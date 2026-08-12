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
            property real padding: 24
           
            screen: modelData
            anchors {
                top:true
            }

            exclusionMode: ExclusionMode.Normal
            margins.top: root.hideBar ? implicitHeight * -1 : 0

            implicitHeight: child.height + padding
            implicitWidth: child.width + 3 * padding

            color: "transparent"


            Rectangle{
                anchors.fill: parent
                anchors.leftMargin: padding
                anchors.rightMargin: padding
                color: "black"
                bottomLeftRadius: padding
                bottomRightRadius: padding
            }

            ScoopShape{
                size: padding
                leftArc: true
            }


            Text{
                id: child
                text: root.time
                color: "green"
                anchors.centerIn: parent
                font.family: "Nuuxfont"
                font.pixelSize: 28
                font.weight: Font.Bold
            }
            ScoopShape{
                size: padding
                anchors.right: parent.right
                leftArc: false
            }
            
        }
    }
}
