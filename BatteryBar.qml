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
                property real spacing: 6

                screen: modelData

                anchors.right: true

                exclusionMode: ExclusionMode.Normal

                implicitWidth: 30
                implicitHeight: 120 + spacing * 4
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
                    bottomLeftRadius: Theme.rounding - spacing
                    topLeftRadius: Theme.rounding - spacing
                }

                FlexboxLayout {
                    id: flexLayout
                    anchors.fill: parent
                    anchors.topMargin: Theme.rounding + spacing
                    anchors.bottomMargin: Theme.rounding + spacing
                    anchors.leftMargin: spacing
                    direction: FlexboxLayout.Column
                    gap: spacing / 2

                    Rectangle {
                        topLeftRadius: Theme.rounding
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.brand
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.brand
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.brand
                    }
                    Rectangle {
                        bottomLeftRadius: Theme.rounding
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.brand
                    }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: spacing / 2
                    text: (root.battery.percentage * 100).toString().split('').slice(0,2).join('\n')
                    color: Theme.bgc
                    font.family: "Nuuxfont"
                    font.pixelSize: 32
                    font.weight: Font.Bold
                    style: Text.Outline
                    styleColor: Theme.brand
                    lineHeight: 0.8             
                }

                ScoopShape{
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    cornerPosition: scoopPosition.bottomLeft
                }
            }

    }
}