import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Display brightness island, pinned to the left edge and built to the same language
// as AudioBar and BatteryBar: a vertical pill that slides off-screen to hide, with
// 6 proportional segments and centered numeral readout.
Scope {
    id: root

    property real brightness: 1.0
    property bool available: false

    readonly property int segments: 6
    readonly property int litBars: brightness <= 0
        ? 0
        : Math.min(6, Math.max(1, Math.ceil(brightness * 6)))

    property bool hideBar: true

    readonly property string probeCommand: 'device="$(omarchy-hw-display 2>/dev/null || echo amdgpu_bl1)"; '
        + 'brightnessctl -d "$device" -m 2>/dev/null | awk -F, \'{ gsub("%", "", $4); print $4; found=1 } END{ if (!found) print "none" }\''

    function refresh() {
        if (probeProcess.running) return
        probeProcess.running = true
    }

    function reveal() {
        PopoutCoordinator.claimHud("brightness")
        root.hideBar = false
        autoHide.restart()
    }

    function nudge(percent) {
        if (!root.available) return
        var action = percent >= 0 ? "+" + Math.round(percent) + "%" : Math.abs(Math.round(percent)) + "%-"
        Quickshell.execDetached(["omarchy-brightness-display", action])
        root.reveal()
        settle.restart()
    }

    IpcHandler {
        target: "brightnessBar"

        function toggle(): string { root.hideBar = !root.hideBar; if (!root.hideBar) root.refresh(); return root.hideBar ? "closed" : "open" }
        function open(): string { root.reveal(); root.refresh(); return "ok" }
        function close(): string { root.hideBar = true; return "ok" }
        function refresh(): string { root.refresh(); return "ok" }
        function raise(): string { root.nudge(10); return "ok" }
        function lower(): string { root.nudge(-10); return "ok" }
        function ping(): string { return "ok" }
    }

    Process {
        id: probeProcess
        command: ["bash", "-c", root.probeCommand]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var text = String(this.text || "").trim()
                if (text === "none" || text === "") {
                    root.available = false
                    return
                }
                root.available = true
                root.brightness = Math.min(1.0, Math.max(0, parseFloat(text) / 100))
            }
        }
    }

    Component.onCompleted: {
        root.refresh()
    }

    onHideBarChanged: {
        if (!root.hideBar) {
            PopoutCoordinator.claimHud("brightness")
            autoHide.restart()
        } else {
            PopoutCoordinator.releaseHud("brightness")
            autoHide.stop()
        }
    }

    Connections {
        target: PopoutCoordinator
        function onActiveHudChanged() {
            if (PopoutCoordinator.activeHud !== "" && PopoutCoordinator.activeHud !== "brightness") {
                root.hideBar = true
            }
        }
    }

    Timer {
        id: autoHide
        interval: 3500
        onTriggered: root.hideBar = true
    }

    Timer {
        id: settle
        interval: 180
        onTriggered: root.refresh()
    }

    Timer {
        interval: 400
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

            WlrLayershell.namespace: "brightness-panel-main"
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
                id: brightnessFlex
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
                    color: root.litBars >= 6 ? Theme.brand : Theme.brandBgc
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
                    text: String(Math.round(Math.min(1, root.brightness) * 100))
                    color: Theme.brand
                    font.family: Theme.brandFont
                    font.pixelSize: Theme.rounding
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
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: root.litBars >= 1 ? Theme.bgc : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }

            // Wheel steps the brightness level
            MouseArea {
                id: inputArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
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
