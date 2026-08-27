import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "MenuModel.js" as Model
import "AppSearch.js" as AppSearch

Scope {
    id: root

    property bool opened: false
    property bool isDismissing: false
    readonly property bool isPresented: opened && !isDismissing
    property real lastToggleTime: 0

    // Navigation State
    property string activeMenu: "root"
    property var navStack: []
    property string filterText: ""
    property int selectedIndex: 0

    // Menu Item Store (JSONC + Desktop Apps)
    property var defaultMenuItems: []
    property var userMenuItems: []
    property var items: ({})
    property var itemOrder: []

    // Icon Fallback Cache
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
        var name = dot > 0 ? file.slice(0, dot) : file
        if (name.length > 0 && root.pendingIconIndex[name] === undefined)
            root.pendingIconIndex[name] = value
    }

    Process {
        id: iconIndexScan
        command: ["bash", "-c", root.iconIndexScanCommand()]
        stdout: SplitParser { onRead: function(line) { root.indexIconLine(line) } }
        onStarted: root.pendingIconIndex = ({})
        onExited: root.iconIndex = root.pendingIconIndex
    }

    function iconSource(icon) {
        var value = String(icon || "")
        if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
        if (value.charAt(0) === "/") return "file://" + value
        var found = root.iconIndex[value]
        if (found) return "file://" + found
        var themed = Quickshell.iconPath(value, true)
        if (themed && themed.length > 0) return themed
        return Quickshell.iconPath("application-x-executable", true)
    }

    FileView {
        id: defaultMenuFile
        path: "/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc"
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.defaultMenuItems = Model.parseMenuJsonc(text())
            root.rebuildItemsFromSources()
        }
        onFileChanged: reload()
    }

    FileView {
        id: userMenuFile
        path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.userMenuItems = Model.parseMenuJsonc(text())
            root.rebuildItemsFromSources()
        }
        onLoadFailed: {
            root.userMenuItems = []
            root.rebuildItemsFromSources()
        }
        onFileChanged: reload()
    }

    function rebuildItemsFromSources() {
        var merged = Model.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
        root.items = merged.items
        root.itemOrder = merged.itemOrder
        root.mergeAppRows()
    }

    function mergeAppRows() {
        var values = (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []
        var rows = AppSearch.sortedEntries(values, "", null)
        var appRows = []

        for (var j = 0; j < rows.length; j++) {
            var entry = rows[j].entry
            var appId = String(entry.id || "")
            if (!appId) continue
            var subtext = AppSearch.entrySubtext(entry)
            var aliases = subtext ? [subtext] : []
            try {
                if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
            } catch (e) { }

            appRows.push({
                id: "apps." + appId,
                parent: "apps",
                kind: "app",
                icon: "",
                appIcon: String(entry.icon || ""),
                appId: appId,
                label: AppSearch.entryName(entry),
                title: "",
                target: "",
                description: subtext,
                action: "",
                provider: "",
                aliases: aliases,
                when: "",
                checked: "",
                order: 0
            })
        }

        var merged = Model.mergeAppRows(root.items, root.itemOrder, appRows)
        root.items = merged.items
        root.itemOrder = merged.itemOrder
        if (root.opened) root.rebuildDisplay()
    }

    Connections {
        target: DesktopEntries.applications ? DesktopEntries.applications : null
        function onValuesChanged() {
            root.mergeAppRows()
        }
    }

    Component.onCompleted: {
        if (defaultMenuFile.text()) {
            root.defaultMenuItems = Model.parseMenuJsonc(defaultMenuFile.text())
        }
        if (userMenuFile.exists && userMenuFile.text()) {
            root.userMenuItems = Model.parseMenuJsonc(userMenuFile.text())
        }
        root.rebuildItemsFromSources()
        iconIndexScan.running = true
    }

    // Display Model for ListView
    ListModel {
        id: displayModel
    }

    function rebuildDisplay() {
        displayModel.clear()
        var active = Model.item(root.items, root.activeMenu) ? root.activeMenu : "root"
        root.activeMenu = active
        var query = root.filterText.trim()
        var rows = []

        if (query) {
            var currentRows = []
            var drilldownRows = []

            for (var i = 0; i < root.itemOrder.length; i++) {
                var entry = Model.item(root.items, root.itemOrder[i])
                if (!entry || entry.id === "root") continue
                if (!Model.isDescendantOf(root.items, entry.id, active)) continue
                if (!Model.matchesQuery(entry, query, true)) continue

                var detail = Model.parentPathFor(root.items, entry.id)
                var row = Model.displayRow(root.items, root.itemOrder, null, entry, detail, Model.searchScore(root.items, entry, query))
                if (entry.parent === active) currentRows.push(row)
                else drilldownRows.push(row)
            }

            var searchSort = function(a, b) {
                if (a.score !== b.score) return a.score - b.score
                return a.path.localeCompare(b.path)
            }

            currentRows.sort(searchSort)
            drilldownRows.sort(searchSort)
            rows = currentRows.concat(drilldownRows)
        } else {
            for (var j = 0; j < root.itemOrder.length; j++) {
                var child = Model.item(root.items, root.itemOrder[j])
                if (!child || child.parent !== active) continue
                rows.push(Model.displayRow(root.items, root.itemOrder, null, child, child.description, child.order))
            }

            if (active === "apps") {
                rows.sort(function(a, b) {
                    var aLabel = String(a.label || "").toLowerCase()
                    var bLabel = String(b.label || "").toLowerCase()
                    if (aLabel < bLabel) return -1
                    if (aLabel > bLabel) return 1
                    return 0
                })
            }
        }

        for (var k = 0; k < rows.length; k++) {
            displayModel.append(rows[k])
        }

        if (root.selectedIndex >= displayModel.count) {
            root.selectedIndex = Math.max(0, displayModel.count - 1)
        }
    }

    Timer {
        id: dismissTimer
        interval: 220
        onTriggered: {
            root.isDismissing = false
            root.opened = false
            root.filterText = ""
            root.activeMenu = "root"
            root.navStack = []
            PopoutCoordinator.release("menu")
        }
    }

    function cancel() {
        if (root.isDismissing || !root.opened) return
        root.isDismissing = true
        dismissTimer.restart()
    }

    function openRoute(id) {
        root.opened = true
        root.isDismissing = false
        dismissTimer.stop()
        root.activeMenu = (id && Model.item(root.items, id)) ? id : "root"
        root.navStack = (id && id !== "root") ? ["root"] : []
        root.filterText = ""
        root.selectedIndex = 0
        root.mergeAppRows()
        root.rebuildDisplay()

        if (!iconIndexScan.running && Object.keys(root.iconIndex).length === 0) {
            iconIndexScan.running = true
        }

        PopoutCoordinator.claim("menu")
        Qt.callLater(function() {
            keyCatcher.forceActiveFocus()
        })
    }

    function toggleMenu(initialMenu) {
        var menu = initialMenu || "root"
        var now = Date.now()
        if (now - root.lastToggleTime < 250) return
        root.lastToggleTime = now

        if (root.opened && !root.isDismissing && root.activeMenu === menu) {
            root.cancel()
        } else {
            root.openRoute(menu)
        }
    }

    // Global Shortcuts
    GlobalShortcut {
        name: "menuToggle"
        description: "Toggle bottom-center Omarchy Menu"
        appid: "quickshell"
        onPressed: {
            root.toggleMenu("root")
        }
    }

    GlobalShortcut {
        name: "appsToggle"
        description: "Toggle bottom-center Omarchy Menu directly into Apps"
        appid: "quickshell"
        onPressed: {
            root.toggleMenu("apps")
        }
    }

    Connections {
        target: PopoutCoordinator
        function onActiveChanged() {
            if (PopoutCoordinator.active !== "" && PopoutCoordinator.active !== "menu") {
                if (root.opened && !root.isDismissing) {
                    root.cancel()
                }
            }
        }
    }

    function setFilter(val) {
        root.filterText = val
        root.selectedIndex = 0
        root.rebuildDisplay()
        resultList.positionViewAtIndex(0, ListView.Beginning)
    }

    function revealCursor() {
        if (displayModel.count === 0) return
        resultList.currentIndex = root.selectedIndex
        if (root.selectedIndex === 0) {
            resultList.positionViewAtIndex(0, ListView.Beginning)
            return
        }
        if (root.selectedIndex === displayModel.count - 1) {
            resultList.positionViewAtIndex(displayModel.count - 1, ListView.End)
            return
        }
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

        var item = resultList.itemAtIndex(root.selectedIndex)
        if (!item) return

        var reach = 37
        var maxY = Math.max(0, resultList.contentHeight - resultList.height)
        if (root.selectedIndex < displayModel.count - 1) {
            var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
            if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
        }
        if (root.selectedIndex > 0) {
            var underhang = resultList.contentY - (item.y - reach)
            if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, 0)
        }
    }

    function select(delta) {
        if (displayModel.count <= 0) return
        var next = root.selectedIndex + delta
        if (next < 0) {
            next = displayModel.count - 1
        } else if (next >= displayModel.count) {
            next = 0
        }
        root.selectedIndex = next
        root.revealCursor()
    }

    function goBack() {
        if (root.navStack.length > 0) {
            root.activeMenu = root.navStack.pop()
            root.setFilter("")
        } else if (root.activeMenu !== "root") {
            root.activeMenu = "root"
            root.setFilter("")
        }
    }

    function activateIndex(index) {
        if (index < 0 || index >= displayModel.count) return
        var row = displayModel.get(index)
        if (!row) return

        var entry = Model.item(root.items, row.itemId)
        if (!entry) return

        if (entry.kind === "menu") {
            root.navStack.push(root.activeMenu)
            root.activeMenu = entry.id
            root.setFilter("")
            return
        }

        if (entry.kind === "app") {
            root.cancel()
            var appId = String(entry.appId || "")
            var desktopFile = appId + ".desktop"
            var quoted = "'" + desktopFile.replace(/'/g, "'\\''") + "'"
            Quickshell.execDetached(["bash", "-lc", "uwsm-app -- gtk-launch " + quoted + " 2>/dev/null || gtk-launch " + quoted + " 2>/dev/null || (" + quoted + " &)"])
            return
        }

        if (entry.kind === "action" && entry.action) {
            root.cancel()
            Quickshell.execDetached(["bash", "-c", entry.action])
            return
        }

        if (entry.kind === "link" && entry.target) {
            root.cancel()
            Quickshell.execDetached(["omarchy-launch-webapp", entry.target])
            return
        }
    }

    // Main Center-Bottom Omarchy Menu Window
    Variants {
        model: (root.opened || root.isDismissing) ? [Quickshell.screens[0]] : []

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            visible: root.opened || root.isDismissing

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "quickshell-omarchy-menu"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.isPresented ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            // Layer 0: Backdrop Scrim with Outside-Click Dismissal
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                opacity: root.isPresented ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: root.cancel()
                }
            }

            // Layer 1: Center-Bottom Sliding Card Container
            Item {
                id: cardContainer
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.isPresented ? 0 : -(height + 50)

                width: 440 + Theme.rounding * 2
                height: 460

                Behavior on anchors.bottomMargin {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                // Bottom-Left Scoop (Connects flush to bottom display bezel)
                ScoopShape {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    cornerPosition: scoopPosition.topLeft
                }

                // Bottom-Right Scoop (Connects flush to bottom display bezel)
                ScoopShape {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    cornerPosition: scoopPosition.topRight
                }

                // Main Card Surface
                Rectangle {
                    id: background
                    anchors.fill: parent
                    anchors.leftMargin: Theme.rounding
                    anchors.rightMargin: Theme.rounding
                    topLeftRadius: Theme.rounding
                    topRightRadius: Theme.rounding
                    bottomLeftRadius: 0
                    bottomRightRadius: 0
                    color: Theme.bgc
                    clip: true

                    // Swallow clicks inside the card
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                    }

                    // Key Catcher for full keyboard control without TextInput focus stealing
                    Item {
                        id: keyCatcher
                        anchors.fill: parent
                        focus: true

                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_Escape) {
                                if (root.filterText) root.setFilter("")
                                else root.cancel()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Backspace && root.filterText) {
                                if (event.modifiers & Qt.ControlModifier) {
                                    root.setFilter(root.filterText.replace(/\s+$/, "").replace(/\S+$/, ""))
                                } else {
                                    root.setFilter(root.filterText.slice(0, -1))
                                }
                                event.accepted = true
                            } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
                                root.goBack()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Up) {
                                root.select(-1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Down) {
                                root.select(1)
                                event.accepted = true
                            } else if (event.key === Qt.Key_PageUp) {
                                root.select(-6)
                                event.accepted = true
                            } else if (event.key === Qt.Key_PageDown) {
                                root.select(6)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
                                if (displayModel.count > 0) {
                                    root.activateIndex(root.selectedIndex)
                                }
                                event.accepted = true
                            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                                root.setFilter(root.filterText + event.text)
                                event.accepted = true
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacing * 2
                        spacing: Theme.spacing * 1.5

                        // --- Header & Search Bar ---
                        RowLayout {
                            id: headerArea
                            Layout.fillWidth: true
                            spacing: Theme.spacing

                            // Back Button (Visible when inside a submenu)
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 6
                                color: Theme.surface
                                visible: root.activeMenu !== "root" && !root.filterText

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰁍"
                                    color: Theme.brand
                                    font.pixelSize: 14
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.goBack()
                                }
                            }

                            // Header Text Display (Type to search indicator)
                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: 8
                                color: Theme.surface
                                border.color: root.filterText ? Theme.accent : Theme.selection
                                border.width: 1.5

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: "󰍉"
                                        color: root.filterText ? Theme.brand : Theme.darkForeground
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.filterText || ((root.activeMenu === "apps" ? "Apps" : (Model.item(root.items, root.activeMenu) ? (Model.item(root.items, root.activeMenu).title || Model.item(root.items, root.activeMenu).label) : "Menu")) + "…")
                                        color: root.filterText ? Theme.foreground : Theme.darkForeground
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }

                                    // Clear Search Button
                                    Text {
                                        visible: !!root.filterText
                                        text: "󰅖"
                                        color: Theme.darkForeground
                                        font.pixelSize: 13

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setFilter("")
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: Theme.selection
                        }

                        // --- Results ListView ---
                        ListView {
                            id: resultList
                            currentIndex: root.selectedIndex
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 3
                            boundsBehavior: Flickable.StopAtBounds
                            model: displayModel

                            delegate: Rectangle {
                                required property int index
                                required property string label
                                required property string icon
                                required property string appIcon
                                required property string kind
                                required property string itemId

                                readonly property bool isSelected: index === root.selectedIndex

                                width: resultList.width
                                height: 34
                                radius: 6
                                color: isSelected ? Theme.selection : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 10

                                    // Icon (Themed SVG/PNG application icon or glyph)
                                    Item {
                                        width: 22
                                        height: 22
                                        Layout.alignment: Qt.AlignVCenter

                                        Image {
                                            id: appIconImage
                                            anchors.fill: parent
                                            visible: kind === "app" && status !== Image.Error && status !== Image.Null
                                            source: (kind === "app" && appIcon) ? root.iconSource(appIcon) : ""
                                            sourceSize.width: 22
                                            sourceSize.height: 22
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: kind !== "app" || !appIconImage.visible
                                            text: icon || (kind === "app" ? "󰀻" : "󰅂")
                                            color: isSelected ? Theme.brand : Theme.foreground
                                            font.pixelSize: 13
                                        }
                                    }

                                    // Title
                                    Text {
                                        text: label
                                        color: isSelected ? Theme.brand : Theme.foreground
                                        font.pixelSize: 12
                                        font.bold: isSelected
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    // Arrow Indicator for submenus
                                    Text {
                                        text: (kind === "menu" || itemId === "apps") ? "󰅂" : ""
                                        color: isSelected ? Theme.brand : Theme.darkForeground
                                        font.pixelSize: 11
                                        visible: text !== ""
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.selectedIndex = index
                                    onClicked: root.activateIndex(index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
