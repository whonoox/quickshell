import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Theme picker: the shell's own theme switcher, on the same zooming grid as
// the wallpaper picker.
//
// Omarchy's stock binding for the theme menu is
// `omarchy-menu toggle theme`, which routes into this shell's menu. That
// menu has no theme route, so the binding did nothing at all. This
// component provides the theme UI instead, and the Hyprland module binds
// the shortcut straight to it.
//
// The cards show each theme's preview, but the zoom lands on the
// background the theme will actually have (picker-themes chooses it the
// way omarchy-theme-set does), or on the first frame of its intro.
// picker-set-theme applies the theme without Omarchy's background
// transition, then sets that background instantly and hands over to OWE
// for the intro, so nothing replays behind the zoom.
Scope {
    id: root

    readonly property string binDir: Quickshell.env("HOME") + "/.config/quickshell/bin"

    GridPicker {
        id: grid
        namespace: "quickshell-theme-grid"

        onOpenRequested: {
            scanProc.command = [root.binDir + "/picker-themes", Math.round(grid.monitorWidth) + "x" + Math.round(grid.monitorHeight)]
            scanProc.running = true
        }

        onApplyRequested: function(item, index) {
            applyProc.command = [root.binDir + "/picker-set-theme", item.name, item.landing || ""]
            applyProc.running = true
        }
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = String(text || "").split("\n")
                var currentTheme = ""
                var currentStill = ""
                var list = []
                var seen = {}

                for (var i = 0; i < lines.length; ++i) {
                    if (!lines[i]) continue
                    var f = lines[i].split("\t")
                    if (f[0] === "CURRENT") {
                        currentTheme = f[1] || ""
                        currentStill = f[2] || ""
                        continue
                    }
                    if (!f[0] || !f[1] || seen[f[0]]) continue
                    seen[f[0]] = true
                    list.push({
                        name: f[0],
                        label: f[0],
                        thumbnail: f[1],
                        still: f[2] || "",
                        landing: f[3] || "",
                        openStill: ""
                    })
                }

                var currentIndex = 0
                for (var j = 0; j < list.length; ++j) {
                    if (list[j].name === currentTheme) {
                        // The grid opens out of, and a cancel returns to,
                        // the background on screen now.
                        list[j].openStill = currentStill
                        currentIndex = j
                        break
                    }
                }

                grid.present(list, currentIndex)
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) grid.present([], 0)
        }
    }

    Process {
        id: applyProc
        stdout: StdioCollector { id: applyOut; waitForEnd: true }
        // An intro is already moving when the script returns, so the grid
        // steps aside at once; a still needs a moment to draw.
        onExited: grid.applyFinished(String(applyOut.text || "").indexOf("INTRO") !== -1 ? 0 : 180)
    }

    GlobalShortcut {
        name: "themeToggle"
        description: "Toggle theme picker"
        appid: "quickshell"
        onPressed: grid.toggle()
    }

    IpcHandler {
        target: "themePicker"
        function toggle(): string { grid.toggle(); return "ok" }
        function open(): string { grid.open(); return "ok" }
        function close(): string { grid.cancel(); return "ok" }
        function moveRight(): string { grid.moveHorizontal(1); return "ok" }
        function moveLeft(): string { grid.moveHorizontal(-1); return "ok" }
        function moveUp(): string { grid.moveVertical(-1); return "ok" }
        function moveDown(): string { grid.moveVertical(1); return "ok" }
        function select(): string { grid.applySelected(); return "ok" }
        function getSelected(): string { return grid.selectedName }
        function getPhase(): string { return grid.phase }
        function refresh(): string { return "ok" }
        function ping(): string { return "ok" }
    }
}
