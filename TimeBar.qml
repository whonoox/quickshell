import Quickshell
import QtQuick
import Quickshell.Hyprland

Scope{  
    id: root
    readonly property string time: {
        Qt.formatDateTime(clock.date, "hh:mm:ss AP")
    }

    property bool hideBar: false

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    GlobalShortcut{
        name: "timeToggle"
        description: "Show the current time with the panel window"
        appid: "quickshell"
        onPressed: {
            root.hideBar = !root.hideBar
            clock.precision = SystemClock.Seconds
        }
    }

    // Timer {
    //     interval: 3000
    //     running: !root.hideBar
    //     onTriggered: {
    //         root.hideBar = true
    //         clock.precision = SystemClock.Hours
    //     }
    // }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            property real blockPadding: Theme.rounding
            property real inlinePadding: Theme.rounding
           
            screen: modelData
            anchors {
                top:true
            }

            exclusionMode: ExclusionMode.Normal
            margins.top: root.hideBar ? implicitHeight * -1 : 0

            implicitHeight: child.height + blockPadding
            implicitWidth: child.width + 3 * inlinePadding

            color: "transparent"

            Rectangle{
                anchors.fill: parent
                anchors.leftMargin: Theme.rounding 
                anchors.rightMargin: Theme.rounding
                color: Theme.bgc
                bottomLeftRadius: Theme.rounding
                bottomRightRadius: Theme.rounding
            }

            // Rectangle{
            //     anchors.fill: parent
            //     anchors.leftMargin: Theme.rounding + Theme.spacing
            //     anchors.rightMargin: Theme.rounding + Theme.spacing
            //     anchors.bottomMargin: Theme.spacing
            //     color: Theme.brandBgc
            //     bottomLeftRadius: Theme.rounding - Theme.spacing
            //     bottomRightRadius: Theme.rounding - Theme.spacing
            //     topRightRadius: Theme.spacing
            //     topLeftRadius: Theme.spacing
            // }

            ScoopShape{
                cornerPosition: scoopPosition.bottomLeft
            }


            Text{
                id: child
                text: root.time
                color: Theme.brand
                anchors.centerIn: parent
                font.family: "Nuuxfont"
                font.pixelSize: 28
                font.weight: Font.Bold
            }
            ScoopShape{
                anchors.right: parent.right
                cornerPosition: scoopPosition.bottomRight
            }
            
        }
    }
}
