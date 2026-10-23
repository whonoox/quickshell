pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string notifSettingsPath: home + "/.local/state/omarchy/notifications.json"

    // ------------------------------------------------------------------
    // Notification DND State
    // ------------------------------------------------------------------
    property bool dnd: false
    property bool _hydratingNotif: false

    function toggleDnd() {
        setDnd(!root.dnd)
    }

    function setDnd(val) {
        root.dnd = !!val
        if (!root._hydratingNotif) {
            notifSaveTimer.restart()
        }
    }

    property Timer notifSaveTimer: Timer {
        interval: 150
        onTriggered: {
            if (root._hydratingNotif) return
            var payload = JSON.stringify({ version: 3, dnd: root.dnd }, null, 2) + "\n"
            if (notifSettingsWrite.setText) {
                notifSettingsWrite.setText(payload)
            } else {
                notifSettingsWrite.text = payload
            }
        }
    }

    property FileView notifSettingsWrite: FileView {
        path: root.notifSettingsPath
        printErrors: false
    }

    property FileView notifSettingsRead: FileView {
        path: root.notifSettingsPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            var raw = text()
            if (!raw) return
            root._hydratingNotif = true
            try {
                var parsed = JSON.parse(raw)
                root.dnd = !!(parsed && parsed.dnd)
            } catch (e) { }
            root._hydratingNotif = false
        }
        onFileChanged: reload()
    }

    // ------------------------------------------------------------------
    // Microphone Mute State
    // ------------------------------------------------------------------
    property bool micMuted: false
    property bool micAvailable: true

    function refreshMic() {
        if (!probeMicProcess.running) {
            probeMicProcess.running = true
        }
    }

    function toggleMic() {
        // Run omarchy-audio-input-mute or fallback to pactl
        Quickshell.execDetached([
            "bash", "-c",
            "if which omarchy-audio-input-mute >/dev/null 2>&1; then omarchy-audio-input-mute; else pactl set-source-mute @DEFAULT_SOURCE@ toggle; fi"
        ])
        // Optimistic toggle for instant visual response
        root.micMuted = !root.micMuted
        micSettleTimer.restart()
    }

    property Timer micSettleTimer: Timer {
        interval: 250
        onTriggered: root.refreshMic()
    }

    property Process probeMicProcess: Process {
        command: [
            "bash", "-c",
            "pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{ print ($NF == \"yes\") ? \"muted\" : \"live\" }'"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                var l = String(line || "").trim()
                if (l === "muted") {
                    root.micMuted = true
                    root.micAvailable = true
                } else if (l === "live") {
                    root.micMuted = false
                    root.micAvailable = true
                }
            }
        }
    }

    property Process pactlSubscriber: Process {
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                if (line.indexOf("'change' on source") !== -1 || line.indexOf("'change' on server") !== -1) {
                    root.refreshMic()
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Cursor X-Ray State
    // ------------------------------------------------------------------
    property bool cursorXRay: false

    function toggleCursorXRay() {
        setCursorXRay(!root.cursorXRay)
    }

    function setCursorXRay(val) {
        root.cursorXRay = !!val
    }

    Component.onCompleted: {
        notifSettingsRead.reload()
        root.refreshMic()
    }
}
