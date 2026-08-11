import Quickshell
import Quickshell.Io
import QtQuick

PanelWindow {
    anchors {
        top:true
    }
    implicitHeight: 30
    implicitWidth: 300

    Text{
        id: "clock"
        anchors.centerIn: parent
        Process {
            id: "dateProcess"
            command: ["date"]
            running: true
            stdout: StdioCollector {
                onStreamFinished: clock.text = this.text
            }
        }
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: dateProcess.running = true
        }
    }
}