import Quickshell
import QtQuick

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: 'transparent'
            aboveWindows: false
            exclusionMode: ExclusionMode.Normal

            ScoopShape{
                anchors.top: parent.top
                anchors.left: parent.left
                size: 20
                cornerPosition: scoopPosition.bottomRight
                color: 'black'
            }

            ScoopShape{
                anchors.top: parent.top
                anchors.right: parent.right
                size: 20
                cornerPosition: scoopPosition.bottomLeft
                color: 'black'
            }

            ScoopShape{
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                size: 20
                cornerPosition: scoopPosition.topRight
                color: 'black'
            }

            ScoopShape{
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                size: 20
                cornerPosition: scoopPosition.topLeft
                color: 'black'
            }
        }
    }
}