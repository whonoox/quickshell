import Quickshell
import QtQuick

Scope {
    BarVariants {
        allScreens: true

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
                cornerPosition: scoopPosition.bottomRight
            }

            ScoopShape{
                anchors.top: parent.top
                anchors.right: parent.right
                cornerPosition: scoopPosition.bottomLeft
            }

            ScoopShape{
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                cornerPosition: scoopPosition.topRight
            }

            ScoopShape{
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                cornerPosition: scoopPosition.topLeft
            }
        }
    }
}