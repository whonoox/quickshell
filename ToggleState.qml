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

    // ------------------------------------------------------------------
    // Stay Awake (Idle Inhibition) State
    // ------------------------------------------------------------------
    readonly property string stayAwakeDir: home + "/.local/state/omarchy/indicators"
    readonly property string stayAwakePath: stayAwakeDir + "/stay-awake"
    property bool stayAwake: false

    function refreshStayAwake() {
        if (!probeStayAwakeProcess.running) {
            probeStayAwakeProcess.running = true
        }
    }

    function toggleStayAwake() {
        Quickshell.execDetached([
            "bash", "-c",
            "if which omarchy-toggle-idle >/dev/null 2>&1; then omarchy-toggle-idle toggle; else mkdir -p \"$HOME/.local/state/omarchy/indicators\"; if [[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]]; then rm -f \"$HOME/.local/state/omarchy/indicators/stay-awake\"; else touch \"$HOME/.local/state/omarchy/indicators/stay-awake\"; fi; fi"
        ])
        root.stayAwake = !root.stayAwake
        stayAwakeSettleTimer.restart()
    }

    function setStayAwake(val) {
        var cmd = val ? "stay-awake" : "allow-idle"
        Quickshell.execDetached([
            "bash", "-c",
            "if which omarchy-toggle-idle >/dev/null 2>&1; then omarchy-toggle-idle " + cmd + "; else mkdir -p \"$HOME/.local/state/omarchy/indicators\"; if [ \"" + (val ? "1" : "0") + "\" = \"1\" ]; then touch \"$HOME/.local/state/omarchy/indicators/stay-awake\"; else rm -f \"$HOME/.local/state/omarchy/indicators/stay-awake\"; fi; fi"
        ])
        root.stayAwake = !!val
        stayAwakeSettleTimer.restart()
    }

    property Timer stayAwakeSettleTimer: Timer {
        interval: 200
        onTriggered: root.refreshStayAwake()
    }

    property Process probeStayAwakeProcess: Process {
        command: [
            "bash", "-c",
            "if [[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]]; then echo yes; else echo no; fi"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                root.stayAwake = (String(line || "").trim() === "yes")
            }
        }
    }

    property FileView stayAwakeDirWatcher: FileView {
        path: root.stayAwakeDir
        watchChanges: true
        printErrors: false
        onFileChanged: root.refreshStayAwake()
    }

    // ------------------------------------------------------------------
    // Fn Lock State
    // ------------------------------------------------------------------
    readonly property string fnLockLedPath: "/sys/class/leds/platform::fnlock/brightness"
    property bool fnLock: false
    property bool fnLockAvailable: true

    function refreshFnLock() {
        if (!probeFnLockProcess.running) {
            probeFnLockProcess.running = true
        }
    }

    function toggleFnLock() {
        Quickshell.execDetached([
            "bash", "-c",
            "val=$(cat /sys/class/leds/platform::fnlock/brightness 2>/dev/null || echo 0); if [ \"$val\" = \"1\" ]; then brightnessctl -q -d platform::fnlock set 0; else brightnessctl -q -d platform::fnlock set 1; fi"
        ])
        root.fnLock = !root.fnLock
        fnLockSettleTimer.restart()
    }

    function setFnLock(val) {
        var target = val ? "1" : "0"
        Quickshell.execDetached([
            "bash", "-c",
            "brightnessctl -q -d platform::fnlock set " + target
        ])
        root.fnLock = !!val
        fnLockSettleTimer.restart()
    }

    property Timer fnLockSettleTimer: Timer {
        interval: 200
        onTriggered: root.refreshFnLock()
    }

    property Process probeFnLockProcess: Process {
        command: ["cat", "/sys/class/leds/platform::fnlock/brightness"]
        stdout: SplitParser {
            onRead: function(line) {
                var l = String(line || "").trim()
                root.fnLockAvailable = true
                root.fnLock = (l === "1")
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.fnLockAvailable = false
            }
        }
    }

    property Timer fnLockPollTimer: Timer {
        interval: 1000
        running: root.fnLockAvailable
        repeat: true
        onTriggered: root.refreshFnLock()
    }

    Component.onCompleted: {
        notifSettingsRead.reload()
        root.refreshMic()
        root.refreshStayAwake()
        root.refreshFnLock()
    }
}
