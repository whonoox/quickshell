pragma Singleton
import QtQuick

QtObject {
    id: root

    property string active: "" // "wifi" | "bluetooth" | "menu"
    property string activeHud: "" // "audio" | "brightness"

    function claim(name) {
        active = name
    }

    function release(name) {
        if (active === name) {
            active = ""
        }
    }

    function claimHud(name) {
        activeHud = name
    }

    function releaseHud(name) {
        if (activeHud === name) {
            activeHud = ""
        }
    }
}
