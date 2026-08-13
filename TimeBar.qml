import Quickshell
import Quickshell.Io
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

    Timer {
        interval: 3000
        running: !root.hideBar
        onTriggered: {
            root.hideBar = true
            clock.precision = SystemClock.Hours
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            property real blockPadding: 24
            property real inlinePadding: 32
           
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

            ScoopShape{
                cornerPosition: scoopPosition.bottomLeft
            }


            Text{
                id: child
                text: root.time
                color: Theme.brand
                anchors.centerIn: parent
                font.family: "Nuuxfont"
                font.pixelSize: inlinePadding
                font.weight: Font.Bold
            }
            ScoopShape{
                anchors.right: parent.right
                cornerPosition: scoopPosition.bottomRight
            }
            
        }
    }
}
