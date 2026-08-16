import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Hyprland
import Quickshell.Io


Scope{  
    id: root
    
    property bool hideBar: true
    property bool nmtuiRunning: false
    readonly property NetworkDevice connectedWifiDevice: Networking.devices.values.find(
        dev => dev.type === DeviceType.Wifi && dev.state === ConnectionState.Connected
    )

    readonly property var connectedNetwork: connectedWifiDevice.networks.values.find(
        net => net.connected === true
    )

    property var weakSignal: connectedNetwork.signalStrength >= 0
    property var mediumSignal: connectedNetwork.signalStrength >= 0.25
    property var strongSignal: connectedNetwork.signalStrength >= 0.5
    property var veryStrongSignal: connectedNetwork.signalStrength >= 0.75

    GlobalShortcut{
        name: "wifiToggle"
        description: "Show the current wifi information with the panel window"
        appid: "quickshell"
        onPressed: {
            if(hideBar){
                hideBar = !hideBar
            }
            else{
                if(nmtuiRunning){
                    nmtuiRunning = false
                    nmtuiKiller.running = true
                }
                else{
                    nmtuiRunning = true
                    nmtui.running = true
                }
            }
        }
    }

    Process {
        id: nmtui
        running: false
        command: ["hyprctl", "dispatch", "exec", "[float; size 750 500; center] ghostty -e nmtui"]
        // command: Hyprland.dispatch("exec [float; size 750 500; center] ghostty -e nmtui")
    }

    Process {
        id: nmtuiKiller
        running: false
        command: ["pkill", "nmtui"]
    }

    Timer {
        interval: 3000
        running: !hideBar && !nmtuiRunning
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
                    anchors.top: background.top
                    anchors.topMargin: Theme.spacing
                    // anchors.verticalCenter: background.verticalCenter
                    anchors.leftMargin: Theme.spacing
                    text: connectedNetwork.name
                    color: Theme.brand
                    font.family: "Nuuxfont"
                    font.pixelSize: Theme.rounding
                    font.weight: Font.Bold  
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    implicitWidth: Theme.spacing * 4.5
                    implicitHeight: implicitWidth
                    color: root.veryStrongSignal ? Theme.brand : Theme.brandBgc
                    radius: Theme.spacing
                    bottomLeftRadius: Theme.rounding + Theme.spacing
                    border.width: Theme.spacing / 2
                    border.color: Theme.bgc
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    implicitWidth: Theme.spacing * 3.5
                    implicitHeight: implicitWidth
                    color: root.strongSignal ? Theme.brand : Theme.brandBgc
                    radius: Theme.spacing
                    bottomLeftRadius: Theme.rounding + Theme.spacing
                    border.width: Theme.spacing / 2
                    border.color: Theme.bgc
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    implicitWidth: Theme.spacing * 2.5
                    implicitHeight: implicitWidth
                    color: root.mediumSignal ? Theme.brand : Theme.brandBgc
                    radius: Theme.spacing
                    bottomLeftRadius: Theme.rounding + Theme.spacing
                    border.width: Theme.spacing / 2
                    border.color: Theme.bgc
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    implicitWidth: Theme.spacing * 1.5
                    implicitHeight: implicitWidth
                    color: root.weakSignal ? Theme.brand : Theme.brandBgc
                    radius: Theme.spacing
                    bottomLeftRadius: Theme.rounding + Theme.spacing
                    border.width: Theme.spacing / 2
                    border.color: Theme.bgc
                }

                ScoopShape{
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    cornerPosition: scoopPosition.bottomLeft
                }
            }

    }
}