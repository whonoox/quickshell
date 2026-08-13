import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower


Scope{  
    id: root
    readonly property var battery: UPower.displayDevice
    
    property bool hideBar: false

    GlobalShortcut{
        name: "batteryToggle"
        description: "Show the current battery information with the panel window"
        appid: "quickshell"
        onPressed: {
            root.hideBar = !root.hideBar
        }
    }

    // Timer {
    //     interval: 3000
    //     running: !root.hideBar
    //     onTriggered: {
    //         root.hideBar = true
    //     }
    // }

    Variants {
            model: Quickshell.screens

            PanelWindow {
                required property var modelData

                screen: modelData

                anchors.right: true

                exclusionMode: ExclusionMode.Normal

                implicitWidth: 30
                implicitHeight: 120 + Theme.spacing * 4
                color:"transparent"

                 margins.right: root.hideBar ? implicitWidth * -1 : 0

                Component.onCompleted: {
                    console.log(root.battery.percentage)
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
                    id: flexLayout
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
                        color: root.battery.percentage >= 0.75 ? Theme.brand : Theme.brandBgc
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.battery.percentage >= 0.5 ? Theme.brand : Theme.brandBgc
                    }
                    Text {
                        text: Math.round(root.battery.percentage * 100)
                        color: root.battery.percentage >= 0.20 ? Theme.brand : "red"
                        font.family: "Nuuxfont"
                        font.pixelSize: Theme.rounding
                        font.weight: Font.Bold  
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.battery.percentage >= 0.25 ? Theme.brand : Theme.brandBgc
                    }
                    Rectangle {
                        bottomLeftRadius: Theme.rounding
                        bottomRightRadius: Theme.spacing
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.battery.percentage >= 0.20 ? Theme.brand : "red"
                    }
                }

                // Text {
                //     anchors.centerIn: parent
                //     anchors.horizontalCenterOffset: Theme.spacing / 2
                //     text: (root.battery.percentage * 100).toString().split('').slice(0,2).join('\n')
                //     color: Theme.brand
                //     font.family: "Nuuxfont"
                //     font.pixelSize: 32
                //     font.weight: Font.Bold
                //     style: Text.Outline
                //     styleColor: Theme.bgc
                //     lineHeight: 0.8             
                // }

                ScoopShape{
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    cornerPosition: scoopPosition.bottomLeft
                }
            }

    }
}