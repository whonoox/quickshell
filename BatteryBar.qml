import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower


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

                implicitWidth: 36
                implicitHeight: 120 + Theme.spacing * 4
                color:"transparent"
                margins.right: root.hideBar ? implicitWidth * -1 : 0

                Component.onCompleted: {
                    console.log(root.battery.state === UPowerDeviceState.Charging)
                }

                ScoopShape{
                    anchors.top: parent.top
                    anchors.right: parent.right
                    cornerPosition: scoopPosition.topLeft
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: Theme.rounding
                    anchors.bottomMargin: Theme.rounding
                    color: Theme.bgc
                    bottomLeftRadius: Theme.rounding - Theme.spacing
                    topLeftRadius: Theme.rounding - Theme.spacing
                }

                FlexboxLayout {
                    id: batteryFlex
                    anchors.fill: parent
                    anchors.topMargin: Theme.rounding + Theme.spacing
                    anchors.bottomMargin: Theme.rounding + Theme.spacing
                    anchors.leftMargin: Theme.spacing
                    // anchors.rightMargin: Theme.spacing / 2
                    direction: FlexboxLayout.Column
                    alignItems: FlexboxLayout.AlignCenter
                    gap: Theme.spacing / 2

                    Rectangle {
                        topLeftRadius: Theme.rounding
                        topRightRadius: Theme.spacing
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
                        bottomRightRadius: Theme.spacing
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.criticalBattery ? "red" : root.lowBattery ? "orange" : Theme.brand
                    }
                    
                }

                Text {
                    anchors.bottom: batteryFlex.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: Theme.spacing / 2
                    text: root.battery.state === UPowerDeviceState.Charging ? "⚡️":""
                    color: root.battery.percentage >= 0.20 ? Theme.brand : "red"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.spacing * 2
                }

                ScoopShape{
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    cornerPosition: scoopPosition.bottomLeft
                }
            }

    }
}