import Quickshell
import Quickshell.Io
import QtQuick


Scope{  
    id: root
    property string time

    Variants {
        model: Quickshell.screens

        PanelWindow {
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
    Process {
        id: dateProcess
        command: ["date"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.time = this.text
        }
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: dateProcess.running = true
    }
}
