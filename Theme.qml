pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string colorsPath: home + "/.local/state/omarchy/current/theme/colors.toml"
    readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"

    // Theme Mode ("dark" | "light")
    property string mode: "dark"
    readonly property bool isLight: mode === "light"

    // Primary Accents
    property color accent: "#82FB9C"
    property color brand: accent
    readonly property color brandBgc: Qt.rgba(accent.r, accent.g, accent.b, isLight ? 0.2 : 0.25)

    // Full Palette Colors
    property color red: "#50f872"
    property color yellow: "#50f7d4"
    property color orange: "#50f7a3"
    property color green: "#00946d"
    property color cyan: "#7cf8f7"
    property color blue: "#829dd4"
    property color magenta: "#86a7df"
    property color brown: "#287b51"

    // Surfaces & Depth: Pure black in dark mode, pure white in light mode
    readonly property color bgc: isLight ? "#ffffff" : "#000000"
    readonly property color background: bgc
    property color darkBackground: isLight ? "#f0f0f0" : "#080910"
    property color darkerBackground: isLight ? "#e5e5e5" : "#06060c"
    property color lighterBackground: isLight ? "#f8f8f8" : "#151828"
    property color surface: lighterBackground
    property color selection: isLight ? "#e2e8f0" : "#1f253a"

    // Text & Hierarchy
    property color foreground: isLight ? "#1a1a1a" : "#ddf7ff"
    readonly property color fgc: foreground
    property color brightForeground: isLight ? "#000000" : "#ddf7ff"
    property color lightForeground: isLight ? "#4a5568" : "#b5c5db"
    property color darkForeground: isLight ? "#718096" : "#6a6e95"
    property color muted: isLight ? "#a0aec0" : "#2d3450"
    property color urgent: red

    // Dimensions
    readonly property int rounding: 20
    readonly property real spacing: 6

    // Typography
    readonly property string brandFont: "Nuuxfont"
    property string systemFont: "monospace"
    property string fontFamily: systemFont

    function parseToml(raw) {
        var map = {}
        var lines = String(raw || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line || line.startsWith("#") || line.startsWith("[")) continue
            var idx = line.indexOf("=")
            if (idx === -1) continue
            var k = line.substring(0, idx).trim()
            var rawVal = line.substring(idx + 1).trim()
            var match = rawVal.match(/^["']([^"']*)["']/)
            var v = match ? match[1] : rawVal.split("#")[0].trim()
            map[k] = v
        }
        return map
    }

    function loadColors(text) {
        if (!text) return
        var d = parseToml(text)
        if (d.mode) {
            root.mode = d.mode.toLowerCase()
        }

        if (d.accent) root.accent = d.accent
        if (d.dark_background) root.darkBackground = d.dark_background
        if (d.darker_background) root.darkerBackground = d.darker_background
        if (d.lighter_background) root.lighterBackground = d.lighter_background
        if (d.selection) root.selection = d.selection
        if (d.foreground) root.foreground = d.foreground
        if (d.bright_foreground) root.brightForeground = d.bright_foreground
        if (d.light_foreground) root.lightForeground = d.light_foreground
        if (d.dark_foreground) root.darkForeground = d.dark_foreground
        if (d.muted) root.muted = d.muted
        if (d.red) root.red = d.red
        if (d.yellow) root.yellow = d.yellow
        if (d.orange) root.orange = d.orange
        if (d.green) root.green = d.green
        if (d.cyan) root.cyan = d.cyan
        if (d.blue) root.blue = d.blue
        if (d.magenta) root.magenta = d.magenta
        if (d.brown) root.brown = d.brown
    }

    property FileView themeNameFile: FileView {
        id: themeNameFile
        path: root.themeNamePath
        watchChanges: true
        printErrors: false
        onLoaded: colorsReloadTimer.restart()
        onFileChanged: {
            reload()
            colorsReloadTimer.restart()
        }
    }

    property Timer colorsReloadTimer: Timer {
        id: colorsReloadTimer
        interval: 50
        repeat: false
        onTriggered: {
            colorsFile.reload()
            if (colorsFile.text()) {
                root.loadColors(colorsFile.text())
            }
        }
    }

    property FileView colorsFile: FileView {
        id: colorsFile
        path: root.colorsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadColors(text())
        onFileChanged: {
            reload()
            if (text()) {
                root.loadColors(text())
            }
        }
    }

    Component.onCompleted: {
        themeNameFile.reload()
        colorsFile.reload()
        if (colorsFile.text()) {
            root.loadColors(colorsFile.text())
        }
    }
}
