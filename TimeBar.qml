import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: root

    property bool hudVisible: false
    property bool isExpanded: false
    readonly property bool hideAll: !hudVisible && !isExpanded
    property real lastToggleTime: 0

    SystemClock {
        id: clock
        precision: root.hideAll ? SystemClock.Minutes : SystemClock.Seconds
    }

    readonly property string time: Qt.formatDateTime(clock.date, "hh:mm:ss AP")
    readonly property string day: Qt.formatDateTime(clock.date, "dddd").toUpperCase()
    readonly property string date: Qt.formatDateTime(clock.date, "MMM dd, yyyy")

    onHideAllChanged: {
        if (hideAll) {
            isExpanded = false
            hudVisible = false
        }
    }

    Component.onCompleted: {
        root.hudVisible = true
    }

    // Auto-hide Timer: Active for both views, auto-collapsing and moving off-screen
    Timer {
        id: autoHideTimer
        interval: 3500
        running: !root.hideAll
        onTriggered: {
            root.isExpanded = false
            root.hudVisible = false
        }
    }

    // IPC Handler
    IpcHandler {
        target: "timeBar"
        function toggle() {
            if (root.hideAll) {
                root.hudVisible = true
                root.isExpanded = false
                autoHideTimer.restart()
            } else if (root.hudVisible && !root.isExpanded) {
                root.isExpanded = true
                root.hudVisible = false
                autoHideTimer.restart()
            } else {
                root.isExpanded = false
                root.hudVisible = false
                autoHideTimer.stop()
            }
        }
        function open() {
            root.hudVisible = true
            root.isExpanded = false
            autoHideTimer.restart()
        }
        function expand() {
            root.isExpanded = true
            root.hudVisible = false
            autoHideTimer.restart()
        }
        function close() {
            root.isExpanded = false
            root.hudVisible = false
            autoHideTimer.stop()
        }
    }

    // Global Shortcut Handler
    GlobalShortcut {
        name: "timeToggle"
        description: "Show Time HUD on first press, expand Date on second press"
        appid: "quickshell"
        onPressed: {
            var now = Date.now()
            if (now - root.lastToggleTime < 250) return
            root.lastToggleTime = now

            if (root.hideAll) {
                // 1st Press: Show time glance HUD
                root.hudVisible = true
                root.isExpanded = false
                autoHideTimer.restart()
            } else if (root.hudVisible && !root.isExpanded) {
                // 2nd Press: Expand into date view and reset timer
                root.isExpanded = true
                root.hudVisible = false
                autoHideTimer.restart()
            } else {
                // 3rd Press or while expanded: Collapse and close
                root.isExpanded = false
                root.hudVisible = false
            }
        }
    }

    // Main Top-Center Island Window
    Variants {
        model: [Quickshell.screens[0]]

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "time-panel-main"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Strict mask: only the visible island captures input; 100% click-through elsewhere
            mask: Region {
                item: !root.hideAll ? cardContainer : null
            }

            // ================================================================
            // Centered Top-Anchored Card Container
            // Smoothly expands width and height, slides vertically off-screen
            // ================================================================
            Item {
                id: cardContainer
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.hideAll ? -(height + 20) : 0

                width: root.isExpanded 
                    ? Math.max(timeText.implicitWidth, dayText.implicitWidth, dateText.implicitWidth) + Theme.rounding * 4
                    : (timeText.implicitWidth + Theme.rounding * 3)

                height: root.isExpanded
                    ? (summaryHeader.height + detailsColumn.implicitHeight + Theme.spacing * 2)
                    : summaryHeader.height

                Behavior on width {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on height {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                // Unified single-vector background contour (position: topCenter)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "topCenter"
                    color: Theme.bgc
                    radius: Theme.rounding
                }

                // Main Content Container
                Item {
                    id: background
                    anchors.fill: parent
                    anchors.leftMargin: Theme.rounding
                    anchors.rightMargin: Theme.rounding
                    clip: true

                    // Click to cycle between collapsed and expanded views with timer reset
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.isExpanded = !root.isExpanded
                            autoHideTimer.restart()
                            if (root.isExpanded) {
                                root.hudVisible = false
                            } else {
                                root.hudVisible = true
                            }
                        }
                    }

                    // ====================================================
                    // 1. SUMMARY (Time Header - Always Visible)
                    // ====================================================
                    Item {
                        id: summaryHeader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: timeText.implicitHeight + Theme.rounding

                        Text {
                            id: timeText
                            anchors.centerIn: parent
                            text: root.time
                            color: Theme.brand
                            font.family: Theme.brandFont
                            font.pixelSize: 22
                            font.weight: Font.Bold
                        }
                    }

                    // ====================================================
                    // 2. DETAILS (Day & Date - Visible when expanded)
                    // ====================================================
                    ColumnLayout {
                        id: detailsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: summaryHeader.bottom
                        anchors.leftMargin: Theme.spacing * 2
                        anchors.rightMargin: Theme.spacing * 2
                        spacing: Theme.spacing
                        visible: root.isExpanded
                        opacity: root.isExpanded ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.selection
                        }

                        // Day of the Week (Prominent in grey / lightForeground)
                        Text {
                            id: dayText
                            Layout.alignment: Qt.AlignHCenter
                            text: root.day
                            color: Theme.lightForeground
                            font.family: Theme.brandFont
                            font.pixelSize: 30
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                        }

                        // Formatted Date (Matched to Time: 22px, Bold, Brand color)
                        Text {
                            id: dateText
                            Layout.alignment: Qt.AlignHCenter
                            text: root.date
                            color: Theme.brand
                            font.family: Theme.brandFont
                            font.pixelSize: 22
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }
    }
}
