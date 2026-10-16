import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Output volume island, pinned to the left edge and built to the same language
// as BatteryBar: a vertical pill that slides off-screen to hide, with a run of
// equal segments that fill to the current level.
//
// State is read through pactl rather than Quickshell's Pipewire service. The
// Pipewire node for the default sink never leaves `ready=false` with zero
// channels here, so `sink.audio.volume` reads 0 and writes are discarded --
// verified against wpctl, which kept reporting the real level. pactl is the
// same source omarchy-audio-output-volume reads, so the bar and the OSD agree.
//
// Writes go through the omarchy helpers rather than pactl directly, so adjusting
// volume from the bar raises the same OSD the volume keys do.
Scope {
    id: root

    // 0.0 - 1.0. Over-amplification is tracked separately because the meter has
    // to stay full at 100% instead of overflowing the pill.
    property real volume: 0
    property bool muted: false
    property bool available: false

    readonly property int segments: 6
    readonly property int litBars: (muted || volume <= 0)
        ? 0
        : Math.min(6, Math.max(1, Math.ceil(volume * 6)))
    readonly property bool boosted: volume > 1.0

    property bool hideBar: true

    readonly property string probeCommand: 'sink="$(omarchy-audio-output-sink 2>/dev/null)"; '
        + 'if [ -z "$sink" ]; then echo "none"; exit 0; fi; '
        + 'pactl get-sink-volume "$sink" 2>/dev/null | awk \'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /%/) { sub("%", "", $i); print $i; exit } }\'; '
        + 'pactl get-sink-mute "$sink" 2>/dev/null | awk \'{ print ($NF == "yes") ? "muted" : "live" }\''

    // Refreshes the meter. Called on open, on a short timer while visible, and
    // immediately after any change this bar makes so the segments never lag
    // behind the OSD.
    function refresh() {
        if (probeProcess.running) return
        probeProcess.running = true
    }

    function reveal() {
        PopoutCoordinator.claimHud("audio")
        root.hideBar = false
        autoHide.restart()
    }

    // Relative steps, so the OSD the helpers raise matches what the bar shows.
    function nudge(percent) {
        if (!root.available) return
        var action = percent >= 0 ? "+" + Math.round(percent) : "-" + Math.abs(Math.round(percent))
        Quickshell.execDetached(["omarchy-audio-output-volume", action])
        root.reveal()
        settle.restart()
    }

    function toggleMute() {
        if (!root.available) return
        Quickshell.execDetached(["omarchy-audio-output-volume", "mute-toggle"])
        root.reveal()
        settle.restart()
    }

    IpcHandler {
        target: "audioBar"

        function toggle(): string { root.hideBar = !root.hideBar; if (!root.hideBar) root.refresh(); return root.hideBar ? "closed" : "open" }
        function open(): string { root.reveal(); root.refresh(); return "ok" }
        function close(): string { root.hideBar = true; return "ok" }
        function refresh(): string { root.refresh(); return "ok" }
        function mute(): string { root.toggleMute(); return "ok" }
        function raise(): string { root.nudge(10); return "ok" }
        function lower(): string { root.nudge(-10); return "ok" }
        function ping(): string { return "ok" }
    }


    Process {
        id: probeProcess
        command: ["bash", "-c", root.probeCommand]
        stdout: StdioCollector {
            waitForEnd: true
            // `this.text`, not a signal argument: onStreamFinished passes no
            // parameter, so reading one yields undefined and the meter never
            // leaves zero.
            onStreamFinished: {
                var lines = String(this.text || "").trim().split("\n")
                var head = String(lines[0] || "").trim()

                if (head === "none" || head === "") {
                    root.available = false
                    root.volume = 0
                    root.muted = false
                    return
                }

                root.available = true
                // pactl allows volumes above 100%; keep them, the meter clamps.
                root.volume = Math.max(0, parseFloat(head) / 100)
                root.muted = String(lines[1] || "").indexOf("muted") !== -1
            }
        }
    }

    property bool _initialized: false

    Process {
        id: pactlSubscriber
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                if (line.indexOf("'change' on sink") !== -1) {
                    root.refresh()
                    if (root._initialized) {
                        root.reveal()
                    }
                }
            }
        }
        onExited: restartSubscriberTimer.restart()
    }

    Timer {
        id: restartSubscriberTimer
        interval: 1000
        onTriggered: pactlSubscriber.running = true
    }

    Component.onCompleted: {
        root.refresh()
        Qt.callLater(function() {
            root._initialized = true
        })
    }

    onHideBarChanged: {
        if (!root.hideBar) {
            PopoutCoordinator.claimHud("audio")
            autoHide.restart()
        } else {
            PopoutCoordinator.releaseHud("audio")
            autoHide.stop()
        }
    }

    Connections {
        target: PopoutCoordinator
        function onActiveHudChanged() {
            if (PopoutCoordinator.activeHud !== "" && PopoutCoordinator.activeHud !== "audio") {
                root.hideBar = true
            }
        }
    }

    Timer {
        id: autoHide
        interval: 3500
        onTriggered: root.hideBar = true
    }

    // After a change the helper has not necessarily talked to pactl yet, so
    // re-probe once things have settled rather than only on the poll tick.
    Timer {
        id: settle
        interval: 180
        onTriggered: root.refresh()
    }

    Timer {
        interval: 900
        repeat: true
        running: !root.hideBar && root.available
        onTriggered: root.refresh()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors.left: true

            WlrLayershell.namespace: "audio-panel-main"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            implicitWidth: 48
            implicitHeight: 160 + Theme.spacing * 4 + 8
            color: "transparent"
            margins.left: root.hideBar ? implicitWidth * -1 : 0

            // Unified single-vector background contour (position: centerLeft)
            ScoopV2 {
                id: backgroundShape
                anchors.fill: parent
                position: "centerLeft"
                color: Theme.bgc
                radius: Theme.rounding
                cornerRadius: Theme.rounding
                borderWidth: Theme.borderWidth
            }

            FlexboxLayout {
                id: volumeFlex
                anchors.fill: parent
                anchors.topMargin: Theme.rounding + Theme.spacing * 2
                anchors.bottomMargin: Theme.rounding + Theme.spacing * 2
                anchors.leftMargin: Theme.borderWidth
                anchors.rightMargin: Theme.spacing + Theme.borderWidth
                direction: FlexboxLayout.Column
                alignItems: FlexboxLayout.AlignCenter
                gap: Theme.spacing / 2

                // Bar 6 (Top: 84% - 100%)
                Rectangle {
                    topLeftRadius: Theme.rounding
                    topRightRadius: Theme.rounding
                    bottomLeftRadius: 4
                    bottomRightRadius: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.litBars >= 6 ? (root.boosted ? Theme.yellow : Theme.brand) : Theme.brandBgc
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                // Bar 5 (67% - 83%)
                Rectangle {
                    radius: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.litBars >= 5 ? Theme.brand : Theme.brandBgc
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                // Bar 4 (51% - 66%)
                Rectangle {
                    radius: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.litBars >= 4 ? Theme.brand : Theme.brandBgc
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Text {
                    text: String(Math.round(Math.min(1, root.volume) * 100)) + (root.boosted ? "+" : "")
                    color: root.muted ? Theme.red : Theme.brand
                    font.family: Theme.brandFont
                    font.pixelSize: root.boosted ? 16 : Theme.rounding
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                }

                // Bar 3 (34% - 50%)
                Rectangle {
                    radius: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.litBars >= 3 ? Theme.brand : Theme.brandBgc
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                // Bar 2 (17% - 33%)
                Rectangle {
                    radius: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.litBars >= 2 ? Theme.brand : Theme.brandBgc
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                // Bar 1 (Bottom: 1% - 16%)
                Rectangle {
                    id: bottomBar
                    topLeftRadius: 4
                    topRightRadius: 4
                    bottomLeftRadius: Theme.rounding
                    bottomRightRadius: Theme.rounding
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.litBars >= 1 ? Theme.brand : Theme.brandBgc
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: root.muted ? "" : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: root.litBars >= 1
                            ? Theme.bgc
                            : (root.muted ? Theme.red : Theme.brand)
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }

            // Wheel steps the level, click toggles mute, and either one keeps
            // the pill up long enough to read the result.
            MouseArea {
                id: inputArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: root.toggleMute()
                onEntered: autoHide.stop()
                onExited: autoHide.restart()
                onWheel: function (wheel) {
                    root.nudge(wheel.angleDelta.y > 0 ? 10 : -10)
                    autoHide.restart()
                    wheel.accepted = true
                }
            }
        }
    }
}