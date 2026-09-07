pragma Singleton
import QtQuick

QtObject {
    id: root

    property string active: "" // "wifi" | "bluetooth" | "menu"

    function claim(name) {
        active = name
    }

    function release(name) {
        if (active === name) {
            active = ""
        }
    }
}
