import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: root

    // Corner island visibility: visible by default, slides down off-screen
    // when a window on the focused workspace enters fullscreen or full-width mode,
    // matching the WorkspaceBar's top-left behavior.
    property bool hudVisible: true

    function isFullWidthMode() {
        var fw = Hyprland.focusedWorkspace
        if (!fw) return false
        if (fw.hasFullscreen || (fw.lastIpcObject && fw.lastIpcObject.hasfullscreen)) {
            return true
        }
        if (fw.toplevels) {
            var tops = fw.toplevels.values
            for (var i = 0; i < tops.length; i++) {
                var t = tops[i]
                if (t.lastIpcObject && (t.lastIpcObject.fullscreen !== 0 || t.lastIpcObject.fullscreenClient !== 0)) {
                    return true
                }
            }
        }
        return false
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var name = String(event.name || "")
            if (name === "fullscreen" || name === "workspace" || name === "focusedmon" || name === "activewindowv2") {
                root.hudVisible = !root.isFullWidthMode()
            }
        }
    }

    Component.onCompleted: {
        root.hudVisible = !root.isFullWidthMode()
    }

    // ------------------------------------------------------------------
    // Global Shortcuts
    // ------------------------------------------------------------------
    GlobalShortcut {
        name: "notifToggle"
        description: "Toggle notifications Do Not Disturb"
        appid: "quickshell"
        onPressed: ToggleState.toggleDnd()
    }

    GlobalShortcut {
        name: "micToggle"
        description: "Toggle microphone mute"
        appid: "quickshell"
        onPressed: ToggleState.toggleMic()
    }

    // ------------------------------------------------------------------
    // IPC Handler
    // ------------------------------------------------------------------
    IpcHandler {
        target: "toggleBar"

        function toggleNotif(): string {
            ToggleState.toggleDnd()
            return ToggleState.dnd ? "dnd_on" : "dnd_off"
        }

        function toggleMic(): string {
            ToggleState.toggleMic()
            return ToggleState.micMuted ? "muted" : "live"
        }

        function notifStatus(): string {
            return ToggleState.dnd ? "dnd_on" : "dnd_off"
        }

        function micStatus(): string {
            return ToggleState.micMuted ? "muted" : "live"
        }

        function status(): string {
            return JSON.stringify({
                notifDnd: ToggleState.dnd,
                micMuted: ToggleState.micMuted
            })
        }
    }

    // ------------------------------------------------------------------
    // Panel Window (Bottom-Left Corner)
    // ------------------------------------------------------------------
    BarVariants {
        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            visible: root.hudVisible || (cardContainer.y < (parent.height + 10))

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "toggle-panel-main"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region {
                item: root.hudVisible ? cardContainer : null
            }

            // Bottom-Left Anchored Card Container
            Item {
                id: cardContainer
                anchors.left: parent.left
                y: root.hudVisible ? (parent.height - height) : (parent.height + 20)

                width: contentRow.implicitWidth + Theme.spacing * 4 + Theme.rounding + Theme.borderWidth
                height: 44 + Theme.rounding + Theme.borderWidth

                Behavior on y {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // Unified single-vector background contour (position: bottomLeft)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "bottomLeft"
                    color: Theme.bgc
                    radius: Theme.rounding
                    cornerRadius: Theme.rounding
                    borderWidth: Theme.borderWidth
                }

                // Inner Content Area
                Item {
                    id: background
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.rounding + Theme.borderWidth
                    anchors.top: parent.top
                    anchors.topMargin: Theme.rounding + Theme.borderWidth

                    Row {
                        id: contentRow
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacing * 1.5

                        // 1. Notification DND Toggle Button
                        Item {
                            id: notifButton
                            width: 32
                            height: 32

                            readonly property bool isDnd: ToggleState.dnd
                            readonly property bool isHovered: notifMouse.containsMouse

                            Rectangle {
                                id: notifBg
                                anchors.fill: parent
                                radius: 8

                                color: notifButton.isDnd
                                    ? (notifButton.isHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16))
                                    : (notifButton.isHovered ? Theme.selection : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5))

                                border.color: notifButton.isDnd
                                    ? Theme.accent
                                    : (notifButton.isHovered ? Theme.selection : Qt.rgba(Theme.selection.r, Theme.selection.g, Theme.selection.b, 0.5))
                                border.width: 1

                                scale: notifMouse.pressed ? 0.92 : (notifButton.isHovered ? 1.05 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Image {
                                    id: notifRawIcon
                                    anchors.centerIn: parent
                                    width: 17
                                    height: 17
                                    sourceSize.width: 34
                                    sourceSize.height: 34
                                    source: notifButton.isDnd ? "decorations/bell-slash.svg" : "decorations/bell.svg"
                                    fillMode: Image.PreserveAspectFit
                                    visible: false
                                }

                                MultiEffect {
                                    anchors.fill: notifRawIcon
                                    source: notifRawIcon
                                    colorization: 1.0
                                    colorizationColor: notifButton.isDnd
                                        ? Theme.accent
                                        : (notifButton.isHovered ? Theme.brightForeground : Theme.foreground)
                                    Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    id: notifMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ToggleState.toggleDnd()
                                }
                            }
                        }

                        // 2. Microphone Mute Toggle Button
                        Item {
                            id: micButton
                            width: 32
                            height: 32

                            readonly property bool isMuted: ToggleState.micMuted
                            readonly property bool isHovered: micMouse.containsMouse

                            Rectangle {
                                id: micBg
                                anchors.fill: parent
                                radius: 8

                                color: micButton.isMuted
                                    ? (micButton.isHovered ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.28) : Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.16))
                                    : (micButton.isHovered ? Theme.selection : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5))

                                border.color: micButton.isMuted
                                    ? Theme.red
                                    : (micButton.isHovered ? Theme.selection : Qt.rgba(Theme.selection.r, Theme.selection.g, Theme.selection.b, 0.5))
                                border.width: 1

                                scale: micMouse.pressed ? 0.92 : (micButton.isHovered ? 1.05 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Image {
                                    id: micRawIcon
                                    anchors.centerIn: parent
                                    width: 17
                                    height: 17
                                    sourceSize.width: 34
                                    sourceSize.height: 34
                                    source: micButton.isMuted ? "decorations/microphone-slash.svg" : "decorations/microphone.svg"
                                    fillMode: Image.PreserveAspectFit
                                    visible: false
                                }

                                MultiEffect {
                                    anchors.fill: micRawIcon
                                    source: micRawIcon
                                    colorization: 1.0
                                    colorizationColor: micButton.isMuted
                                        ? Theme.red
                                        : (micButton.isHovered ? Theme.brightForeground : Theme.foreground)
                                    Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    id: micMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ToggleState.toggleMic()
                                }
                            }
                        }
                    }
                }

                // ------------------------------------------------------------
                // Tooltip Capsule (Hover Hint)
                // ------------------------------------------------------------
                Rectangle {
                    id: tooltipBox
                    readonly property bool active: notifMouse.containsMouse || micMouse.containsMouse
                    readonly property string tipText: notifMouse.containsMouse
                        ? (ToggleState.dnd ? "Notifications Silenced  (Super+Alt+N)" : "Notifications Active  (Super+Alt+N)")
                        : (ToggleState.micMuted ? "Microphone Muted  (Mic)" : "Microphone Active  (Mic)")

                    visible: opacity > 0.01
                    opacity: active ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    anchors.bottom: parent.top
                    anchors.bottomMargin: 8
                    anchors.left: parent.left
                    anchors.leftMargin: notifMouse.containsMouse ? 4 : (micButton.x + 4)
                    Behavior on anchors.leftMargin { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    width: tipContent.implicitWidth + 16
                    height: tipContent.implicitHeight + 8
                    radius: 6
                    color: Theme.darkerBackground
                    border.color: Theme.selection
                    border.width: 1

                    Text {
                        id: tipContent
                        anchors.centerIn: parent
                        text: tooltipBox.tipText
                        color: Theme.foreground
                        font.family: Theme.systemFont
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
