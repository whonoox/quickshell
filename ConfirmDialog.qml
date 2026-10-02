import QtQuick

// Two-button confirmation overlay. Kept local so the menu island doesn't have
// to pull in the omarchy shell's Ui module.
Item {
    id: root

    property bool opened: false
    property string message: ""
    property string confirmText: "Confirm"
    property string cancelText: "Cancel"

    signal confirmed()
    signal canceled()

    property int selectedIndex: 1

    function select(delta) {
        var count = Math.max(1, buttonRow.children.length)
        selectedIndex = (selectedIndex + delta + count) % count
    }

    function activate() {
        if (selectedIndex === 0) root.confirmed()
        else root.canceled()
    }

    // Returns true when the key was consumed.
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            root.canceled()
            return true
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.select(-1)
            return true
        }
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            root.select(1)
            return true
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate()
            return true
        }
        return false
    }

    visible: root.opened
    enabled: root.opened

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        // The scrim is a plain Rectangle, which does not accept mouse events,
        // so without this every click during the prompt would fall through to
        // whatever is underneath -- the row the confirmation is about.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(360, parent.width - Theme.spacing * 4)
        height: confirmColumn.implicitHeight + Theme.spacing * 4
        radius: Theme.rounding
        color: Theme.bgc

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        Column {
            id: confirmColumn
            anchors.centerIn: parent
            width: parent.width - Theme.spacing * 4
            spacing: Theme.spacing * 1.5

            Text {
                width: parent.width
                text: root.message
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Row {
                id: buttonRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacing

                Rectangle {
                    width: 110
                    height: 32
                    radius: 6
                    color: root.selectedIndex === 0 ? Theme.selection : "transparent"
                    border.color: Theme.selection
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.cancelText
                        color: root.selectedIndex === 0 ? Theme.brand : Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: root.selectedIndex === 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selectedIndex = 0
                        onClicked: root.canceled()
                    }
                }

                Rectangle {
                    width: 110
                    height: 32
                    radius: 6
                    color: root.selectedIndex === 1 ? Theme.selection : "transparent"
                    border.color: Theme.selection
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.confirmText
                        color: root.selectedIndex === 1 ? Theme.brand : Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: root.selectedIndex === 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selectedIndex = 1
                        onClicked: root.confirmed()
                    }
                }
            }
        }
    }
}