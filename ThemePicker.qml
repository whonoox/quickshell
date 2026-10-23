import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// Theme picker: the shell's own theme switcher, in the same language as the
// wallpaper picker.
//
// Omarchy's stock binding for the theme menu is
// `omarchy-menu toggle theme`, which routes into this shell's menu. That
// menu has no theme route, so the binding did nothing at all. This
// component provides the theme UI instead, and the Hyprland module binds
// the shortcut straight to it.
Scope {
    id: root

    // ---- Configuration & Geometry ----
    readonly property real monitorWidth: (Quickshell.screens && Quickshell.screens.length > 0 && Quickshell.screens[0].width > 0) ? Quickshell.screens[0].width : 1920
    readonly property real monitorHeight: (Quickshell.screens && Quickshell.screens.length > 0 && Quickshell.screens[0].height > 0) ? Quickshell.screens[0].height : 1080

    readonly property real cardWidth: 440
    readonly property real cardHeight: 248
    readonly property real colGap: 36
    readonly property real rowGap: 28
    readonly property real colStep: cardWidth + colGap
    readonly property real rowStep: cardHeight + rowGap
    readonly property real staggerY: (cardHeight + rowGap) / 2
    readonly property real baseY: 70
    readonly property real centerMargin: Math.max(0, (monitorWidth - (3 * cardWidth + 2 * colGap)) / 2)
    readonly property real cardRadius: 10

    // ---- State ----
    property bool opened: false
    property bool isDismissing: false
    property bool isApplying: false
    property var themeList: []
    property int selectedIndex: 0
    property string currentThemeName: ""
    property int initialIndex: 0

    // Zoom transform state (0.0 = Grid view, 1.0 = Fullscreen zoom)
    property real zoomProgress: 0.0
    property real cameraScale: 1.0
    property real targetTx: 0.0
    property real targetTy: 0.0

    // Snappy horizontal scroll offset
    property real scrollX: 0.0
    Behavior on scrollX {
        enabled: !zoomAnim.running
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    readonly property string selectedThemeName: (themeList && themeList.length > selectedIndex && selectedIndex >= 0) ? themeList[selectedIndex].name : ""

    // ---- Navigation Math ----
    function moveVertical(dir) {
        var total = themeList.length
        if (total === 0) return
        var col = Math.floor(selectedIndex / 3)
        var row = selectedIndex % 3
        var newRow = row + dir
        if (newRow >= 0 && newRow <= 2) {
            var newIndex = col * 3 + newRow
            if (newIndex < total) {
                selectedIndex = newIndex
            }
        }
    }

    function moveHorizontal(dir) {
        var total = themeList.length
        if (total === 0) return
        var col = Math.floor(selectedIndex / 3)
        var row = selectedIndex % 3
        var totalCols = Math.ceil(total / 3)
        var newCol = col + dir
        if (newCol >= 0 && newCol < totalCols) {
            var newIndex = newCol * 3 + row
            if (newIndex >= total) {
                newIndex = total - 1
            }
            selectedIndex = newIndex
        }
    }

    onSelectedIndexChanged: {
        if (!opened && !isApplying && !isDismissing) return
        var col = Math.floor(selectedIndex / 3)
        var targetScroll = 0
        if (col > 1) {
            targetScroll = (col - 1) * colStep
        }
        scrollX = targetScroll
    }

    function updateCameraTarget(index) {
        var total = themeList.length
        if (total === 0 || index < 0 || index >= total) {
            cameraScale = 1.0
            targetTx = 0.0
            targetTy = 0.0
            return
        }

        var col = Math.floor(index / 3)
        var row = index % 3

        var cardX = centerMargin + col * colStep - scrollX
        var cardY = baseY + (col % 2 === 1 ? staggerY : 0) + row * rowStep

        var px = cardX + cardWidth / 2
        var py = cardY + cardHeight / 2

        var scale = monitorWidth / cardWidth
        cameraScale = scale
        targetTx = monitorWidth / 2 - px * scale
        targetTy = monitorHeight / 2 - py * scale
    }

    // ---- Open / Close / Toggle / Apply Flow ----
    function open() {
        if (opened && !isDismissing) return
        scanProc.running = true
    }

    function startReveal() {
        // Find index of current theme
        var curIdx = 0
        if (currentThemeName) {
            for (var i = 0; i < themeList.length; ++i) {
                if (themeList[i].name === currentThemeName) {
                    curIdx = i
                    break
                }
            }
        }

        selectedIndex = curIdx
        initialIndex = curIdx

        var col = Math.floor(curIdx / 3)
        var targetScroll = (col > 1) ? (col - 1) * colStep : 0
        scrollX = targetScroll

        updateCameraTarget(curIdx)

        zoomAnim.stop()
        zoomProgress = 1.0
        opened = true
        isDismissing = false
        isApplying = false

        zoomAnim.from = 1.0
        zoomAnim.to = 0.0
        zoomAnim.duration = 250
        zoomAnim.easing.type = Easing.OutCubic
        zoomAnim.start()
    }

    property bool zoomDone: false
    property bool applyDone: false

    function checkDismiss() {
        if (root.isApplying) {
            if (root.zoomDone && root.applyDone) {
                root.opened = false
                root.isApplying = false
                root.zoomDone = false
                root.applyDone = false
            }
        }
    }

    function applySelected() {
        if (isApplying || isDismissing || !opened) return
        var name = selectedThemeName
        if (!name) {
            cancel()
            return
        }

        isApplying = true
        zoomDone = false
        applyDone = false
        updateCameraTarget(selectedIndex)

        // Omarchy's own theme command, so the theme is applied exactly the
        // way the stock switcher applies it: the palette, the background
        // and the shell's own theme hooks all run.
        applyProc.command = ["omarchy", "theme", "set", name]
        applyProc.running = true

        zoomAnim.stop()
        zoomAnim.from = zoomProgress
        zoomAnim.to = 1.0
        zoomAnim.duration = 250
        zoomAnim.easing.type = Easing.InOutCubic
        zoomAnim.start()
    }

    function cancel() {
        if (isDismissing || isApplying || !opened) return
        isDismissing = true
        updateCameraTarget(initialIndex)

        zoomAnim.stop()
        zoomAnim.from = zoomProgress
        zoomAnim.to = 1.0
        zoomAnim.duration = 220
        zoomAnim.easing.type = Easing.OutCubic
        zoomAnim.start()
    }

    function toggle() {
        if (opened && !isDismissing && !isApplying) {
            cancel()
        } else {
            open()
        }
    }

    NumberAnimation {
        id: zoomAnim
        target: root
        property: "zoomProgress"
        onFinished: {
            if (root.zoomProgress === 0.0) {
                // Zoom-out finished
            } else if (root.zoomProgress === 1.0) {
                // Zoom-in finished
                if (root.isApplying) {
                    root.zoomDone = true
                    root.checkDismiss()
                } else if (root.isDismissing) {
                    root.opened = false
                    root.isDismissing = false
                }
            }
        }
    }

    // ---- Discovery & Application Processes ----
    Process {
        id: scanProc
        command: [
            "bash", "-c",
            "thumb_dir=\"${XDG_CACHE_HOME:-$HOME/.cache}/nooxshell/thumbnails\"; " +
            "mkdir -p \"$thumb_dir\"; " +
            "find_preview() { " +
            "  local theme_path=\"$1\" preview name; " +
            "  for name in preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp preview.jxl; do " +
            "    preview=\"$(find -L \"$theme_path\" -maxdepth 1 -type f -iname \"$name\" -print -quit 2>/dev/null)\"; " +
            "    [ -n \"$preview\" ] && { printf '%s\\n' \"$preview\"; return; }; " +
            "  done; " +
            "  find -L \"$theme_path/backgrounds\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' -o -iname '*.jxl' \\) -print 2>/dev/null | sort | head -n 1; " +
            "}; " +
            "current=\"$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null)\"; " +
            "echo \"CURRENT:$current\"; " +
            "for dir in \"$HOME/.config/omarchy/themes\" \"${OMARCHY_PATH:-/usr/share/omarchy}/themes\"; do " +
            "  [ -d \"$dir\" ] || continue; " +
            "  for theme_path in \"$dir\"/*; do " +
            "    [ -d \"$theme_path\" ] || continue; " +
            "    name=\"${theme_path##*/}\"; " +
            "    preview=\"$(find_preview \"$theme_path\")\"; " +
            "    [ -n \"$preview\" ] || continue; " +
            "    thumb=\"$preview\"; " +
            "    ext=\"${preview##*.}\"; " +
            "    ext=\"$(echo \"$ext\" | tr '[:upper:]' '[:lower:]')\"; " +
            "    if [ \"$ext\" = \"jxl\" ]; then " +
            "      sig=$(stat -Lc '%s:%Y' \"$preview\" 2>/dev/null); " +
            "      hash=$(printf '%s:%s' \"$preview\" \"$sig\" | md5sum | cut -d ' ' -f 1); " +
            "      thumb=\"$thumb_dir/$hash.jpg\"; " +
            "      if [ ! -f \"$thumb\" ]; then " +
            "        vipsthumbnail \"$preview\" --size 880x496 --smartcrop=centre -o \"$thumb\" 2>/dev/null || magick \"$preview\" -resize 880x496^ -gravity center -extent 880x496 \"$thumb\" 2>/dev/null; " +
            "      fi; " +
            "    fi; " +
            "    printf '%s|%s|%s\\n' \"$name\" \"$preview\" \"$thumb\"; " +
            "  done; " +
            "done"
        ]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = String(text || "").trim()
                if (!raw) return
                var lines = raw.split("\n")
                var cur = ""
                var list = []
                var seen = {}

                for (var i = 0; i < lines.length; ++i) {
                    var l = lines[i].trim()
                    if (!l) continue
                    if (l.indexOf("CURRENT:") === 0) {
                        cur = l.substring(8).trim()
                        continue
                    }
                    var sep = l.indexOf("|")
                    if (sep === -1) continue
                    var name = l.substring(0, sep)
                    var rest = l.substring(sep + 1)
                    var sep2 = rest.indexOf("|")
                    var path = (sep2 === -1) ? rest : rest.substring(0, sep2)
                    var thumb = (sep2 === -1) ? rest : rest.substring(sep2 + 1)
                    if (!name || !path || seen[name]) continue
                    seen[name] = true
                    list.push({ name: name, path: path, thumbnail: thumb })
                }

                root.currentThemeName = cur
                root.themeList = list
                root.startReveal()
            }
        }
    }

    Process {
        id: applyProc
        onExited: {
            root.applyDone = true
            root.checkDismiss()
        }
    }

    // ---- Shortcuts & IPC ----
    GlobalShortcut {
        name: "themeToggle"
        description: "Toggle theme picker"
        appid: "quickshell"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "themePicker"
        function toggle(): string { root.toggle(); return "ok" }
        function open(): string { root.open(); return "ok" }
        function close(): string { root.cancel(); return "ok" }
        function moveRight(): string { root.moveHorizontal(1); return "ok" }
        function moveLeft(): string { root.moveHorizontal(-1); return "ok" }
        function moveUp(): string { root.moveVertical(-1); return "ok" }
        function moveDown(): string { root.moveVertical(1); return "ok" }
        function select(): string { root.applySelected(); return "ok" }
        function getSelected(): string { return root.selectedThemeName }
        function refresh(): string { scanProc.running = true; return "ok" }
        function ping(): string { return "ok" }
    }

    // ---- Fullscreen Layershell Window ----
    BarVariants {
        PanelWindow {
            id: panel
            required property var modelData

            visible: root.opened || root.isDismissing || root.isApplying
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"

            WlrLayershell.namespace: "quickshell-theme-grid"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            // Solid blank backdrop
            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 1.0

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!zoomAnim.running) {
                            root.cancel()
                        }
                    }
                }
            }

            // Invisible Keyboard Event Sink
            Item {
                id: keyFilter
                anchors.fill: parent
                focus: true

                Component.onCompleted: forceActiveFocus()

                Connections {
                    target: root
                    function onZoomProgressChanged() {
                        if (root.zoomProgress === 0.0 && root.opened) keyFilter.forceActiveFocus()
                    }
                    function onOpenedChanged() {
                        if (root.opened) keyFilter.forceActiveFocus()
                    }
                }

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    if (zoomAnim.running) {
                        event.accepted = true
                        return
                    }

                    if (event.key === Qt.Key_Escape) {
                        root.cancel()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.applySelected()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        root.moveVertical(1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        root.moveVertical(-1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Right) {
                        root.moveHorizontal(1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Left) {
                        root.moveHorizontal(-1)
                        event.accepted = true
                    }
                }
            }

            // Camera Transform Container
            Item {
                id: cameraContainer
                anchors.fill: parent
                clip: false

                transformOrigin: Item.TopLeft
                transform: [
                    Scale {
                        origin.x: 0
                        origin.y: 0
                        xScale: 1.0 + (root.cameraScale - 1.0) * root.zoomProgress
                        yScale: 1.0 + (root.cameraScale - 1.0) * root.zoomProgress
                    },
                    Translate {
                        x: root.targetTx * root.zoomProgress
                        y: root.targetTy * root.zoomProgress
                    }
                ]

                // Horizontal Ribbon Container
                Item {
                    id: ribbon
                    x: -root.scrollX
                    y: 0
                    width: parent.width
                    height: parent.height

                    Repeater {
                        model: root.themeList

                        delegate: Item {
                            id: cardItem
                            required property int index
                            required property var modelData

                            readonly property int col: Math.floor(index / 3)
                            readonly property int row: index % 3
                            readonly property bool isSelected: index === root.selectedIndex

                            x: root.centerMargin + col * root.colStep
                            y: root.baseY + (col % 2 === 1 ? root.staggerY : 0) + row * root.rowStep
                            width: root.cardWidth
                            height: root.cardHeight
                            z: isSelected ? 10 : 1
                            opacity: (cardItem.isSelected || root.zoomProgress === 0.0) ? 1.0 : Math.max(0.0, 1.0 - root.zoomProgress * 2.5)

                            readonly property real currentRadius: Math.max(0, root.cardRadius * (1.0 - root.zoomProgress))

                            // Rounded mask for image clipping
                            Rectangle {
                                id: maskRect
                                anchors.fill: parent
                                radius: cardItem.currentRadius
                                color: "black"
                                visible: false
                                layer.enabled: true
                            }

                            // Image Layer clipped to rounded corners
                            Item {
                                id: imageLayer
                                anchors.fill: parent
                                layer.enabled: true
                                layer.smooth: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: maskRect
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#121420"
                                }

                                Image {
                                    id: staticImg
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    source: (modelData && modelData.thumbnail) ? (modelData.thumbnail.indexOf("file://") === 0 ? modelData.thumbnail : "file://" + modelData.thumbnail) : (modelData ? (modelData.path.indexOf("file://") === 0 ? modelData.path : "file://" + modelData.path) : "")
                                    asynchronous: true
                                    sourceSize: Qt.size(880, 496)
                                }
                            }

                            // Card Outline / Selection Accent (rendered on top)
                            Rectangle {
                                anchors.fill: parent
                                radius: cardItem.currentRadius
                                color: "transparent"
                                border.width: cardItem.isSelected ? Math.max(0, 3 * (1.0 - root.zoomProgress)) : 1
                                border.color: cardItem.isSelected ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                                z: 2
                            }

                            // Mouse Interactions
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    if (!zoomAnim.running) {
                                        root.selectedIndex = index
                                    }
                                }
                                onClicked: {
                                    if (!zoomAnim.running) {
                                        root.selectedIndex = index
                                        root.applySelected()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Minimal Theme Name Indicator at Bottom
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 26
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.selectedThemeName.toUpperCase()
                font.family: Theme.brandFont
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 2
                color: Theme.fgc
                opacity: Math.max(0.0, (1.0 - root.zoomProgress) * 0.75)
                visible: opacity > 0.01 && root.selectedThemeName.length > 0
            }
        }
    }
}
