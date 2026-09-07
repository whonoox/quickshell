import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    property bool hudVisible: false
    property var workspacesData: []
    property var windowClassByAddress: ({})
    property string currentActiveAddress: ""
    property int currentWorkspaceId: -1

    function normAddr(a) {
        return String(a || "").toLowerCase().replace(/^0x/, "").trim()
    }

    function isFullWidthMode() {
        var fw = Hyprland.focusedWorkspace
        if (!fw) return false
        if (fw.hasFullscreen || (fw.lastIpcObject && fw.lastIpcObject.hasfullscreen)) {
            return true
        }
        if (fw.toplevels) {
            var tops = fw.toplevels.values
            for (var i = 0; i < tops.length; i++) {
                var t = tops[i]
                if (t.lastIpcObject && (t.lastIpcObject.fullscreen !== 0 || t.lastIpcObject.fullscreenClient !== 0)) {
                    return true
                }
            }
        }
        return false
    }

    // Icon Index & Resolution
    property var iconIndex: ({})
    property var pendingIconIndex: ({})

    function iconIndexScanCommand() {
        return [
            'dirs="$HOME/.icons $HOME/.local/share/icons";',
            'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
            'for ext in svg png; do',
            '  for base in $dirs; do',
            '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
            '  done;',
            '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
            'done'
        ].join(' ')
    }

    function indexIconLine(path) {
        var value = String(path || "").trim()
        if (value.length === 0) return
        var slash = value.lastIndexOf("/")
        var file = slash >= 0 ? value.slice(slash + 1) : value
        var dot = file.lastIndexOf(".")
        var name = dot > 0 ? file.slice(0, dot).toLowerCase() : file.toLowerCase()
        if (name.length > 0 && root.pendingIconIndex[name] === undefined) {
            root.pendingIconIndex[name] = value
        }
    }

    Process {
        id: iconIndexScan
        command: ["bash", "-c", root.iconIndexScanCommand()]
        stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
        onStarted: root.pendingIconIndex = ({})
        onExited: {
            root.iconIndex = root.pendingIconIndex
            root.updateWorkspaces()
        }
    }

    function lookupIcon(name) {
        var key = String(name || "").toLowerCase().trim()
        if (key.length === 0) return ""
        if (key.indexOf("file://") === 0 || key.indexOf("image://") === 0) return key
        if (key.charAt(0) === "/") return "file://" + key

        if (root.iconIndex[key]) return "file://" + root.iconIndex[key]
        var themed = Quickshell.iconPath(key, true)
        if (themed && themed.length > 0) return themed
        return ""
    }

    function resolveAppInfo(windowClass, title, initialTitle) {
        var cls = String(windowClass || "").trim()
        var tit = String(title || "").trim()
        var initTit = String(initialTitle || "").trim()

        // 1. Terminal / TUI Application Detection (Ghostty, Alacritty, Kitty, Foot)
        var isTerminal = (cls === "com.mitchellh.ghostty" || cls === "ghostty" || 
                          cls === "Alacritty" || cls === "kitty" || cls === "foot" ||
                          cls.indexOf("org.omarchy.") === 0)
        
        if (isTerminal) {
            // Check Herdr explicitly anywhere in title/class
            if (tit.toLowerCase().indexOf("herdr") !== -1 || initTit.toLowerCase().indexOf("herdr") !== -1 || cls.toLowerCase().indexOf("herdr") !== -1) {
                var herdrIcon = root.lookupIcon("herdr")
                if (herdrIcon) return { iconUrl: herdrIcon, glyph: "" }
            }

            // Check Omarchy TUI app id prefix (e.g. org.omarchy.btop -> btop)
            if (cls.indexOf("org.omarchy.") === 0) {
                var tuiApp = cls.replace(/^org\.omarchy\./, "").toLowerCase()
                var iconTuiApp = root.lookupIcon(tuiApp)
                if (iconTuiApp) return { iconUrl: iconTuiApp, glyph: "" }
            }

            // Check initialTitle (e.g. btop, cliamp, lazygit, nvim)
            if (initTit.length > 0 && initTit.toLowerCase() !== "ghostty" && initTit.toLowerCase() !== "terminal") {
                var icon1 = root.lookupIcon(initTit)
                if (icon1) return { iconUrl: icon1, glyph: "" }
            }

            // Extract command from window title (e.g. "nuuxpc: btop", "user@host: ~/dir -> btop")
            var cleanTitle = tit.replace(/^[^:]+:\s*/, "").trim()
            var parts = cleanTitle.split(/\s+/)
            if (parts.length > 0) {
                var cmd = parts[0].toLowerCase()
                if (cmd.length > 0 && cmd !== "~" && cmd !== "bash" && cmd !== "zsh" && cmd !== "fish") {
                    var icon2 = root.lookupIcon(cmd)
                    if (icon2) return { iconUrl: icon2, glyph: "" }
                }
            }

            // Fallback for generic terminal shell
            var termIcon = root.lookupIcon(cls) || root.lookupIcon("com.mitchellh.ghostty") || root.lookupIcon("ghostty")
            return { iconUrl: termIcon, glyph: "" }
        }

        // 2. Webapp (PWA) Detection (e.g. "chrome-github.com__-Default", "chromium-youtube.com__-Default")
        if (cls.indexOf("chrome-") === 0 || cls.indexOf("chromium-") === 0) {
            // Check initialTitle (e.g. "GitHub", "YouTube", "WhatsApp", "Basecamp", "Discord", "X")
            if (initTit.length > 0) {
                var iconWeb1 = root.lookupIcon(initTit)
                if (iconWeb1) return { iconUrl: iconWeb1, glyph: "" }
            }

            // Parse domain name from class: chrome-github.com__-Default -> github
            var stripped = cls.replace(/^(?:chrome|chromium)-(?:https?___)?/, "").replace(/__.*$/, "")
            var domainParts = stripped.split(".")
            for (var d = 0; d < domainParts.length; d++) {
                var part = domainParts[d].toLowerCase()
                if (part.length > 0 && part !== "com" && part !== "org" && part !== "net" && part !== "app" && part !== "web" && part !== "default") {
                    var iconWeb2 = root.lookupIcon(part)
                    if (iconWeb2) return { iconUrl: iconWeb2, glyph: "" }
                }
            }

            // Check title keywords for webapps
            var lowerTitle = tit.toLowerCase()
            if (lowerTitle.indexOf("github") !== -1) {
                var iconGh = root.lookupIcon("github")
                if (iconGh) return { iconUrl: iconGh, glyph: "" }
            }
            if (lowerTitle.indexOf("youtube") !== -1) {
                var iconYt = root.lookupIcon("youtube")
                if (iconYt) return { iconUrl: iconYt, glyph: "" }
            }
            if (lowerTitle.indexOf("whatsapp") !== -1) {
                var iconWa = root.lookupIcon("whatsapp")
                if (iconWa) return { iconUrl: iconWa, glyph: "" }
            }
        }

        // 3. Direct class lookup
        var direct = root.lookupIcon(cls)
        if (direct) return { iconUrl: direct, glyph: "" }

        // 4. Dot-separated / hyphen-separated fallbacks
        var dotParts = cls.split(".")
        for (var i = dotParts.length - 1; i >= 0; i--) {
            var p = dotParts[i]
            if (p) {
                var iconDot = root.lookupIcon(p)
                if (iconDot) return { iconUrl: iconDot, glyph: "" }
            }
        }

        var hyphens = cls.split("-")
        for (var k = hyphens.length - 1; k >= 0; k--) {
            var h = hyphens[k]
            if (h) {
                var iconHyphen = root.lookupIcon(h)
                if (iconHyphen) return { iconUrl: iconHyphen, glyph: "" }
            }
        }

        // 5. Title / initialTitle lookup fallback
        if (initTit.length > 0) {
            var iconInit = root.lookupIcon(initTit)
            if (iconInit) return { iconUrl: iconInit, glyph: "" }
        }

        return { iconUrl: "", glyph: "" }
    }

    // Auto-hide Timer (1.5 seconds)
    Timer {
        id: autoHideTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.hudVisible = false
        }
    }

    // Fast trigger delay timer (60ms)
    Timer {
        id: triggerDelayTimer
        interval: 60
        repeat: false
        onTriggered: {
            Hyprland.refreshWorkspaces()
            root.updateWorkspaces()
        }
    }

    // Secondary settling timer (200ms) for newly created client windows
    Timer {
        id: secondaryDelayTimer
        interval: 200
        repeat: false
        onTriggered: {
            Hyprland.refreshWorkspaces()
            root.updateWorkspaces()
        }
    }

    function getWorkspaceId(w) {
        if (!w) return -1
        if (w.lastIpcObject && w.lastIpcObject.id !== undefined && w.lastIpcObject.id > 0) {
            return w.lastIpcObject.id
        }
        var parsed = parseInt(w.name)
        if (!isNaN(parsed) && parsed > 0) return parsed
        return w.id > 0 ? w.id : -1
    }

    // Refresh & Compute Workspaces List
    function updateWorkspaces() {
        var ws = Hyprland.workspaces.values
        var focused = Hyprland.focusedWorkspace
        var focusedId = root.getWorkspaceId(focused)
        var list = []
        var seen = {}

        // 1. Always evaluate active workspace
        if (focusedId > 0) {
            var focusedTops = []
            for (var i = 0; i < ws.length; i++) {
                if (root.getWorkspaceId(ws[i]) === focusedId && ws[i].toplevels) {
                    var rawTops = ws[i].toplevels.values
                    for (var k = 0; k < rawTops.length; k++) {
                        var rt = rawTops[k]
                        var appClass = ""
                        if (rt.lastIpcObject && (rt.lastIpcObject.class || rt.lastIpcObject.initialClass)) {
                            appClass = rt.lastIpcObject.class || rt.lastIpcObject.initialClass
                        } else if (rt.address && root.windowClassByAddress[rt.address]) {
                            appClass = root.windowClassByAddress[rt.address]
                        } else if (rt.appId) {
                            appClass = rt.appId
                        }
                        
                        var initialTitle = rt.lastIpcObject ? (rt.lastIpcObject.initialTitle || "") : ""
                        var appInfo = root.resolveAppInfo(appClass, rt.title || "", initialTitle)

                        focusedTops.push({
                            title: rt.title || "",
                            initialTitle: initialTitle,
                            address: rt.address || "",
                            appClass: appClass,
                            iconUrl: appInfo.iconUrl,
                            glyph: appInfo.glyph,
                            lastIpcObject: rt.lastIpcObject
                        })
                    }
                    break
                }
            }
            list.push({
                id: focusedId,
                isActive: true,
                toplevels: focusedTops,
                count: focusedTops.length
            })
            seen[focusedId] = true
        }

        // 2. Include other workspaces only if they have >= 1 open window
        for (var j = 0; j < ws.length; j++) {
            var w = ws[j]
            var id = root.getWorkspaceId(w)
            if (id <= 0 || seen[id]) continue
            var tops = w.toplevels ? w.toplevels.values : []
            if (tops.length > 0) {
                list.push({
                    id: id,
                    isActive: false,
                    toplevels: tops,
                    count: tops.length
                })
                seen[id] = true
            }
        }

        // Sort ascending by Workspace ID
        list.sort(function(a, b) { return a.id - b.id })
        root.workspacesData = list
    }

    // Event & Full-Width Mode Handler
    function handleEvent(eventName, eventData) {
        // Cache newly opened window class immediately from IPC event data
        if (eventName === "openwindow" && eventData) {
            var parts = String(eventData).split(",")
            if (parts.length >= 3) {
                var addr = parts[0].trim()
                var cls = parts[2].trim()
                if (addr.length > 0 && cls.length > 0) {
                    root.windowClassByAddress[addr] = cls
                }
            }
        }

        Hyprland.refreshWorkspaces()
        root.updateWorkspaces()

        // 1. Workspace switch: always reveal for 1.5s
        if (eventName === "workspace" || eventName === "focusedmon") {
            var wsId = parseInt(eventData) || (Hyprland.focusedWorkspace ? root.getWorkspaceId(Hyprland.focusedWorkspace) : -1)
            if (wsId !== root.currentWorkspaceId) {
                root.currentWorkspaceId = wsId
                root.hudVisible = true
                autoHideTimer.restart()
                triggerDelayTimer.restart()
                secondaryDelayTimer.restart()
            }
            return
        }

        // 2. Window focus switch: only reveal if transitioning to a different window in full-width mode!
        if (eventName === "activewindowv2") {
            var nextAddr = root.normAddr(eventData)
            // If the address didn't change (e.g. running command in terminal, browser tab opening, video playing), ignore!
            if (nextAddr.length > 0 && nextAddr === root.currentActiveAddress) {
                return
            }
            root.currentActiveAddress = nextAddr

            // Only reveal if the newly focused window is in full-width mode
            if (nextAddr.length > 0 && root.isFullWidthMode()) {
                root.hudVisible = true
                autoHideTimer.restart()
                triggerDelayTimer.restart()
                secondaryDelayTimer.restart()
            } else {
                root.hudVisible = false
                autoHideTimer.stop()
            }
            return
        }

        // 3. Fullscreen / full-width toggle (SUPER + ALT + F)
        if (eventName === "fullscreen") {
            var isFs = (String(eventData).trim() === "1") || root.isFullWidthMode()
            if (isFs) {
                root.hudVisible = true
                autoHideTimer.restart()
                triggerDelayTimer.restart()
            } else {
                root.hudVisible = false
                autoHideTimer.stop()
            }
            return
        }

        // 4. Structural window updates: refresh internal models without toggling visibility
        triggerDelayTimer.restart()
        secondaryDelayTimer.restart()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var name = String(event.name || "")
            var data = String(event.data || "")
            if (name === "activewindowv2" || 
                name === "workspace" || name === "focusedmon" || 
                name === "fullscreen" || name === "openwindow" || 
                name === "closewindow" || name === "movewindow") {
                root.handleEvent(name, data)
            }
        }
    }

    Component.onCompleted: {
        iconIndexScan.running = true
        Hyprland.refreshWorkspaces()
        root.updateWorkspaces()
    }

    // Top-Left Panel Window
    Variants {
        model: [Quickshell.screens[0]]

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "workspaces-panel-main"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region {
                item: root.hudVisible ? cardContainer : null
            }

            // Top-Left Anchored Card Container
            Item {
                id: cardContainer
                anchors.left: parent.left
                y: root.hudVisible ? 0 : -(height + 20)

                width: contentRow.implicitWidth + Theme.rounding + Theme.spacing * 4
                height: 44 + Theme.rounding

                Behavior on y {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                // Unified single-vector background contour (position: topLeft)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "topLeft"
                    color: Theme.bgc
                    radius: Theme.rounding
                    cornerRadius: Theme.rounding
                }

                // Main Content Container
                Item {
                    id: background
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.rounding
                    height: 44
                    clip: true

                    RowLayout {
                        id: contentRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing * 2.5
                        spacing: Theme.spacing * 1.5

                        Repeater {
                            model: root.workspacesData

                            RowLayout {
                                required property var modelData
                                required property int index
                                spacing: Theme.spacing * 1.5

                                // 1. Workspace Content
                                RowLayout {
                                    spacing: Theme.spacing

                                    // Active Workspace: Flex Row of App Icons (or circled Workspace Number if empty)
                                    RowLayout {
                                        visible: modelData.isActive
                                        spacing: Theme.spacing

                                        Repeater {
                                            model: modelData.toplevels

                                            Rectangle {
                                                required property var modelData
                                                required property int index

                                                width: 24
                                                height: 24
                                                radius: 6
                                                color: Theme.surface

                                                Image {
                                                    id: appImg
                                                    anchors.centerIn: parent
                                                    width: 18
                                                    height: 18
                                                    source: modelData.iconUrl || root.resolveAppInfo(modelData.appClass, modelData.title, modelData.initialTitle).iconUrl
                                                    visible: status === Image.Ready
                                                    sourceSize.width: 18
                                                    sourceSize.height: 18
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: !appImg.visible
                                                    text: modelData.glyph && modelData.glyph.length > 0 ? modelData.glyph : "󰀻"
                                                    color: Theme.brand
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 14
                                                }
                                            }
                                        }

                                        // Empty Active Workspace Badge: Circled Workspace Number
                                        Rectangle {
                                            visible: modelData.toplevels.length === 0
                                            width: 24
                                            height: 24
                                            radius: 12
                                            color: Theme.surface
                                            border.color: Theme.brand
                                            border.width: 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: String(modelData.id === 10 ? "0" : modelData.id)
                                                color: Theme.brand
                                                font.family: Theme.brandFont
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }

                                    // Inactive Workspace: Compact Circle Badge with App Count
                                    Rectangle {
                                        visible: !modelData.isActive
                                        width: 24
                                        height: 24
                                        radius: 12
                                        color: Theme.surface
                                        border.color: Theme.selection
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: String(modelData.count)
                                            color: Theme.lightForeground
                                            font.family: Theme.brandFont
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                // 2. Sleek Vertical Divider Between Workspace Sections
                                Rectangle {
                                    visible: index < root.workspacesData.length - 1
                                    width: 1
                                    height: 18
                                    color: Theme.selection
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
