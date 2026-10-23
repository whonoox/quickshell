import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Quickshell.Io


Scope{  
    id: root
    readonly property var battery: UPower.displayDevice
    
    property bool hideBar: true

    readonly property int batteryState: UPower.displayDevice.state
    readonly property bool isCharging: battery.state === UPowerDeviceState.Charging
    readonly property bool criticalBattery: battery.percentage <= 0.20 && !isCharging
    readonly property bool lowBattery: battery.percentage <= 0.25
    readonly property bool mediumBattery: battery.percentage <= 0.50
    readonly property bool highBattery: battery.percentage <= 0.75
    readonly property bool fullBattery: battery.percentage === 1.00

    onCriticalBatteryChanged: {
        if (criticalBattery) {
            root.hideBar = false
        }
    }

    function reveal() {
        if (!criticalBattery) {
            root.hideBar = false
            autoHide.restart()
        }
    }

    onBatteryStateChanged: {
        root.reveal()
    }

    onHideBarChanged: {
        if (!root.hideBar && !criticalBattery) {
            autoHide.restart()
        } else {
            autoHide.stop()
        }
    }

    Timer {
        id: autoHide
        interval: 3500
        onTriggered: {
            root.hideBar = true
        }
    }

    // IPC Handler
    IpcHandler {
        target: "batteryBar"
        function toggle() {
            if (!criticalBattery) {
                if (root.hideBar) {
                    root.reveal()
                } else {
                    root.hideBar = true
                    autoHide.stop()
                }
            }
        }
        function open() {
            root.reveal()
        }
        function close() {
            if (!criticalBattery) {
                root.hideBar = true
                autoHide.stop()
            }
        }
    }

    GlobalShortcut {
        name: "batteryToggle"
        description: "Show the current battery information with the panel window"
        appid: "quickshell"
        onPressed: {
            if (!criticalBattery) {
                if (root.hideBar) {
                    root.reveal()
                } else {
                    root.hideBar = true
                    autoHide.stop()
                }
            }
        }
    }

    Component.onCompleted: {
        if (criticalBattery) {
            root.hideBar = false
        }
    }

    BarVariants {
        PanelWindow {
            id: panelWindow
            required property var modelData

            screen: modelData
            visible: false

            anchors.right: true

            WlrLayershell.namespace: "battery-panel-main"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            implicitWidth: 48
            implicitHeight: 160 + Theme.spacing * 4 + 8
            color: "transparent"

            mask: Region {
                item: !root.hideBar ? pillContainer : null
            }

            Item {
                id: pillContainer
                width: parent.width
                height: parent.height
                x: width + 10

                Component.onCompleted: {
                    if (!root.hideBar) {
                        panelWindow.visible = true
                        pillContainer.x = 0
                    }
                }

                NumberAnimation {
                    id: slideAnim
                    target: pillContainer
                    property: "x"
                    duration: 250
                    easing.type: Easing.OutCubic
                    onFinished: {
                        if (root.hideBar) {
                            panelWindow.visible = false
                        }
                    }
                }

                Connections {
                    target: root
                    function onHideBarChanged() {
                        if (!root.hideBar) {
                            panelWindow.visible = true
                            slideAnim.stop()
                            slideAnim.from = pillContainer.x
                            slideAnim.to = 0
                            slideAnim.start()
                        } else {
                            slideAnim.stop()
                            slideAnim.from = pillContainer.x
                            slideAnim.to = pillContainer.width + 10
                            slideAnim.start()
                        }
                    }
                }

                // Unified single-vector background contour (position: centerRight)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "centerRight"
                    color: Theme.bgc
                    radius: Theme.rounding
                    cornerRadius: Theme.rounding
                    borderWidth: Theme.borderWidth
                }

                FlexboxLayout {
                    id: batteryFlex
                    anchors.fill: parent
                    anchors.topMargin: Theme.rounding + Theme.spacing * 2
                    anchors.bottomMargin: Theme.rounding + Theme.spacing * 2
                    anchors.leftMargin: Theme.spacing + Theme.borderWidth
                    anchors.rightMargin: Theme.borderWidth
                    direction: FlexboxLayout.Column
                    alignItems: FlexboxLayout.AlignCenter
                    gap: Theme.spacing / 2

                    Rectangle {
                        topLeftRadius: Theme.rounding
                        topRightRadius: Theme.rounding
                        bottomLeftRadius: 4
                        bottomRightRadius: 4
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.highBattery ? Theme.brandBgc : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Rectangle {
                        radius: 4
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.mediumBattery ? Theme.brandBgc : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        text: Math.round(root.battery.percentage * 100)
                        color: root.criticalBattery ? "red" : Theme.brand
                        font.family: Theme.brandFont
                        font.pixelSize: Theme.rounding
                        font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase
                    }
                    Rectangle {
                        radius: 4
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.lowBattery ? Theme.brandBgc : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Rectangle {
                        id: batteryBottom
                        topLeftRadius: 4
                        topRightRadius: 4
                        bottomLeftRadius: Theme.rounding
                        bottomRightRadius: Theme.rounding
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.criticalBattery ? "red" : root.lowBattery ? "orange" : Theme.brand
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }

                Image {
                    id: chargingIcon
                    anchors.bottom: batteryFlex.bottom
                    anchors.bottomMargin: Theme.spacing / 2
                    anchors.horizontalCenter: batteryFlex.horizontalCenter
                    visible: root.battery.state === UPowerDeviceState.Charging
                    source: root.battery.percentage >= 0.20 ? "decorations/lightning-fill.svg" : "decorations/lightning-fill-red.svg"
                    width: 14
                    height: 14
                    sourceSize.width: 14
                    sourceSize.height: 14
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }
}
