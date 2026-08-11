import Quickshell
import Quickshell.Io
import QtQuick


Scope{  
    id: root
    readonly property string time: {
        Qt.formatDateTime(clock.date, "ddd MMM d hh:mm:ss AP yyyy")
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors {
                top:true
            }
            implicitHeight: 30
            implicitWidth: 300

            Text{
                text: root.time
                anchors.centerIn: parent
            }
        }
    }
}
