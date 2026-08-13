import Quickshell
import QtQuick
import QtQuick.Layouts

Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors.right: true

            exclusionMode: ExclusionMode.Normal

            implicitWidth: 40
            implicitHeight: 150
            color:"transparent"

            ScoopShape{
                anchors.top: parent.top
                anchors.right: parent.right
                cornerPosition: scoopPosition.topLeft
            }

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: Theme.rounding
                anchors.bottomMargin: Theme.rounding
                color: Theme.bgc
                bottomLeftRadius: Theme.rounding - flexLayout.spacing
                topLeftRadius: Theme.rounding - flexLayout.spacing
            }

            FlexboxLayout {
                property real spacing: 4
                id: flexLayout
                anchors.fill: parent
                anchors.topMargin: Theme.rounding + spacing
                anchors.bottomMargin: Theme.rounding + spacing
                anchors.leftMargin: spacing
                direction: FlexboxLayout.Column
                gap: spacing
                

                Rectangle {
                topLeftRadius: Theme.rounding
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: 'green'
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: 'lime'
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: 'yellow'
                }
                Rectangle {
                bottomLeftRadius: Theme.rounding
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: 'red'
                }
            }

            ScoopShape{
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                cornerPosition: scoopPosition.bottomLeft
            }
        }

}