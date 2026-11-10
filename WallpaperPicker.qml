import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Wallpaper picker: the current theme's backgrounds on the zooming grid.
//
// A choice is applied the way omarchy-theme-bg-set applies it, except that
// Omarchy's background is told to switch instantly (picker-set-background):
// the grid's zoom is the transition, and Omarchy's own reveal would
// otherwise replay underneath it once the grid steps aside.
//
// A background with an intro plays it every time it is set. The zoom then
// lands on the intro's first frame rather than on the background, and OWE
// plays the intro on from that frame.
Scope {
    id: root

    readonly property string binDir: Quickshell.env("HOME") + "/.config/quickshell/bin"

    GridPicker {
        id: grid
        namespace: "quickshell-wallpaper-grid"

        onOpenRequested: {
            scanProc.command = [root.binDir + "/picker-wallpapers", Math.round(grid.monitorWidth) + "x" + Math.round(grid.monitorHeight)]
            scanProc.running = true
        }

        onApplyRequested: function(item, index) {
            applyProc.command = [root.binDir + "/picker-set-background", item.path]
            applyProc.running = true
        }
    }

    function entry(fields) {
        var path = fields[0] || ""
        var name = path.substring(path.lastIndexOf("/") + 1)
        var ext = name.substring(name.lastIndexOf(".") + 1).toLowerCase()
        return {
            name: name,
            label: name,
            path: path,
            thumbnail: fields[1] || path,
            // Applying zooms into the intro's first frame when there is
            // one; opening and cancelling show the background as it is.
            still: fields[3] || fields[2] || "",
            openStill: fields[2] || "",
            isAnimated: ext === "gif" || ext === "webp"
        }
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = String(text || "").split("\n")
                var current = null
                var list = []
                var seen = {}

                for (var i = 0; i < lines.length; ++i) {
                    if (!lines[i]) continue
                    var fields = lines[i].split("\t")
                    if (fields[0] === "CURRENT") {
                        if (fields[1]) current = root.entry(fields.slice(1))
                        continue
                    }
                    var item = root.entry(fields)
                    if (!item.path || seen[item.name]) continue
                    seen[item.name] = true
                    list.push(item)
                }

                var currentIndex = 0
                if (current) {
                    var found = -1
                    for (var j = 0; j < list.length; ++j) {
                        if (list[j].path === current.path || list[j].name === current.name) {
                            found = j
                            break
                        }
                    }
                    // A background from outside the theme still opens the
                    // grid on itself.
                    // (A video has no still and gets no card.)
                    if (found === -1 && current.openStill) {
                        list.unshift(current)
                        found = 0
                    }
                    currentIndex = Math.max(0, found)
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
        name: "wallpaperToggle"
        description: "Toggle wallpaper grid picker"
        appid: "quickshell"
        onPressed: grid.toggle()
    }

    IpcHandler {
        target: "wallpaperPicker"
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
