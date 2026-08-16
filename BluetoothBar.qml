import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Hyprland


Scope{  
    id: root
    
    property bool hideBar: false
    // property var wifiDevice: null
    // property var connectedNetwork: null
    readonly property BluetoothDevice connectedBluetoothDevice: Bluetooth.devices.values.find(
        dev => dev.connected === true
    )

    GlobalShortcut{
        name: "bluetoothToggle"
        description: "Show the current bluetooth information with the panel window"
        appid: "quickshell"
        onPressed: {
            hideBar = !hideBar
        }
    }

    Timer {
        interval: 3000
        running: !hideBar
        onTriggered: {
            hideBar = true
        }
    }

    Variants {
            model: Quickshell.screens

            PanelWindow {
                required property var modelData

                screen: modelData

                anchors.right: true
                anchors.top: true

                exclusionMode: ExclusionMode.Normal

                implicitHeight: Theme.rounding * 2.5
                implicitWidth: wifiName.implicitWidth + Theme.rounding * 3
                color: "transparent"

                margins.right: root.hideBar ? implicitWidth * -1 : 0
                margins.top: root.hideBar ? implicitHeight * -1 : 0

                ScoopShape{
                    anchors.top: parent.top
                    anchors.left: parent.left
                    cornerPosition: scoopPosition.bottomLeft
                }

                Rectangle {
                    id: background
                    anchors.fill: parent
                    anchors.leftMargin: Theme.rounding
                    anchors.bottomMargin: Theme.rounding
                    color: Theme.bgc
                    bottomLeftRadius: Theme.rounding
                }

                Text{
                    id: wifiName
                    anchors.left: background.left
                    anchors.verticalCenter: background.verticalCenter
                    anchors.leftMargin: Theme.spacing
                    text: connectedBluetoothDevice.name
                    color: Theme.brand
                    font.family: "Nuuxfont"
                    font.pixelSize: Theme.rounding
                    font.weight: Font.Bold  
                }

                // BluetoothIcon {
                //     anchors.right: parent.right
                //     anchors.top: parent.top
                //     size: 28
                //     color: connectedBluetoothDevice ? Theme.brand : Theme.brandBgc
                // } 

                ScoopShape{
                    bgColor: Theme.brand
                    anchors.top: parent.top
                    anchors.right: parent.right
                    cornerPosition: scoopPosition.bottomLeft
                }

                ScoopShape{
                    bgColor: Theme.brand
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacing
                    anchors.topMargin: Theme.spacing
                    scale: 0.7
                    cornerPosition: scoopPosition.bottomLeft
                }

                ScoopShape{
                    bgColor: Theme.brand
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacing * 2
                    anchors.topMargin: Theme.spacing * 2
                    scale: 0.5
                    cornerPosition: scoopPosition.bottomLeft
                }
                


                ScoopShape{
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    cornerPosition: scoopPosition.bottomLeft
                }
            }

    }
}