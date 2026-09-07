import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root

    property bool opened: false
    onOpenedChanged: console.log(">>> [ScoopTestPanel] opened is now:", opened)

    property real customRadius: Theme.rounding
    onCustomRadiusChanged: {
        var minReqH = 3 * customRadius;
        if (hPanelHeight < minReqH) {
            hPanelHeight = minReqH;
        }
        var minReqW = 4 * customRadius;
        if (hPanelWidth < minReqW) {
            hPanelWidth = minReqW;
        }
    }

    property color previewColor: "#ffffff"
    property color frameColor: Theme.darkerBackground
    readonly property color textColor: (previewColor === "#ffffff" || previewColor === "#f5f5f5" || previewColor === "#e2e8f0") ? "#0a0a0a" : Theme.brand

    property real hPanelWidth: Math.max(180, 4 * customRadius)
    property real hPanelHeight: Math.max(68, 3 * customRadius)

    IpcHandler {
        target: "scoopTest"
        function toggle() {
            root.opened = !root.opened
        }
        function open() {
            root.opened = true
        }
        function close() {
            root.opened = false
        }
    }

    GlobalShortcut {
        name: "scoopTestToggle"
        description: "Toggle Scoop V2 Test Inspector"
        appid: "quickshell"
        onPressed: root.opened = !root.opened
    }

    Variants {
        model: root.opened ? [Quickshell.screens[0]] : []

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

            WlrLayershell.namespace: "scoop-v2-inspector"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            // Dimmed semi-transparent backdrop
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.65)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.opened = false
                }
            }

            // ================================================================
            // Simulated Display Frame (Matches user sketch perimeter)
            // ================================================================
            Rectangle {
                id: displayFrame
                anchors.centerIn: parent
                width: 900
                height: 620
                color: root.frameColor
                radius: Theme.rounding
                border.color: Theme.selection
                border.width: 2
                clip: true

                // Consume clicks so clicking inside the test frame doesn't dismiss
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                }

                // ------------------------------------------------------------
                // 1. TOP LEFT
                // ------------------------------------------------------------
                ScoopV2 {
                    id: pTopLeft
                    position: "topLeft"
                    anchors.top: parent.top
                    anchors.left: parent.left
                    width: Math.max(root.hPanelWidth, minWidth)
                    height: Math.max(root.hPanelHeight, minHeight)
                    color: root.previewColor
                    radius: root.customRadius
                    cornerRadius: Theme.rounding

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -root.customRadius / 2
                        anchors.verticalCenterOffset: -root.customRadius / 2
                        text: "top left"
                        color: root.textColor
                        font.family: Theme.brandFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                }

                // ------------------------------------------------------------
                // 2. TOP CENTER
                // ------------------------------------------------------------
                ScoopV2 {
                    id: pTopCenter
                    position: "topCenter"
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(root.hPanelWidth + 20, minWidth)
                    height: Math.max(root.hPanelHeight, minHeight)
                    color: root.previewColor
                    radius: root.customRadius

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -root.customRadius / 4
                        text: "top center"
                        color: root.textColor
                        font.family: Theme.brandFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                }

                // ------------------------------------------------------------
                // 3. TOP RIGHT
                // ------------------------------------------------------------
                ScoopV2 {
                    id: pTopRight
                    position: "topRight"
                    anchors.top: parent.top
                    anchors.right: parent.right
                    width: Math.max(root.hPanelWidth, minWidth)
                    height: Math.max(root.hPanelHeight, minHeight)
                    color: root.previewColor
                    radius: root.customRadius
                    cornerRadius: Theme.rounding

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: root.customRadius / 2
                        anchors.verticalCenterOffset: -root.customRadius / 2
                        text: "top right"
                        color: root.textColor
                        font.family: Theme.brandFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                }

                // ------------------------------------------------------------
                // 4. CENTER RIGHT
                // ------------------------------------------------------------
                ScoopV2 {
                    id: pCenterRight
                    position: "centerRight"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(root.hPanelHeight, minWidth)
                    height: Math.max(170, minHeight)
                    color: root.previewColor
                    radius: root.customRadius

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: root.customRadius / 4
                        text: "center\nright"
                        horizontalAlignment: Text.AlignHCenter
                        color: root.textColor
                        font.family: Theme.brandFont
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                }

                // ------------------------------------------------------------
                // 5. BOTTOM RIGHT
                // ------------------------------------------------------------
                ScoopV2 {
                    id: pBottomRight
                    position: "bottomRight"
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    width: Math.max(root.hPanelWidth, minWidth)
                    height: Math.max(root.hPanelHeight, minHeight)
                    color: root.previewColor
                    radius: root.customRadius
                    cornerRadius: Theme.rounding

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: root.customRadius / 2
                        anchors.verticalCenterOffset: root.customRadius / 2
                        text: "bottom right"
                        color: root.textColor
                        font.family: Theme.brandFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                }

                // ------------------------------------------------------------
                // 6. BOTTOM CENTER
                // ------------------------------------------------------------
                ScoopV2 {
                    id: pBottomCenter
                    position: "bottomCenter"
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(root.hPanelWidth + 20, minWidth)
                    height: Math.max(root.hPanelHeight, minHeight)
                    color: root.previewColor
                    radius: root.customRadius

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: root.customRadius / 4
                        text: "bottom center"
                        color: root.textColor
                        font.family: Theme.brandFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                }

                // ------------------------------------------------------------
                // 7. BOTTOM LEFT
                // ------------------------------------------------------------
                ScoopV2 {
                    id: pBottomLeft
                    position: "bottomLeft"
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: Math.max(root.hPanelWidth, minWidth)
                    height: Math.max(root.hPanelHeight, minHeight)
                    color: root.previewColor
                    radius: root.customRadius
                    cornerRadius: Theme.rounding

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -root.customRadius / 2
                        anchors.verticalCenterOffset: root.customRadius / 2
                        text: "bottom left"
                        color: root.textColor
                        font.family: Theme.brandFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                }

                // ------------------------------------------------------------
                // 8. CENTER LEFT
                // ------------------------------------------------------------
                ScoopV2 {
                    id: pCenterLeft
                    position: "centerLeft"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(root.hPanelHeight, minWidth)
                    height: Math.max(170, minHeight)
                    color: root.previewColor
                    radius: root.customRadius

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -root.customRadius / 4
                        text: "center\nleft"
                        horizontalAlignment: Text.AlignHCenter
                        color: root.textColor
                        font.family: Theme.brandFont
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                }

                // ============================================================
                // CENTER CONTROL & VERIFICATION CARD
                // ============================================================
                Rectangle {
                    anchors.centerIn: parent
                    width: 480
                    height: 310
                    color: Theme.darkBackground
                    radius: 16
                    border.color: Theme.selection
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 10

                        // Header
                        RowLayout {
                            Layout.fillWidth: true

                            ColumnLayout {
                                spacing: 2
                                Text {
                                    text: "Scoop V2 Inspector"
                                    color: Theme.brightForeground
                                    font.family: Theme.brandFont
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                }
                                Text {
                                    text: "8-Position Unified Continuous Vector Shapes"
                                    color: Theme.lightForeground
                                    font.family: Theme.systemFont
                                    font.pixelSize: 11
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Close Button
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                color: closeArea.containsMouse ? Theme.urgent : Theme.surface
                                border.color: Theme.selection
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: closeArea.containsMouse ? "#ffffff" : Theme.lightForeground
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    id: closeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.opened = false
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.selection
                        }

                        // Panel Color Presets (White / Light Grey / Accent / Dark)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Panel Fill:"
                                color: Theme.lightForeground
                                font.family: Theme.systemFont
                                font.pixelSize: 12
                            }

                            Repeater {
                                model: [
                                    { label: "White", val: "#ffffff" },
                                    { label: "Light Grey", val: "#e2e8f0" },
                                    { label: "Accent", val: String(Theme.accent) },
                                    { label: "Dark", val: String(Theme.bgc) }
                                ]

                                Rectangle {
                                    required property var modelData
                                    width: 74
                                    height: 26
                                    radius: 6
                                    color: String(root.previewColor).toLowerCase() === String(modelData.val).toLowerCase() ? Theme.brand : Theme.surface
                                    border.color: Theme.selection
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: String(root.previewColor).toLowerCase() === String(modelData.val).toLowerCase() ? Theme.darkerBackground : Theme.brightForeground
                                        font.family: Theme.brandFont
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.previewColor = modelData.val
                                    }
                                }
                            }
                        }

                        // Radius Presets
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Radius:"
                                color: Theme.lightForeground
                                font.family: Theme.systemFont
                                font.pixelSize: 12
                            }

                            Repeater {
                                model: [16, 20, 24, 28]

                                Rectangle {
                                    required property int modelData
                                    width: 44
                                    height: 26
                                    radius: 6
                                    color: root.customRadius === modelData ? Theme.brand : Theme.surface
                                    border.color: Theme.selection
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData + "px"
                                        color: root.customRadius === modelData ? Theme.darkerBackground : Theme.brightForeground
                                        font.family: Theme.brandFont
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.customRadius = modelData
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "r=" + root.customRadius + "px (minH=" + (3 * root.customRadius) + "px)"
                                color: Theme.brand
                                font.family: Theme.brandFont
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                        }

                        // Width / Height Resizing Steppers
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Width:"
                                color: Theme.lightForeground
                                font.family: Theme.systemFont
                                font.pixelSize: 12
                            }

                            Rectangle {
                                width: 28; height: 24; radius: 5
                                color: Theme.surface; border.color: Theme.selection; border.width: 1
                                Text { anchors.centerIn: parent; text: "-"; color: Theme.brightForeground; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.hPanelWidth = Math.max(4 * root.customRadius, root.hPanelWidth - 20) }
                            }
                            Text {
                                text: String(root.hPanelWidth) + "px"
                                color: Theme.brightForeground
                                font.family: Theme.brandFont
                                font.pixelSize: 11
                            }
                            Rectangle {
                                width: 28; height: 24; radius: 5
                                color: Theme.surface; border.color: Theme.selection; border.width: 1
                                Text { anchors.centerIn: parent; text: "+"; color: Theme.brightForeground; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.hPanelWidth = Math.min(280, root.hPanelWidth + 20) }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "Height:"
                                color: Theme.lightForeground
                                font.family: Theme.systemFont
                                font.pixelSize: 12
                            }

                            Rectangle {
                                width: 28; height: 24; radius: 5
                                color: Theme.surface; border.color: Theme.selection; border.width: 1
                                Text { anchors.centerIn: parent; text: "-"; color: Theme.brightForeground; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.hPanelHeight = Math.max(3 * root.customRadius, root.hPanelHeight - 6) }
                            }
                            Text {
                                text: String(root.hPanelHeight) + "px"
                                color: Theme.brightForeground
                                font.family: Theme.brandFont
                                font.pixelSize: 11
                            }
                            Rectangle {
                                width: 28; height: 24; radius: 5
                                color: Theme.surface; border.color: Theme.selection; border.width: 1
                                Text { anchors.centerIn: parent; text: "+"; color: Theme.brightForeground; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.hPanelHeight = Math.min(120, root.hPanelHeight + 6) }
                            }
                        }

                        // Shortcut hint
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Toggle via: qs ipc call scoopTest toggle"
                                color: Theme.darkForeground
                                font.family: Theme.systemFont
                                font.pixelSize: 10
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Click backdrop to dismiss"
                                color: Theme.darkForeground
                                font.family: Theme.systemFont
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }
}
