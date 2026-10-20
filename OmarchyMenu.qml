import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "MenuModel.js" as MenuModel
import "AppSearch.js" as AppSearch

// Menu island. Feature set mirrors the stock `omarchy.menu` plugin:
// JSONC merge, when/checked guards, providers, route resolution, dmenu
// select/input requests, app uninstall and launch feedback. Only the visuals
// are ours.
Scope {
    id: root

    property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    property string defaultMenuPath: root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
    property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"

    // ---- state -------------------------------------------------------
    property var defaultMenuItems: []
    property var userMenuItems: []
    property bool rowsLoaded: false
    property bool opened: false
    // Kept true for the length of the slide-out so the card stays on screen
    // while it animates away.
    property bool isDismissing: false
    readonly property bool isPresented: opened && !isDismissing

    property string mode: "menu"
    readonly property bool dmenuActive: mode === "select" || mode === "input"
    property string dmenuPrompt: ""
    property var dmenuOptions: []
    property string selectionFile: ""
    property string doneFile: ""
    property int dmenuWidth: 300
    property int dmenuMaxHeight: 0
    property bool requestActive: false

    property string activeMenu: "root"
    property var navStack: []
    property string filterText: ""
    property int selectedIndex: 0
    property bool cursorActive: false

    property var items: ({})
    property var itemOrder: []
    property var whenResults: ({})
    property var checkedResults: ({})
    property bool guardsPending: false

    property var providersLoaded: ({})
    property var providerQueue: []
    property int providerRevision: 0

    property int requestSerial: 0
    property int applySerial: 0

    // App uninstall confirmation.
    property bool deleteConfirmOpen: false
    property var deleteTarget: null
    onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null }

    // ---- app library ------------------------------------------------
    property var configuredHiddenEntryIds: ({})
    property var desktopHiddenEntryIds: ({})
    property var iconIndex: ({})
    property var pendingIconIndex: ({})
    property string hiddenEntryOutput: ""
    property int launchSerial: 0
    property int launchToplevelCount: 0
    property var launchActiveToplevel: null
    property bool launchOsdOpen: false
    property string launchOsdMessage: ""

    // ---- metrics ----------------------------------------------------
    property int contentMargin: Math.round(Theme.spacing * 2)
    property int headerHeight: 34
    property int contentSpacing: Math.round(Theme.spacing * 1.5)
    property int baseRowHeight: 34
    property int detailRowHeight: 48
    readonly property int rowPeek: Math.round(baseRowHeight * 0.55)
    property int rowSpacing: 3
    property int dividerHeight: 12
    property bool searchDivider: false
    // Fixed height for the card to prevent layout shifts when filtering or navigating.
    readonly property int cardHeight: 450
    readonly property int maxCardHeight: cardHeight
    // Breathing room under the last row so it never sits on the bottom edge
    // (and so the scoop's bottom corners cannot crowd it).
    readonly property int bottomInset: Theme.rounding + Theme.borderWidth
    readonly property int cardWidth: {
        if (root.dmenuActive) return Math.max(240, root.dmenuWidth)
        if (root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") return 520
        return 440
    }
    property int visibleRowsHeight: 0

    readonly property var activeScreen: {
        var screens = Quickshell.screens
        if (!screens || screens.length === 0) return null
        if (screens.length === 1) return screens[0]

        var targetName = (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            ? Hyprland.focusedMonitor.name
            : (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.monitor && Hyprland.focusedWorkspace.monitor.name
                ? Hyprland.focusedWorkspace.monitor.name : "")

        if (targetName) {
            for (var i = 0; i < screens.length; i++) {
                if (screens[i].name === targetName) return screens[i]
            }
        }
        return screens[0]
    }

    function screen() {
        return root.activeScreen
    }

    // ------------------------------------------------------------------
    // MenuModel delegation
    // ------------------------------------------------------------------

    function item(id) { return root.items[id] || null }

    function rebuildItemsFromSources() {
        var merged = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
        root.providerRevision += 1
        root.providersLoaded = ({})
        root.providerQueue = []
        root.items = merged.items
        root.itemOrder = merged.itemOrder
        root.rowsLoaded = true
        root.evaluateGuards()
        if (root.opened) {
            root.rebuildDisplay()
            if (!root.dmenuActive) {
                if (root.filterText.trim()) root.loadProvidersForSearch()
                else root.loadProviderForMenu(root.activeMenu)
            }
        }
    }

    function depthFor(id) { return MenuModel.depthFor(root.items, id) }
    function pathFor(id) { return MenuModel.pathFor(root.items, id) }
    function parentPathFor(id) { return MenuModel.parentPathFor(root.items, id) }
    function isDescendantOf(id, ancestorId) { return MenuModel.isDescendantOf(root.items, id, ancestorId) }
    function childCount(id) { return MenuModel.childCount(root.items, root.itemOrder, id) }
    function isVisible(entry) { return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry) }
    function labelFor(entry) { return MenuModel.labelFor(entry, root.checkedResults) }
    function matchesQuery(entry, query) { return MenuModel.matchesQuery(entry, query, root.isVisible(entry)) }
    function searchScore(entry, query) { return MenuModel.searchScore(root.items, entry, query) }
    function displayRow(entry, detail, score, section) {
        return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
    }
    function resolveRoute(input) { return MenuModel.resolveRoute(root.items, root.itemOrder, input) }
    function slugify(value) { return MenuModel.slugify(value) }

    // ------------------------------------------------------------------
    // Providers
    // ------------------------------------------------------------------

    readonly property var providers: ({
        "fonts": {
            script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
            icon: "",
            volatile: true,
            actionFor: function(value) { return "omarchy-font-set " + shellQuote(value) }
        },
        "power-profiles": {
            script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
            icon: "\udb81\udc0b",
            volatile: true,
            actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + shellQuote(value) }
        }
    })

    function shellQuote(value) {
        return "'" + String(value === undefined || value === null ? "" : value).replace(/'/g, "'\\''") + "'"
    }

    function runAction(action) {
        var command = String(action || "")
        if (!command) return
        Quickshell.execDetached(["bash", "-lc", command])
    }

    function startProviderForMenu(id) {
        var entry = root.item(id)
        if (!entry || !entry.provider || root.providersLoaded[id]) return
        if (entry.provider === "apps") {
            root.providersLoaded[id] = true
            root.mergeAppRows()
            return
        }
        var spec = root.providers[entry.provider]
        if (!spec) return

        root.providersLoaded[id] = true
        providerProc.menuId = id
        providerProc.providerKey = entry.provider
        providerProc.revision = root.providerRevision
        providerProc.collected = ""
        providerProc.command = ["bash", "-lc", spec.script]
        providerProc.running = true
    }

    function mergeProviderRows(rows, menuId, providerKey) {
        var spec = root.providers[providerKey]
        if (!spec) return
        var lines = String(rows || "").split("\n")
        var providerRows = []
        var takenIds = ({})
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line) continue
            var parts = line.split("\t")
            var label = parts[0] || ""
            var value = parts[1] || parts[0] || ""
            var current = parts[2] || ""
            if (!label) continue
            var rowId = menuId + "." + root.slugify(value)
            while (takenIds[rowId]) rowId += "-"
            takenIds[rowId] = true

            providerRows.push({
                id: rowId,
                parent: menuId,
                kind: "action",
                icon: (value === current) ? "✓" : (spec.icon || ""),
                iconFont: "",
                label: label,
                title: "",
                target: "",
                description: "",
                action: spec.actionFor(value),
                provider: "",
                aliases: [],
                when: "",
                checked: "",
                order: 0
            })
        }
        var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
        root.items = merged.items
        root.itemOrder = merged.itemOrder
        if (root.opened) root.rebuildDisplay()
    }

    function startNextProvider() {
        if (providerProc.running) return
        while (root.providerQueue.length > 0) {
            var id = root.providerQueue.shift()
            var entry = root.item(id)
            if (!entry || !entry.provider || root.providersLoaded[id]) continue
            root.startProviderForMenu(id)
            return
        }
    }

    function invalidateVolatileProvider(id) {
        var entry = root.item(id)
        var spec = entry && entry.provider ? root.providers[entry.provider] : null
        if (spec && spec.volatile) root.providersLoaded[id] = false
    }

    function loadProviderForMenu(id) {
        var entry = root.item(id)
        if (!entry || !entry.provider || root.providersLoaded[id]) return

        if (entry.provider === "apps") {
            root.startProviderForMenu(id)
            return
        }

        if (providerProc.running) {
            if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
            return
        }

        root.startProviderForMenu(id)
    }

    function loadProvidersForSearch() {
        var active = root.item(root.activeMenu) ? root.activeMenu : "root"
        for (var i = 0; i < root.itemOrder.length; i++) {
            var entry = root.item(root.itemOrder[i])
            if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
            if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue
            root.loadProviderForMenu(entry.id)
        }
    }

    // ------------------------------------------------------------------
    // App rows
    // ------------------------------------------------------------------

    function isHiddenEntry(entry) {
        var id = String((entry && entry.id) || "")
        return root.configuredHiddenEntryIds[id] === true || root.desktopHiddenEntryIds[id] === true
    }

    function mergeAppRows() {
        var values = (DesktopEntries.applications && DesktopEntries.applications.values) ? DesktopEntries.applications.values : []
        var rows = AppSearch.sortedEntries(values, "", function(entry) { return root.isHiddenEntry(entry) })
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
                iconFont: "",
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

        var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
        root.items = merged.items
        root.itemOrder = merged.itemOrder
        if (root.opened) root.rebuildDisplay()
    }

    function iconSource(icon) {
        var value = String(icon || "")
        if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
        if (value.charAt(0) === "/") return "file://" + String(value).split("/").map(encodeURIComponent).join("/")
        var found = root.iconIndex[value]
        if (found) return "file://" + String(found).split("/").map(encodeURIComponent).join("/")
        var themed = Quickshell.iconPath(value, true)
        if (themed && themed.length > 0) return themed
        return Quickshell.iconPath("application-x-executable", true)
    }

    function refreshIcons() {
        if (!iconIndexScan.running) iconIndexScan.running = true
    }

    function launchApp(desktopId, name) {
        var id = String(desktopId || "")
        if (!id) return
        root.beginLaunchFeedback(name)
        Quickshell.execDetached(["bash", "-lc", "uwsm-app -- gtk-launch " + root.shellQuote(id + ".desktop")])
    }

    function removeApp(desktopId, name) {
        var id = String(desktopId || "")
        if (!id) return
        Quickshell.execDetached(["bash", "-lc",
            root.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " "
            + root.shellQuote(id) + " " + root.shellQuote(String(name || id))])
    }

    function toplevelCount() {
        try { return Hyprland.toplevels ? Hyprland.toplevels.values.length : 0 } catch (e) { return 0 }
    }

    function beginLaunchFeedback(name) {
        root.launchSerial += 1
        root.launchToplevelCount = root.toplevelCount()
        root.launchActiveToplevel = Hyprland.activeToplevel
        root.launchOsdMessage = "Launching " + String(name || "application") + "…"
        launchDelay.restart()
        launchTimeout.restart()
    }

    function closeLaunchFeedback(serial) {
        if (serial !== root.launchSerial) return
        launchDelay.stop()
        launchTimeout.stop()
        // The launch OSD is shown with duration 0, so nothing else takes it
        // down once a window appears.
        if (root.launchOsdOpen) {
            Quickshell.execDetached(["omarchy-shell", "-q", "osd", "close"])
            root.launchOsdOpen = false
        }
    }

    function maybeFinishLaunchFeedback() {
        if (!launchDelay.running && !launchTimeout.running && !root.launchOsdOpen) return
        if (root.toplevelCount() <= root.launchToplevelCount && Hyprland.activeToplevel === root.launchActiveToplevel) return
        root.closeLaunchFeedback(root.launchSerial)
    }

    // ------------------------------------------------------------------
    // Guards
    // ------------------------------------------------------------------

    function evaluateGuards() {
        if (guardProc.running) {
            root.guardsPending = true
            return
        }
        root.guardsPending = false

        var script = MenuModel.guardScript(root.items)
        if (!script) {
            root.whenResults = ({})
            root.checkedResults = ({})
            return
        }
        guardProc.collected = ""
        guardProc.command = ["bash", "-lc", script]
        guardProc.running = true
    }

    // ------------------------------------------------------------------
    // Layout helpers
    // ------------------------------------------------------------------

    function rowHeightForDetail(detail) {
        return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
    }

    function naturalCardHeight() {
        return root.cardHeight
    }

    function availableRowsHeight() {
        // Space available for the list inside the fixed card height
        var available = root.cardHeight - root.contentMargin - root.bottomInset - root.headerHeight - root.contentSpacing + Theme.borderWidth
        if (root.dmenuActive && root.dmenuMaxHeight > 0) available = Math.min(available, root.dmenuMaxHeight)
        return Math.max(available, root.baseRowHeight)
    }

    function foldedListHeight(totals, available) {
        var count = totals.length
        if (count === 0) return root.baseRowHeight
        if (totals[count - 1] <= available) return totals[count - 1]

        var full = 0
        while (full < count && totals[full] <= available) full++
        while (full > 1 && totals[full - 1] + root.rowSpacing + root.rowPeek > available) full--
        if (full < 1) return Math.max(available, root.baseRowHeight)
        return totals[full - 1] + root.rowSpacing + root.rowPeek
    }

    function computeRowsHeight() {
        if (displayModel.count === 0) return root.dmenuActive && root.mode === "input" ? 0 : root.baseRowHeight

        var totals = []
        var total = 0
        var previousSection = ""
        for (var i = 0; i < displayModel.count; i++) {
            var row = displayModel.get(i)
            if (i > 0) total += root.rowSpacing
            if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
            total += root.rowHeightForDetail(row.detail)
            previousSection = row.section
            totals.push(total)
        }

        return root.foldedListHeight(totals, root.availableRowsHeight())
    }

    // ------------------------------------------------------------------
    // Display model
    // ------------------------------------------------------------------

    ListModel { id: displayModel }

    function rebuildDmenuDisplay() {
        displayModel.clear()
        root.searchDivider = false

        if (root.mode === "input") {
            root.visibleRowsHeight = 0
            return
        }

        var query = root.filterText.trim().toLowerCase()
        for (var i = 0; i < root.dmenuOptions.length; i++) {
            var parts = String(root.dmenuOptions[i] || "").split("\t")
            var icon = parts.length > 1 ? parts.shift() : ""
            var label = parts.shift() || ""
            var detail = parts.join("\t")
            if (query && label.toLowerCase().indexOf(query) < 0 && detail.toLowerCase().indexOf(query) < 0) continue
            displayModel.append({
                itemId: "dmenu." + i,
                kind: "dmenu",
                icon: icon,
                iconFont: "",
                appIcon: "",
                appId: "",
                label: label,
                target: "",
                detail: detail,
                path: "",
                childCount: 0,
                action: "",
                provider: "",
                score: i,
                section: ""
            })
        }

        if (displayModel.count === 0) root.selectedIndex = 0
        else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
        else if (root.selectedIndex < 0) root.selectedIndex = 0

        root.visibleRowsHeight = root.computeRowsHeight()
        Qt.callLater(function() { if (displayModel.count > 0) root.revealCursor() })
    }

    function rebuildDisplay() {
        if (root.dmenuActive) {
            root.rebuildDmenuDisplay()
            return
        }

        displayModel.clear()
        if (!root.rowsLoaded) return

        var active = root.item(root.activeMenu) ? root.activeMenu : "root"
        root.activeMenu = active
        var rows = []
        var query = root.filterText.trim()
        root.searchDivider = false

        if (query) {
            var currentRows = []
            var drilldownRows = []

            for (var i = 0; i < root.itemOrder.length; i++) {
                var entry = root.item(root.itemOrder[i])
                if (!entry || entry.id === "root") continue
                if (!root.isDescendantOf(entry.id, active)) continue
                if (!root.matchesQuery(entry, query)) continue

                var detail = root.parentPathFor(entry.id)
                var row = root.displayRow(entry, detail, root.searchScore(entry, query))
                if (entry.parent === active) currentRows.push(row)
                else drilldownRows.push(row)
            }

            var searchSort = function(a, b) {
                if (a.score !== b.score) return a.score - b.score
                return a.path.localeCompare(b.path)
            }

            currentRows.sort(searchSort)
            drilldownRows.sort(searchSort)
            root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
            if (root.searchDivider) {
                for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
            }
            rows = currentRows.concat(drilldownRows)
        } else {
            for (var j = 0; j < root.itemOrder.length; j++) {
                var child = root.item(root.itemOrder[j])
                if (!child || child.parent !== active) continue
                if (!root.isVisible(child)) continue
                rows.push(root.displayRow(child, child.description, child.order))
            }

            if (active === "apps") {
                rows.sort(function(a, b) {
                    var aLabel = String(a.label || "").toLowerCase()
                    var bLabel = String(b.label || "").toLowerCase()
                    if (aLabel < bLabel) return -1
                    if (aLabel > bLabel) return 1
                    var aId = String(a.itemId || "")
                    var bId = String(b.itemId || "")
                    if (aId < bId) return -1
                    if (aId > bId) return 1
                    return 0
                })
            }
        }

        for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])

        if (displayModel.count === 0) root.selectedIndex = 0
        else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
        else if (root.selectedIndex < 0) root.selectedIndex = 0

        root.visibleRowsHeight = root.computeRowsHeight()
        Qt.callLater(function() { if (displayModel.count > 0) root.revealCursor() })
    }

    function revealCursor() {
        if (displayModel.count === 0 || typeof resultList === "undefined") return
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

        var rowItem = resultList.itemAtIndex(root.selectedIndex)
        if (!rowItem) return

        var reach = root.rowPeek + root.rowSpacing
        if (root.selectedIndex < displayModel.count - 1) {
            var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
            var overhang = rowItem.y + rowItem.height + reach - (resultList.contentY + resultList.height)
            if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
        }
        if (root.selectedIndex > 0) {
            var underhang = resultList.contentY - (rowItem.y - reach)
            if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
        }
    }

    function select(delta) {
        if (displayModel.count === 0) return
        if (!root.cursorActive) {
            root.cursorActive = true
            root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
        } else {
            root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
        }
        root.revealCursor()
    }

    function setFilter(nextFilter) {
        root.filterText = nextFilter
        root.selectedIndex = 0
        root.cursorActive = root.mode !== "input"
        if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
        root.rebuildDisplay()
    }

    function setActiveMenu(id, pushHistory) {
        if (!root.item(id)) id = "root"
        if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
        root.activeMenu = id
        root.filterText = ""
        root.selectedIndex = 0
        root.cursorActive = true
        root.rebuildDisplay()
        root.invalidateVolatileProvider(id)
        root.loadProviderForMenu(id)
    }

    function goBack() {
        if (root.activeMenu === "root") return false
        if (root.navStack.length > 0) {
            var previous = root.navStack[root.navStack.length - 1]
            root.navStack = root.navStack.slice(0, root.navStack.length - 1)
            root.setActiveMenu(previous, false)
            return true
        }
        var active = root.item(root.activeMenu)
        root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
        return true
    }

    // ------------------------------------------------------------------
    // Activation
    // ------------------------------------------------------------------

    function requestDeleteSelected() {
        if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
        var row = displayModel.get(root.selectedIndex)
        if (!row || row.kind !== "app") return
        root.deleteTarget = { appId: row.appId, label: row.label }
        deleteConfirm.selectedIndex = 1
        root.deleteConfirmOpen = true
    }

    function cancelDelete() {
        root.deleteConfirmOpen = false
        root.deleteTarget = null
        deleteConfirm.selectedIndex = 1
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    function confirmDelete() {
        var target = root.deleteTarget
        root.deleteConfirmOpen = false
        root.deleteTarget = null
        if (!target) return
        root.cancel()
        root.removeApp(target.appId, target.label)
    }

    function activateIndex(index, fromPointer) {
        if (root.deleteConfirmOpen) return
        if (root.dmenuActive) {
            if (root.mode === "input") {
                root.applyDmenuSelection(root.filterText)
                return
            }
            if (index < 0 || index >= displayModel.count) return
            var picked = displayModel.get(index)
            root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
            return
        }

        if (index < 0 || index >= displayModel.count) return
        var row = displayModel.get(index)

        if (row.kind === "menu" || row.kind === "link") {
            root.setActiveMenu(row.target || row.itemId, true)
        } else if (row.kind === "app") {
            root.beginClose()
            root.launchApp(row.appId, row.label)
        } else {
            root.applySelected(row.itemId, row.action)
        }
    }

    function applyDmenuSelection(value) {
        root.beginClose()
        root.finishRequest(value)
    }

    function applySelected(id, action) {
        if (!id) { root.cancel(); return }
        root.beginClose()
        root.runAction(action)
    }

    // Closing keeps the card mounted for the length of the slide-out, so
    // requestSerial has to stay authoritative until the result lands.
    function beginClose() {
        root.applySerial = root.requestSerial
        root.filterText = ""
        root.releaseCoordinator()
        root.isDismissing = true
        root.opened = false
        dismissTimer.restart()
    }

    function finishRequest(selection) {
        if (!root.requestActive || !root.doneFile) {
            // Nothing left to answer, so this is only ever a dismissal. Let it
            // ride the same slide-out as every other close instead of yanking
            // the panel away -- but never resurrect a panel that is already
            // hidden, or a stray second request would flash it on screen.
            if (root.isPresented) root.beginClose()
            else {
                root.opened = false
                root.isDismissing = false
            }
            return
        }

        var activeSelectionFile = root.selectionFile
        var activeDoneFile = root.doneFile
        root.requestActive = false
        root.selectionFile = ""
        root.doneFile = ""

        if (selection === null || selection === undefined) {
            resultProc.command = ["bash", "-c", ": > " + root.shellQuote(activeDoneFile)]
        } else {
            resultProc.command = ["bash", "-c",
                "printf '%s\\n' " + root.shellQuote(selection) + " > " + root.shellQuote(activeSelectionFile)
                + "; : > " + root.shellQuote(activeDoneFile)]
        }
        resultProc.running = true
    }

    // ------------------------------------------------------------------
    // Open / close
    // ------------------------------------------------------------------

    function releaseCoordinator() {
        PopoutCoordinator.release("menu")
    }

    function cancel() {
        if (root.dmenuActive) root.finishRequest(null)
        root.beginClose()
    }

    function openExistingMenu(initialMenu) {
        root.requestSerial += 1
        root.mode = "menu"
        root.requestActive = false
        root.selectionFile = ""
        root.doneFile = ""
        root.activeMenu = root.item(initialMenu) ? initialMenu : "root"
        root.navStack = []
        root.filterText = ""
        root.selectedIndex = 0
        root.cursorActive = true
        root.evaluateGuards()
        dismissTimer.stop()
        root.isDismissing = false
        // Rows first: revealing the card before rebuildDisplay() leaves
        // visibleRowsHeight stale for a frame, so the card slides in short and
        // grows as it arrives.
        root.rebuildDisplay()
        panel.screen = root.activeScreen
        root.opened = true
        root.invalidateVolatileProvider(root.activeMenu)
        root.loadProviderForMenu(root.activeMenu)
        root.refreshIcons()

        PopoutCoordinator.claim("menu")
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    function openDmenu(payload) {
        root.requestSerial += 1
        root.mode = payload.mode === "input" ? "input" : "select"
        root.dmenuPrompt = String(payload.prompt || (root.mode === "input" ? "Input" : "Select"))
        root.dmenuOptions = Array.isArray(payload.options) ? payload.options : []
        root.selectionFile = String(payload.selectionFile || "")
        root.doneFile = String(payload.doneFile || "")
        root.requestActive = !!root.doneFile
        root.dmenuWidth = Math.max(1, Number(payload.width || 300))
        root.dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
        root.activeMenu = "root"
        root.navStack = []
        root.filterText = ""
        root.selectedIndex = 0
        root.cursorActive = root.mode !== "input"
        dismissTimer.stop()
        root.isDismissing = false
        // Rows first: revealing the card before rebuildDisplay() leaves
        // visibleRowsHeight stale for a frame, so the card slides in short and
        // grows as it arrives.
        root.rebuildDisplay()
        panel.screen = root.activeScreen
        root.opened = true

        PopoutCoordinator.claim("menu")
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    function openRoute(initialMenu) {
        var id = root.resolveRoute(initialMenu)
        var entry = root.items[id]
        if (entry && entry.kind === "action" && entry.action) {
            root.cancel()
            root.runAction(entry.action)
            return "ok"
        }
        if (entry && entry.kind === "link" && entry.target) id = entry.target
        root.openExistingMenu(id)
        return "ok"
    }

    // Toggling closes only when the requested route is already showing, so
    // SUPER+SPACE never leaves the menu stuck open on a different submenu.
    function toggle(initialMenu) {
        var id = root.resolveRoute(initialMenu || "root")
        var entry = root.items[id]
        if (entry && entry.kind === "action" && entry.action) {
            root.cancel()
            root.runAction(entry.action)
            return "ok"
        }
        if (entry && entry.kind === "link" && entry.target) id = entry.target

        if (root.opened && !root.dmenuActive && id === root.activeMenu) {
            root.cancel()
            return "ok"
        }
        root.openExistingMenu(id)
        return "ok"
    }

    function summon(payloadJson) {
        var payload = ({})
        try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
        if (payload.mode === "select" || payload.mode === "input") root.openDmenu(payload)
        else root.openRoute(payload.initialMenu || payload.menu || "root")
        return "ok"
    }

    function refresh() {
        defaultMenuFile.reload()
        userMenuFile.reload()
        return "ok"
    }

    function ping() { return "ok" }

    // ------------------------------------------------------------------
    // Processes
    // ------------------------------------------------------------------

    Process {
        id: providerProc
        property string menuId: ""
        property string providerKey: ""
        property string collected: ""
        property int revision: 0
        stdout: SplitParser {
            onRead: function(data) { providerProc.collected += data + "\n" }
        }
        onExited: {
            if (providerProc.revision === root.providerRevision) {
                root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
                if (root.filterText.trim() && !root.dmenuActive) root.loadProvidersForSearch()
            }
            root.startNextProvider()
        }
    }

    Process {
        id: guardProc
        property string collected: ""
        stdout: SplitParser {
            onRead: function(data) { guardProc.collected += data + "\n" }
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0 || exitStatus !== 0) {
                if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
                return
            }

            var nextWhen = ({})
            var nextChecked = ({})
            var lines = guardProc.collected.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (!line) continue
                var colon = line.lastIndexOf(":")
                if (colon < 0) continue
                var value = line.substring(colon + 1) === "1"
                var rest = line.substring(0, colon)
                var tagAt = rest.lastIndexOf(":")
                if (tagAt < 0) continue
                var id = rest.substring(0, tagAt)
                var tag = rest.substring(tagAt + 1)
                if (tag === "w") nextWhen[id] = value
                else if (tag === "c") nextChecked[id] = value
            }
            root.whenResults = nextWhen
            root.checkedResults = nextChecked
            if (root.opened) root.rebuildDisplay()
            if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        }
    }

    Process {
        id: resultProc
        onExited: if (root.applySerial === root.requestSerial && root.isPresented) root.beginClose()
    }

    Process {
        id: hiddenEntryScan
        command: ["bash", "-c", root.hiddenEntryScanCommand()]
        stdout: SplitParser {
            onRead: function(line) { root.hiddenEntryOutput += line + "\n" }
        }
        onStarted: root.hiddenEntryOutput = ""
        onExited: root.loadDesktopHiddenEntries(root.hiddenEntryOutput)
    }

    Process {
        id: iconIndexScan
        command: ["bash", "-c", root.iconIndexScanCommand()]
        stdout: SplitParser {
            onRead: function(line) { root.indexIconLine(line) }
        }
        onStarted: root.pendingIconIndex = ({})
        onExited: root.iconIndex = root.pendingIconIndex
    }

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

    function hiddenEntryScanCommand() {
        var desktop = [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")]
            .filter(function(v) { return String(v || "").length > 0 }).join(":")
        var script = root.omarchyPath + "/shell/services/hidden-entries.sh"
        return root.shellQuote(script) + " " + root.shellQuote(desktop)
    }

    function normalizeDesktopId(id) {
        var value = String(id || "").trim()
        if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
        return value
    }

    function loadConfiguredHides(rawText) {
        var next = ({})
        var lines = String(rawText || "").split(/\n/)
        for (var i = 0; i < lines.length; i++) {
            var id = root.normalizeDesktopId(lines[i])
            if (id.length > 0) next[id] = true
        }
        root.configuredHiddenEntryIds = next
        if (root.providersLoaded["apps"]) root.mergeAppRows()
    }

    function loadDesktopHiddenEntries(rawText) {
        var next = ({})
        var lines = String(rawText || "").split(/\n/)
        for (var i = 0; i < lines.length; i++) {
            var id = root.normalizeDesktopId(lines[i])
            if (id.length > 0) next[id] = true
        }
        root.desktopHiddenEntryIds = next
        if (root.providersLoaded["apps"]) root.mergeAppRows()
    }

    Timer {
        id: launchDelay
        interval: 2000
        onTriggered: {
            if (root.toplevelCount() > root.launchToplevelCount || Hyprland.activeToplevel !== root.launchActiveToplevel) return
            root.launchOsdOpen = true
            Quickshell.execDetached(["omarchy-shell", "osd", "show",
                JSON.stringify({ icon: "󱓞", message: root.launchOsdMessage, duration: 0 })])
        }
    }

    Timer {
        id: launchTimeout
        interval: 15000
        onTriggered: root.closeLaunchFeedback(root.launchSerial)
    }

    Timer {
        id: iconIndexDebounce
        interval: 750
        onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
    }

    Timer {
        id: dismissTimer
        // Safety timeout outlasting the 220ms slide-out in case the animation
        // is interrupted or suspended.
        interval: 400
        onTriggered: {
            if (root.isDismissing) root.isDismissing = false
        }
    }

    // ------------------------------------------------------------------
    // Sources
    // ------------------------------------------------------------------

    FileView {
        id: defaultMenuFile
        path: root.defaultMenuPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.defaultMenuItems = MenuModel.parseMenuJsonc(text())
            root.rebuildItemsFromSources()
        }
        onFileChanged: reload()
    }

    FileView {
        id: userMenuFile
        path: root.userMenuPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.userMenuItems = MenuModel.parseMenuJsonc(text())
            root.rebuildItemsFromSources()
        }
        onLoadFailed: {
            root.userMenuItems = []
            root.rebuildItemsFromSources()
        }
        onFileChanged: reload()
    }

    FileView {
        id: launcherHidesFile
        path: root.omarchyPath + "/default/omarchy/launcher.hides"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadConfiguredHides(text())
        onFileChanged: root.loadConfiguredHides(text())
        onLoadFailed: root.loadConfiguredHides("")
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            hiddenEntryScan.running = true
            iconIndexDebounce.restart()
            if (root.providersLoaded["apps"]) root.mergeAppRows()
        }
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { root.maybeFinishLaunchFeedback() }
    }

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root.maybeFinishLaunchFeedback() }
    }

    Connections {
        target: PopoutCoordinator
        function onActiveChanged() {
            if (PopoutCoordinator.active !== "" && PopoutCoordinator.active !== "menu") {
                if (root.opened) root.cancel()
            }
        }
    }

    Component.onCompleted: {
        hiddenEntryScan.running = true
        iconIndexScan.running = true
    }

    // ------------------------------------------------------------------
    // IPC
    // ------------------------------------------------------------------

    IpcHandler {
        target: "omarchyMenu"
        function toggle(route: string): string { return root.toggle(route) }
        function open(route: string): string { return root.toggle(route) }
        function close(): string { root.cancel(); return "ok" }
        function summon(payload: string): string { return root.summon(payload) }
        function select(payload: string): string { return root.summon(payload) }
        function input(payload: string): string { return root.summon(payload) }
        function refresh(): string { return root.refresh() }
        function ping(): string { return root.ping() }
    }

    GlobalShortcut {
        name: "menuToggle"
        description: "Toggle the Omarchy menu"
        appid: "quickshell"
        onPressed: root.toggle("root")
    }

    GlobalShortcut {
        name: "appsToggle"
        description: "Toggle the Omarchy menu directly into Apps"
        appid: "quickshell"
        onPressed: root.toggle("apps")
    }

    GlobalShortcut {
        name: "systemToggle"
        description: "Toggle the Omarchy menu directly into System"
        appid: "quickshell"
        onPressed: root.toggle("system")
    }

    GlobalShortcut {
        name: "menuRefresh"
        description: "Re-parse the Omarchy menu JSONC files"
        appid: "quickshell"
        onPressed: root.refresh()
    }

    // ------------------------------------------------------------------
    // Window
    // ------------------------------------------------------------------

    PanelWindow {
        id: panel
        // Stays mounted through the slide-out so the card animates away
        // instead of vanishing the frame `opened` flips.
        visible: root.opened || root.isDismissing
        screen: root.screen()

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "quickshell-omarchy-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        // No dimming scrim: like the other custom panels, the card floats on
        // its own and only the invisible backdrop swallows outside clicks.
        Rectangle {
            anchors.fill: parent
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.cancel()
            }
        }

        Item {
            id: cardContainer
            // ScoopContour's bottomCenter path runs its vertical edges at
            // radius + borderWidth in from the item bounds and strokes another
            // borderWidth outward, so the painted card is inset on both sides.
            // The item carries that slack; content is aligned to the painted
            // edge by the same inset.
            width: root.cardWidth + 2 * (Theme.rounding + Theme.borderWidth)
            height: {
                if (root.dmenuActive && root.mode === "input")
                    return root.contentMargin + root.bottomInset + root.headerHeight + 2
                if (root.dmenuActive && root.dmenuMaxHeight > 0)
                    return Math.min(root.cardHeight, root.dmenuMaxHeight)
                return root.cardHeight
            }
            anchors.horizontalCenter: parent.horizontalCenter
            // Docked to the bottom edge like the other custom panels. The
            // slide rides a transform rather than anchors.bottomMargin, which
            // would relayout the card on every frame; this keeps the motion on
            // the render thread and the bottom edge locked while height
            // animates.
            anchors.bottom: parent.bottom

            transform: Translate {
                id: slideTranslate
                // Slide off-screen by the card's height plus margin
                y: root.isPresented ? 0 : (cardContainer.height + 40)

                Behavior on y {
                    NumberAnimation {
                        id: yAnim
                        duration: 220
                        easing.type: Easing.OutCubic
                        onRunningChanged: {
                            if (!running && root.isDismissing) {
                                root.isDismissing = false
                                dismissTimer.stop()
                            }
                        }
                    }
                }
            }

            // Only animate the box while the card is on screen. While it is
            // hidden the height has to snap, otherwise opening would show the
            // card growing out of a collapsed stub as it slides.
            Behavior on width {
                enabled: root.isPresented
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }
            Behavior on height {
                enabled: root.isPresented
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
            }

            ScoopV2 {
                anchors.fill: parent
                position: "bottomCenter"
                color: Theme.bgc
                radius: Theme.rounding
                cornerRadius: Theme.rounding
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                z: root.deleteConfirmOpen ? 20 : 0
                focus: true

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    if (root.deleteConfirmOpen) {
                        if (deleteConfirm.handleKey(event)) event.accepted = true
                        return
                    }

                    if (event.key === Qt.Key_Delete) {
                        root.requestDeleteSelected()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        if (root.filterText) root.setFilter("")
                        else root.cancel()
                        event.accepted = true
                    } else if (root.editsFilter(event)) {
                        root.setFilter(root.editedFilter(event))
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
                        if (root.dmenuActive) {
                            if (root.mode === "input") root.applyDmenuSelection(root.filterText)
                            else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
                        } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
                        else if (displayModel.count > 0) root.cursorActive = true
                        event.accepted = true
                    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                               && event.text.charCodeAt(0) !== 127
                               && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                        root.setFilter(root.filterText + event.text)
                        event.accepted = true
                    }
                }
            }

            ConfirmDialog {
                id: deleteConfirm

                anchors.fill: parent
                opened: root.deleteConfirmOpen
                z: 10
                message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
                confirmText: "Uninstall"
                onCanceled: root.cancelDelete()
                onConfirmed: root.confirmDelete()
            }

            ColumnLayout {
                anchors.fill: parent
                // Aligns to the painted card edge, not the oversized item box.
                anchors.leftMargin: Theme.rounding + Theme.borderWidth + root.contentMargin
                anchors.rightMargin: Theme.rounding + Theme.borderWidth + root.contentMargin
                anchors.topMargin: root.contentMargin
                anchors.bottomMargin: root.bottomInset
                spacing: root.contentSpacing

                // --- Header ---
                Item {
                    id: headerArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.headerHeight

                    RowLayout {
                        anchors.fill: parent
                        spacing: Theme.spacing

                        Rectangle {
                            id: backButton
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 6
                            color: Theme.surface
                            visible: root.activeMenu !== "root" && !root.filterText && !root.dmenuActive

                            Text {
                                anchors.centerIn: parent
                                text: "󰁍"
                                color: Theme.brand
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.goBack()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
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
                                    text: root.dmenuActive ? "󰍉" : "󰍉"
                                    color: root.filterText ? Theme.brand : Theme.darkForeground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (root.filterText) return root.filterText
                                        if (root.dmenuActive) return root.dmenuPrompt + "…"
                                        var entry = root.item(root.activeMenu)
                                        return ((entry ? (entry.title || entry.label) : "Go")) + "…"
                                    }
                                    color: root.filterText ? Theme.foreground : Theme.darkForeground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: !!root.filterText
                                    text: "󰅖"
                                    color: Theme.darkForeground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setFilter("")
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.selection
                    visible: !(root.dmenuActive && root.mode === "input")
                }

                // --- Rows ---
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !(root.dmenuActive && root.mode === "input")

                    ListView {
                        id: resultList
                        anchors.fill: parent
                        model: displayModel
                        clip: true
                        spacing: root.rowSpacing
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: false

                        section.property: "section"
                        section.criteria: ViewSection.FullString
                        section.delegate: Item {
                            required property string section

                            width: ListView.view.width
                            height: section === "drilldown" ? root.dividerHeight : 0
                            visible: section === "drilldown"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                height: 1
                                color: Theme.selection
                            }
                        }

                        WheelHandler {
                            target: null
                            property real wheelAccumulator: 0
                            onWheel: function(event) {
                                if ((wheelAccumulator > 0 && event.angleDelta.y < 0) || (wheelAccumulator < 0 && event.angleDelta.y > 0))
                                    wheelAccumulator = 0
                                wheelAccumulator += event.angleDelta.y
                                var threshold = 120
                                while (wheelAccumulator <= -threshold) {
                                    root.select(1)
                                    wheelAccumulator += threshold
                                }
                                while (wheelAccumulator >= threshold) {
                                    root.select(-1)
                                    wheelAccumulator -= threshold
                                }
                                event.accepted = true
                            }
                        }

                        delegate: Rectangle {
                            id: rowItem
                            required property int index
                            required property string itemId
                            required property string kind
                            required property string icon
                            required property string iconFont
                            required property string appIcon
                            required property string appId
                            required property string label
                            required property string detail

                            readonly property bool hasCursor: root.cursorActive && rowItem.index === root.selectedIndex
                            readonly property bool isApp: rowItem.kind === "app"
                            readonly property bool hasIcon: rowItem.icon.length > 0 || rowItem.isApp

                            width: ListView.view.width
                            height: root.rowHeightForDetail(rowItem.detail)
                            radius: 6
                            color: rowItem.hasCursor ? Theme.selection : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 10

                                Item {
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22

                                    Image {
                                        id: appIconImage
                                        anchors.fill: parent
                                        visible: rowItem.isApp && status !== Image.Error && status !== Image.Null
                                        source: rowItem.isApp && rowItem.appIcon ? root.iconSource(rowItem.appIcon) : ""
                                        sourceSize.width: 22 * Screen.devicePixelRatio
                                        sourceSize.height: 22 * Screen.devicePixelRatio
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !appIconImage.visible
                                        text: rowItem.icon || (rowItem.isApp ? "󰀻" : "")
                                        color: rowItem.hasCursor ? Theme.brand : Theme.foreground
                                        font.family: rowItem.iconFont.length > 0 ? rowItem.iconFont : Theme.fontFamily
                                        font.pixelSize: 13
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: rowItem.label
                                        color: rowItem.hasCursor ? Theme.brand : Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: rowItem.hasCursor
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: (root.filterText || rowItem.kind === "dmenu") && rowItem.detail.length > 0
                                        text: rowItem.detail
                                        color: Theme.lightForeground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    text: (rowItem.kind === "menu" || rowItem.kind === "link") ? "󰅂" : ""
                                    color: rowItem.hasCursor ? Theme.brand : Theme.darkForeground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    visible: text !== ""
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    root.cursorActive = true
                                    root.selectedIndex = rowItem.index
                                }
                                onClicked: {
                                    root.cursorActive = true
                                    root.selectedIndex = rowItem.index
                                    root.activateIndex(rowItem.index)
                                }
                            }
                        }
                    }

                    // Edge scrims, strength driven by how much is hidden past
                    // each edge so a wrap-around jump lands already faded.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Math.min(20, parent.height / 2)
                        visible: opacity > 0
                        opacity: resultList.contentHeight > resultList.height
                            ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height)) : 0
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.bgc }
                            GradientStop { position: 1; color: Qt.rgba(Theme.bgc.r, Theme.bgc.g, Theme.bgc.b, 0) }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Math.min(20, parent.height / 2)
                        visible: opacity > 0
                        opacity: resultList.contentHeight > resultList.height
                            ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height)) : 0
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(Theme.bgc.r, Theme.bgc.g, Theme.bgc.b, 0) }
                            GradientStop { position: 1; color: Theme.bgc }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: displayModel.count === 0 && root.mode !== "input"

                        Text {
                            text: "󰈉"
                            color: Theme.brand
                            opacity: 0.8
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            horizontalAlignment: Text.AlignHCenter
                            width: 320
                        }

                        Text {
                            text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
                            color: Theme.foreground
                            opacity: 0.7
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            width: 320
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Filter editing helpers (shared semantics with the stock menu)
    // ------------------------------------------------------------------

    function editsFilter(event) {
        if (!root.filterText) return false
        if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) return false
        if (event.key === Qt.Key_U) return event.modifiers === Qt.ControlModifier
        return event.key === Qt.Key_Backspace
    }

    function editedFilter(event) {
        if (event.key === Qt.Key_U) return ""
        if (event.modifiers & Qt.ControlModifier) return root.filterText.replace(/\s+$/, "").replace(/\S+$/, "")
        return root.filterText.slice(0, -1)
    }
}