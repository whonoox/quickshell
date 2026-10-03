import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications

import "NotificationLogic.js" as Logic

// Notification daemon and toast stack for this config.
//
// This process owns org.freedesktop.Notifications, so every sender on the bus --
// omarchy-notification-send, libnotify apps, hooks, reminders -- lands here. The
// built-in omarchy.notifications plugin must be disabled for that to work:
//
//   omarchy plugin disable omarchy.notifications
//
// Toasts are a passive surface: Overlay layer, no keyboard focus, no exclusion,
// click-through everywhere except the cards themselves. They must never steal
// input from the focused application.
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string settingsPath: home + "/.local/state/omarchy/notifications.json"

    property bool doNotDisturb: false
    property bool _hydrating: false

    // Live Notification objects by originalId. Deliberately a JS map and not a
    // ListModel role: a QObject stored in a model role becomes a dangling
    // pointer the moment the server destroys it, and the next read of that role
    // segfaults in QQmlListModel::data. A JS map holds a wrapper, which degrades
    // to a catchable error instead.
    property var liveRefs: ({})

    function shellQuote(value) {
        return "'" + String(value === undefined || value === null ? "" : value).replace(/'/g, "'\\''") + "'"
    }

    // ------------------------------------------------------------------
    // Snapshot
    // ------------------------------------------------------------------

    function snapshotOf(notification) {
        var id = notification.id
        var expireTimeout = Number(notification.expireTimeout)
        if (!isFinite(expireTimeout) || expireTimeout < 0) expireTimeout = 0

        var desktopEntry = Logic.desktopEntryFrom(notification)
        var imagePath = Logic.extractImagePath(notification.image, notification.hints, notification.appIcon, notification.body, notification.summary)
        var actionsJson = JSON.stringify(Logic.actionListFrom(notification.actions))

        return {
            id: id,
            originalId: id,
            app: String(notification.appName || ""),
            appIcon: String(notification.appIcon || ""),
            summary: String(notification.summary || ""),
            body: String(notification.body || ""),
            image: String(notification.image || ""),
            glyph: Logic.glyphFromHints(notification.hints),
            execArgv: Logic.execArgvFromHints(notification.hints),
            urgency: notification.urgency,
            expireTimeout: expireTimeout,
            desktopEntry: desktopEntry,
            imagePath: imagePath,
            actionsJson: actionsJson,
            timestamp: Date.now()
        }
    }

    // A replaces_id update lands on the same object rather than firing a second
    // onNotification, so the row is refreshed in place -- keeping the original id
    // AND timestamp so nothing that keys off either has to change.
    function replacementSnapshot(notification, originalId, timestamp) {
        var next = snapshotOf(notification)
        next.id = originalId
        next.originalId = originalId
        next.timestamp = timestamp
        return next
    }

    readonly property var popupRoles: ["app", "appIcon", "summary", "body", "image", "glyph", "execArgv", "urgency", "expireTimeout", "desktopEntry", "imagePath", "actionsJson"]

    function popupRowChanged(before, after) {
        if (!before || !after) return false
        var roles = root.popupRoles
        for (var i = 0; i < roles.length; i++) {
            var role = roles[i]
            if (String(before[role] === undefined ? "" : before[role]) !== String(after[role] === undefined ? "" : after[role])) {
                return true
            }
        }
        return false
    }

    // ------------------------------------------------------------------
    // Ingest
    // ------------------------------------------------------------------

    property var updateSignals: [
        "summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
        "imageChanged", "urgencyChanged", "expireTimeoutChanged", "hintsChanged",
        "desktopEntryChanged", "actionsChanged"
    ]

    function handleNotification(notification) {
        root.dismissTimer.stop()
        if (root.isDismissing) {
            popupModel.clear()
            root.isDismissing = false
        }

        // Without this the Notification object is destroyed the moment this
        // handler returns, taking the reference the cards need with it.
        notification.tracked = true

        var snapshot = root.snapshotOf(notification)
        root.liveRefs[snapshot.originalId] = notification

        notification.closed.connect(function () {
            if (root.liveRefs[snapshot.originalId] === notification) {
                delete root.liveRefs[snapshot.originalId]
            }
        })

        if (root.doNotDisturb && !Logic.shouldBypassDnd(notification)) {
            // A silenced notification is still tracked until it is dropped, so
            // the sender is not told it closed while we are still reading it.
            if (Logic.isEphemeral(notification)) {
                if (root.liveRefs[snapshot.originalId] === notification) {
                    delete root.liveRefs[snapshot.originalId]
                }
                notification.tracked = false
                return
            }
            root.silenced.push(snapshot)
            if (root.silenced.length > 20) root.silenced = root.silenced.slice(1)
            return
        }

        root.watchForUpdates(notification, snapshot)
        popupModel.insert(0, snapshot)
    }

    // Notifications held back by DND, so they can be surfaced rather than lost.
    property var silenced: []

    function watchForUpdates(notification, snapshot) {
        for (var i = 0; i < root.updateSignals.length; i++) {
            (function (signalName) {
                notification[signalName].connect(function () {
                    root.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
                })
            })(root.updateSignals[i])
        }
    }

    function refreshPopup(notification, originalId, timestamp) {
        if (root.liveRefs[originalId] !== notification) return

        var updated = root.replacementSnapshot(notification, originalId, timestamp)
        for (var i = 0; i < popupModel.count; i++) {
            var row = popupModel.get(i)
            if (!row || row.originalId !== originalId || row.timestamp !== timestamp) continue
            // Bail unless something visible actually changed, so a burst of hint
            // updates does not rewrite the row repeatedly.
            if (!root.popupRowChanged(row, updated)) return
            // ListModel.get() hands back a read-only view: assigning to its
            // roles throws "Cannot assign to read-only property". Write each
            // role through setProperty instead, which is also what keeps the
            // delegate from being recreated.
            for (var r = 0; r < root.popupRoles.length; r++) {
                popupModel.setProperty(i, root.popupRoles[r], updated[root.popupRoles[r]])
            }
            return
        }
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function durationFor(urgency, expireTimeout) {
        return Logic.durationFor(urgency, expireTimeout, NotificationUrgency.Critical)
    }

    function dismissPopup(index) { root.removePopup(index, "dismiss") }

    function expirePopup(index) { root.removePopup(index, "expire") }

    function removePopup(index, reason) {
        if (index < 0 || index >= popupModel.count || root.isDismissing) return
        var originalId = popupModel.get(index) ? popupModel.get(index).originalId : -1
        var ref = originalId >= 0 ? root.liveRefs[originalId] : null

        if (ref) {
            // Guarded: the server may have destroyed the object between the last
            // read and this call.
            try {
                if (ref.tracked) {
                    if (reason === "expire" && typeof ref.expire === "function") ref.expire()
                    else ref.dismiss()
                }
            } catch (e) { }
        }

        if (popupModel.count <= 1) {
            root.isDismissing = true
            root.dismissTimer.restart()
        } else {
            popupModel.remove(index)
        }
    }

    function clearPopups() {
        if (popupModel.count === 0 || root.isDismissing) return
        for (var i = 0; i < popupModel.count; i++) {
            var row = popupModel.get(i)
            var ref = row && row.originalId >= 0 ? root.liveRefs[row.originalId] : null
            if (ref) {
                try {
                    if (ref.tracked) ref.dismiss()
                } catch (e) { }
            }
        }
        root.isDismissing = true
        root.dismissTimer.restart()
    }

    function resolveIcon(icon) {
        if (!icon || icon.length === 0) return ""
        if (icon.indexOf("/") !== -1) {
            return icon.startsWith("file://") ? icon : ("file://" + icon)
        }
        var resolved = Quickshell.iconPath(icon, true)
        if (resolved && resolved.length > 0) return resolved
        return ""
    }

    function focusAppCandidates(entry) {
        var candidates = Logic.focusCandidatesFor(entry)
        if (!candidates || candidates.length === 0) return

        var script = [
            'for cand in "$@"; do',
            '  [[ -n "$cand" ]] || continue',
            '  match=$(hyprctl clients -j 2>/dev/null | jq -r --arg pattern "$cand" \'',
            '    def matches($v): ($v // "") | test($pattern; "i");',
            '    first(.[] | select(matches(.class) or matches(.initialClass) or matches(.title))) |',
            '    "\\(.workspace.id // .workspace.name // "") \\(.address // "")"',
            '  \')',
            '  if [[ -n "$match" && "$match" != " " ]]; then',
            '    read -r ws addr <<< "$match"',
            '    if [[ -n "$ws" ]]; then',
            '      hyprctl dispatch "hl.dsp.focus({ workspace = \\"$ws\\" })" >/dev/null 2>&1 || \\',
            '        hyprctl dispatch workspace "$ws" >/dev/null 2>&1',
            '    fi',
            '    if [[ -n "$addr" ]]; then',
            '      hyprctl dispatch "hl.dsp.focus({ window = \\"address:$addr\\" })" >/dev/null 2>&1 || \\',
            '        hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1',
            '    fi',
            '    exit 0',
            '  fi',
            'done',
            'exit 1'
        ].join('\n')

        Quickshell.execDetached(["bash", "-c", script, "bash"].concat(candidates))
    }

    function openMediaFile(filePath, isScreenshot) {
        if (!filePath) return
        var script = [
            'file="$1"',
            'is_screen="$2"',
            'if [[ "$is_screen" == "true" ]]; then',
            '  editor="${OMARCHY_SCREENSHOT_EDITOR:-tensaku-edit}"',
            '  if command -v "$editor" >/dev/null 2>&1; then',
            '    exec "$editor" "$file"',
            '  fi',
            'fi',
            'exec xdg-open "$file"'
        ].join('\n')

        Quickshell.execDetached(["bash", "-c", script, "bash", filePath, isScreenshot ? "true" : "false"])
    }

    function invokePopupDefault(index) {
        if (index < 0 || index >= popupModel.count) return "none"
        var entry = popupModel.get(index)
        if (!entry) return "none"

        // 1. omarchy-supplied argv (e.g. omarchy-capture-screenshot --exec)
        var argv = Logic.parseExecArgv(entry.execArgv)
        if (argv) {
            Quickshell.execDetached(["bash", "-c", 'exec "$@"', "bash"].concat(argv))
            root.dismissPopup(index)
            return "ok"
        }

        // 2. Primary action in ref.actions (default, open, view, etc.)
        var ref = entry.originalId >= 0 ? root.liveRefs[entry.originalId] : null
        var actionInvoked = false
        try {
            if (ref && ref.actions && ref.actions.length > 0) {
                var action = Logic.findPrimaryAction(ref.actions)
                if (action) {
                    action.invoke()
                    actionInvoked = true
                }
            }
        } catch (e) { }

        // 3. Media / screenshot file fallback
        var imagePath = String(entry.imagePath || "")
        var isScreenshot = Logic.isScreenshotNotification(entry)
        if (imagePath && (isScreenshot || !actionInvoked)) {
            root.openMediaFile(imagePath, isScreenshot)
        }

        // 4. Focus sending window in Hyprland
        root.focusAppCandidates(entry)

        root.dismissPopup(index)
        return "ok"
    }

    function invokePopupAction(index, actionId) {
        if (index < 0 || index >= popupModel.count) return "none"
        var entry = popupModel.get(index)
        if (!entry) return "none"

        var ref = entry.originalId >= 0 ? root.liveRefs[entry.originalId] : null
        try {
            if (ref && ref.actions) {
                for (var i = 0; i < ref.actions.length; i++) {
                    var action = ref.actions[i]
                    if (action && action.identifier === actionId) {
                        action.invoke()
                        break
                    }
                }
            }
        } catch (e) { }

        root.focusAppCandidates(entry)
        root.dismissPopup(index)
        return "ok"
    }

    // ------------------------------------------------------------------
    // Do Not Disturb
    // ------------------------------------------------------------------

    function setDoNotDisturb(value) {
        root.doNotDisturb = !!value
    }

    // Persisted so the choice survives a shell restart, not just an in-process
    // reload. 200ms debounce, and never written while hydrating or the write
    // would immediately re-trigger itself.
    Timer {
        id: settingsSaveTimer
        interval: 200
        onTriggered: {
            if (root._hydrating) return
            settingsWrite.text = JSON.stringify({ version: 3, dnd: root.doNotDisturb }, null, 2) + "\n"
        }
    }

    FileView {
        id: settingsWrite
        path: root.settingsPath
        printErrors: false
    }

    FileView {
        id: settingsRead
        path: root.settingsPath
        printErrors: false
        onLoaded: {
            var raw = text()
            if (!raw) return
            root._hydrating = true
            try {
                var parsed = JSON.parse(raw)
                root.doNotDisturb = !!(parsed && parsed.dnd)
            } catch (e) { }
            root._hydrating = false
        }
    }

    onDoNotDisturbChanged: {
        if (root._hydrating) return
        settingsSaveTimer.restart()
    }

    Component.onCompleted: settingsRead.reload()

    // ------------------------------------------------------------------
    // Daemon
    // ------------------------------------------------------------------

    NotificationServer {
        id: server
        // True, unlike the stock service: this is the process that owns the bus
        // name, and a QML reload must not drop it and re-race the handover.
        keepOnReload: true
        imageSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true

        onNotification: function (notification) { root.handleNotification(notification) }
    }

    ListModel { id: popupModel }

    // Aliased rather than referenced as `root.popupModel` from the per-screen
    // delegate below: a bare id is not reachable through the root object from
    // inside a Variants delegate, which is the same scope trap that bit
    // `root.cardContainer` in the menu and `forgetConfirm` in the bluetooth bar.
    property alias popups: popupModel
    property bool isDismissing: false
    readonly property bool isPresented: popupModel.count > 0 && !isDismissing

    property Timer dismissTimer: Timer {
        id: dismissTimer
        interval: 260
        onTriggered: {
            popupModel.clear()
            root.isDismissing = false
        }
    }

    // ------------------------------------------------------------------
    // IPC -- same target and method names the stock service exposed, so
    // omarchy-notification-dismiss, the DND toggle and the hypr keybindings
    // keep working unchanged.
    // ------------------------------------------------------------------

    IpcHandler {
        target: "notifications"

        function dndState(): string { return root.doNotDisturb ? "on" : "off" }

        function isDnd(): string { return root.dndState() }

        function toggleDnd(): string {
            root.setDoNotDisturb(!root.doNotDisturb)
            return root.dndState()
        }

        function setDnd(value: string): string {
            var text = String(value === undefined || value === null ? "" : value).toLowerCase()
            root.setDoNotDisturb(text === "true" || text === "1" || text === "on" || text === "yes")
            return root.dndState()
        }

        function showHistory(): string { return "ok" }

        function dismissAll(): string { root.clearPopups(); return "ok" }

        function dismissOne(): string {
            if (popupModel.count === 0) return "none"
            root.dismissPopup(0)
            return "ok"
        }

        function invokeLast(): string {
            if (popupModel.count === 0) return "none"
            return root.invokePopupDefault(0)
        }

        // Case-sensitive substring, iterating backwards so removals do not shift
        // the indices still to be checked.
        function dismiss(summary: string): string {
            var needle = String(summary === undefined || summary === null ? "" : summary)
            if (!needle) return "none"
            for (var i = 0; i < popupModel.count; i++) {
                var row = popupModel.get(i)
                if (row && String(row.summary).indexOf(needle) !== -1) {
                    root.dismissPopup(i)
                    return "ok"
                }
            }
            for (var j = popupModel.count - 1; j >= 0; j--) {
                var older = popupModel.get(j)
                if (older && String(older.summary).indexOf(needle) !== -1) {
                    root.dismissPopup(j)
                    return "ok"
                }
            }
            return "none"
        }

        function inspectLast(): string {
            if (popupModel.count === 0) return "{}"
            var r = popupModel.get(0)
            return JSON.stringify({
                app: r.app,
                appIcon: r.appIcon,
                summary: r.summary,
                body: r.body,
                image: r.image,
                glyph: r.glyph,
                execArgv: r.execArgv,
                desktopEntry: r.desktopEntry,
                imagePath: r.imagePath,
                actionsJson: r.actionsJson
            })
        }

        function ping(): string { return "ok" }
    }

    // ------------------------------------------------------------------
    // Window
    // ------------------------------------------------------------------

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: toastWindow
            required property var modelData
            screen: modelData
            visible: root.popups.count > 0 || root.isDismissing

            anchors { top: true; bottom: true; left: true; right: true }

            WlrLayershell.namespace: "notification-panel-main"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            // Only the tray is an interactive region; the rest of the
            // full-screen overlay stays click-through so a toast never eats a
            // click meant for the window beneath.
            mask: Region { item: tray }

            // One container docked into the corner holding every live
            // notification as a list, rather than a stack of separate cards.
            // The Omarchy bar sits at the top, so the bottom-right corner is
            // free and nothing needs to clear it.
            Item {
                id: tray

                // The bottomRight contour runs its path along the item's right
                // and bottom edges and strokes outward by borderWidth, so the
                // painted card sits borderWidth OUTSIDE these bounds. Backing
                // the margins off by that much is what makes the card meet the
                // corner instead of floating a few pixels shy of it.
                readonly property int paintOutset: Theme.borderWidth

                width: 400 + 2 * Theme.borderWidth
                height: list.height + (Theme.rounding + Theme.spacing) + (Theme.borderWidth + Theme.spacing)

                Behavior on height {
                    enabled: root.isPresented
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -tray.paintOutset
                anchors.bottomMargin: -tray.paintOutset

                // Slides up from below the corner edge as one unit, on a
                // transform so the motion stays off the layout pass.
                transform: Translate {
                    id: slide
                    y: root.isPresented ? 0 : (tray.height + 60)

                    Behavior on y {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                }

                ScoopV2 {
                    anchors.fill: parent
                    position: "bottomRight"
                    color: Theme.bgc
                    radius: Theme.rounding
                    cornerRadius: Theme.rounding
                }

                ListView {
                    id: list
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: Theme.rounding + Theme.spacing * 2
                    anchors.rightMargin: Theme.borderWidth + Theme.spacing * 2
                    anchors.topMargin: Theme.rounding + Theme.spacing
                    height: Math.min(contentHeight, 460)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height
                    model: root.popups

                    // Only the container is interactive; the rest of the
                    // full-screen overlay stays click-through so a toast never
                    // eats a click meant for the window beneath.
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        id: row
                        required property int index
                        required property string app
                        required property string appIcon
                        required property string summary
                        required property string body
                        required property string image
                        required property string glyph
                        required property string execArgv
                        required property int urgency
                        required property int expireTimeout

                        required property string desktopEntry
                        required property string imagePath
                        required property string actionsJson

                        readonly property var actionList: {
                            try {
                                return row.actionsJson ? JSON.parse(row.actionsJson) : []
                            } catch (e) {
                                return []
                            }
                        }

                        readonly property real lifetime: root.durationFor(row.urgency, row.expireTimeout)
                        property real remaining: 1.0
                        readonly property bool ticking: row.lifetime > 0 && !rowMouse.containsMouse && !root.isDismissing
                        readonly property color accent: row.urgency === NotificationUrgency.Critical
                            ? Theme.red
                            : (row.urgency === NotificationUrgency.Low ? Qt.darker(Theme.foreground, 1.4) : Theme.brand)

                        width: list.width
                        height: rowColumn.height + Theme.spacing * 3

                        // A 50ms decrementing fraction rather than a wall-clock
                        // deadline, so hovering pauses it and a content update
                        // can hand back a full lifetime without re-arming.
                        Timer {
                            interval: 50
                            repeat: true
                            running: row.ticking
                            onTriggered: {
                                if (row.remaining <= 0) return
                                row.remaining -= 50.0 / row.lifetime
                                if (row.remaining <= 0) {
                                    row.remaining = 0
                                    root.expirePopup(row.index)
                                }
                            }
                        }

                        onSummaryChanged: remaining = 1.0
                        onBodyChanged: remaining = 1.0

                        // Hairline between entries so the list reads as one
                        // surface rather than a pile of cards.
                        Rectangle {
                            visible: row.index > 0
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 1
                            color: Qt.rgba(Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.6)
                        }

                        Rectangle {
                            visible: row.urgency !== NotificationUrgency.Low
                            width: 3
                            height: row.height - Theme.spacing * 3
                            anchors.left: parent.left
                            anchors.leftMargin: -Theme.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 1.5
                            color: row.accent
                        }

                        Row {
                            id: rowColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: Theme.spacing * 1.5
                            spacing: Theme.spacing

                            readonly property bool showIcon: row.glyph.length > 0 || row.image.length > 0 || row.appIcon.length > 0

                            // omarchy-notification-send passes its glyph through
                            // a custom hint rather than app_icon, so the glyph is
                            // the slot that actually gets used in practice.
                            Rectangle {
                                width: 28
                                height: 28
                                visible: rowColumn.showIcon
                                radius: 8
                                color: Theme.surface
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true

                                Text {
                                    anchors.fill: parent
                                    visible: row.glyph.length > 0
                                    text: row.glyph
                                    color: row.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: row.image.length > 0 ? 0 : 5
                                    visible: row.glyph.length === 0 && (row.image.length > 0 || row.appIcon.length > 0)
                                    source: row.image.length > 0 ? row.image : root.resolveIcon(row.appIcon)
                                    asynchronous: true
                                    fillMode: row.image.length > 0 ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                    sourceSize.width: 28 * Screen.devicePixelRatio
                                    sourceSize.height: 28 * Screen.devicePixelRatio
                                }
                            }

                            Column {
                                width: Math.max(0, parent.width - (rowColumn.showIcon ? 28 + Theme.spacing : 0))
                                spacing: 3

                                Text {
                                    width: parent.width
                                    text: row.app.toUpperCase()
                                    color: Theme.darkForeground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: row.summary
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: text.length > 0
                                    text: Logic.sanitizeBody(row.body)
                                    textFormat: Text.StyledText
                                    color: Theme.lightForeground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                }

                                Flow {
                                    width: parent.width
                                    spacing: 6
                                    visible: row.actionList && row.actionList.length > 0

                                    Repeater {
                                        model: row.actionList
                                        delegate: Rectangle {
                                            id: actionBtn
                                            required property var modelData
                                            width: btnText.implicitWidth + 14
                                            height: 22
                                            radius: 6
                                            color: actionBtnMouse.containsMouse ? Theme.brand : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
                                            border.width: 1
                                            border.color: actionBtnMouse.containsMouse ? Theme.brand : Qt.rgba(Theme.muted.r, Theme.muted.g, Theme.muted.b, 0.6)

                                            Text {
                                                id: btnText
                                                anchors.centerIn: parent
                                                text: actionBtn.modelData.text
                                                color: actionBtnMouse.containsMouse ? Theme.darkerBackground : Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: true
                                            }

                                            MouseArea {
                                                id: actionBtnMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.invokePopupAction(row.index, actionBtn.modelData.identifier)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Left click acts, right click dismisses. Hover pauses
                        // the countdown, which is the third and last affordance.
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.isDismissing
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function (mouse) {
                                if (mouse.button === Qt.RightButton) root.dismissPopup(row.index)
                                else root.invokePopupDefault(row.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
