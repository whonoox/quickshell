import Quickshell
import Quickshell.Io
import QtQuick


Scope{  
    id: root
    readonly property string time: {
        Qt.formatDateTime(clock.date, "hh:mm:ss AP")
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            property bool hideBar: false
            property real padding: 24
            screen: modelData
            anchors {
                top:true
            }
            exclusionMode: ExclusionMode.Normal
            margins.top: hideBar ? implicitHeight * -1 : 0

            implicitHeight: child.height + padding
            implicitWidth: child.width + padding

            color: "transparent"


            Rectangle{
                anchors.fill: parent
                color: "black"
                bottomLeftRadius: 12
                bottomRightRadius: 12
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
            
        }
    }
}
