import Quickshell
import Quickshell.Hyprland
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

    // IPC Handler
    IpcHandler {
        target: "batteryBar"
        function toggle() {
            if (!criticalBattery) {
                hideBar = !hideBar
            }
        }
        function open() {
            hideBar = false
        }
        function close() {
            if (!criticalBattery) {
                hideBar = true
            }
        }
    }

    GlobalShortcut {
        name: "batteryToggle"
        description: "Show the current battery information with the panel window"
        appid: "quickshell"
        onPressed: {
            if (!criticalBattery) {
                hideBar = !hideBar
            }
        }
    }

    onBatteryStateChanged: {
        root.hideBar = false
    }

    Timer {
        interval: 3500
        running: !hideBar && !criticalBattery
        onTriggered: {
            hideBar = true
        }
    }

    Component.onCompleted: {
        if (criticalBattery) {
            root.hideBar = false
        }
    }

    Variants {
            model: Quickshell.screens

            PanelWindow {
                required property var modelData

                screen: modelData

                anchors.right: true

                exclusionMode: ExclusionMode.Normal

                implicitWidth: 48
                implicitHeight: 160 + Theme.spacing * 4 + 8
                color: "transparent"
                margins.right: root.hideBar ? implicitWidth * -1 : 0

                // Unified single-vector background contour (position: centerRight)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "centerRight"
                    color: Theme.bgc
                    radius: Theme.rounding
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
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.highBattery ? Theme.brandBgc : Theme.brand
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.mediumBattery ? Theme.brandBgc : Theme.brand
                    }
                    Text {
                        text: Math.round(root.battery.percentage * 100)
                        color: root.criticalBattery ? "red" : Theme.brand
                        font.family: Theme.brandFont
                        font.pixelSize: Theme.rounding
                        font.weight: Font.Bold  
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.lowBattery ? Theme.brandBgc : Theme.brand
                    }
                    Rectangle {
                        id: batteryBottom
                        bottomLeftRadius: Theme.rounding
                        bottomRightRadius: Theme.rounding
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.criticalBattery ? "red" : root.lowBattery ? "orange" : Theme.brand
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
