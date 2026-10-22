import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import "BluetoothModel.js" as Model

Scope {
    id: root

    property bool hudVisible: false
    property bool isExpanded: false
    readonly property bool hideAll: !hudVisible && !isExpanded
    property real lastToggleTime: 0
    property bool focusPrimed: false

    // Keyboard Navigation State
    property string focusSection: "devices" // "header" | "devices"
    property int headerIndex: 1            // 0: Scan, 1: Bluetooth Power Switch
    property int selectedDeviceIndex: 0
    property bool deviceActionFocused: false

    // Rename state
    property bool renaming: false
    property string renameAddress: ""
    property string renameText: ""

    // The favorited device addresses, re-read whenever the file changes.
    readonly property var favoriteAddresses: {
        var raw = favoritesFile.text
        if (!raw) return []
        var out = []
        var lines = String(raw).split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line) out.push(line)
        }
        return out
    }

    // Bluetooth Adapter & Devices
    readonly property var adapter: Bluetooth.defaultAdapter
    property int deviceStateVersion: 0

    readonly property var allDevices: (Bluetooth.devices && Bluetooth.devices.values) ? Bluetooth.devices.values : []
    readonly property var deviceGroups: {
        var _ = deviceStateVersion
        return Model.deviceLists(allDevices)
    }

    readonly property var connectedDevices: deviceGroups.connected || []
    readonly property var knownDevices: deviceGroups.known || []
    readonly property var discoveredDevices: deviceGroups.discovered || []

    readonly property var primaryConnectedDevice: connectedDevices.length > 0 ? connectedDevices[0] : null
    readonly property bool hasConnection: primaryConnectedDevice !== null

    // Connection Monitoring for Auto-Reveal on Connect
    readonly property string connectedDevicesKey: {
        var _ = deviceStateVersion
        if (!connectedDevices || connectedDevices.length === 0) return ""
        var addrs = []
        for (var i = 0; i < connectedDevices.length; i++) {
            var dev = connectedDevices[i]
            if (dev && dev.address) addrs.push(dev.address)
        }
        addrs.sort()
        return addrs.join(",")
    }
    property var prevConnectedAddrs: []
    property bool connectionWatchReady: false

    function currentConnectedAddrs() {
        var addrs = []
        if (root.connectedDevices) {
            for (var i = 0; i < root.connectedDevices.length; i++) {
                var d = root.connectedDevices[i]
                if (d && d.address) addrs.push(d.address)
            }
        }
        return addrs
    }

    function revealGlance() {
        if (root.isExpanded) return
        PopoutCoordinator.claim("bluetooth")
        root.hudVisible = true
        autoHideTimer.restart()
    }

    Timer {
        id: connectionStartupTimer
        interval: 1500
        running: true
        onTriggered: {
            root.prevConnectedAddrs = root.currentConnectedAddrs()
            root.connectionWatchReady = true
        }
    }

    onConnectedDevicesKeyChanged: {
        if (!root.connectionWatchReady) return
        var current = root.currentConnectedAddrs()
        var newlyConnected = false
        for (var i = 0; i < current.length; i++) {
            if (root.prevConnectedAddrs.indexOf(current[i]) === -1) {
                newlyConnected = true
                break
            }
        }
        if (newlyConnected) {
            root.revealGlance()
        }
        root.prevConnectedAddrs = current
    }

    Instantiator {
        model: (Bluetooth.devices && Bluetooth.devices.values) ? Bluetooth.devices.values : []
        delegate: Connections {
            target: modelData
            ignoreUnknownSignals: true
            function onConnectedChanged() {
                root.deviceStateVersion++
                if (!root.connectionWatchReady) return
                if (modelData && modelData.connected) {
                    root.revealGlance()
                }
            }
            function onPairedChanged() {
                root.deviceStateVersion++
            }
            function onStateChanged() {
                root.deviceStateVersion++
            }
            function onBatteryChanged() {
                root.deviceStateVersion++
            }
        }
    }

    // Flattened List of all interactive devices for unified ListView and keyboard navigation
    readonly property var flattenedDevices: {
        var list = []
        for (var c = 0; c < connectedDevices.length; c++) {
            list.push({ section: "connected", data: connectedDevices[c] })
        }
        for (var k = 0; k < knownDevices.length; k++) {
            list.push({ section: "known", data: knownDevices[k] })
        }
        if (adapter && adapter.discovering) {
            for (var d = 0; d < discoveredDevices.length; d++) {
                list.push({ section: "discovered", data: discoveredDevices[d] })
            }
        }
        return list
    }
    readonly property int totalDeviceCount: flattenedDevices.length

    // Clamp the cursor whenever the list changes underneath it. Devices move
    // between the connected/known/discovered buckets as they pair, connect and
    // get forgotten, and stopping discovery drops the discovered block entirely
    // -- so a stale index used to match no delegate at all, leaving the cursor
    // invisible and making the next Up/Down compute from a row that is gone.
    function clampDeviceCursor() {
        if (flattenedDevices.length === 0) {
            selectedDeviceIndex = 0
            deviceActionFocused = false
            return
        }
        if (selectedDeviceIndex >= flattenedDevices.length) selectedDeviceIndex = flattenedDevices.length - 1
        if (selectedDeviceIndex < 0) selectedDeviceIndex = 0
    }

    onFlattenedDevicesChanged: root.clampDeviceCursor()

    // Focus Priming Timer (75ms Exclusive focus so Hyprland transfers keyboard focus immediately)
    Timer {
        id: focusPrimeTimer
        interval: 75
        onTriggered: {
            if (root.isExpanded) root.focusPrimed = true
        }
    }

    onIsExpandedChanged: {
        if (isExpanded) {
            focusPrimed = false
            focusPrimeTimer.restart()
            focusSection = totalDeviceCount > 0 ? "devices" : "header"
            selectedDeviceIndex = 0
            deviceActionFocused = false
        } else {
            focusPrimeTimer.stop()
            focusPrimed = false
            // Auto stop discovery on close if running
            if (adapter && adapter.discovering) {
                adapter.discovering = false
            }
        }
    }

    onHideAllChanged: {
        if (hideAll) PopoutCoordinator.release("bluetooth")
    }

    Connections {
        target: PopoutCoordinator
        function onActiveChanged() {
            if (PopoutCoordinator.active !== "" && PopoutCoordinator.active !== "bluetooth") {
                root.isExpanded = false
                root.hudVisible = false
            }
        }
    }

    // IPC Handler
    IpcHandler {
        target: "bluetoothBar"
        function toggle() {
            if (root.hideAll) {
                PopoutCoordinator.claim("bluetooth")
                root.hudVisible = true
                root.isExpanded = false
            } else if (root.hudVisible && !root.isExpanded) {
                PopoutCoordinator.claim("bluetooth")
                root.isExpanded = true
                root.hudVisible = false
            } else {
                root.isExpanded = false
                root.hudVisible = false
                PopoutCoordinator.release("bluetooth")
            }
        }
        function open() {
            root.revealGlance()
        }
        function expand() {
            PopoutCoordinator.claim("bluetooth")
            root.isExpanded = true
            root.hudVisible = false
        }
        function close() {
            root.isExpanded = false
            root.hudVisible = false
            PopoutCoordinator.release("bluetooth")
        }
        function scan(): void {
            root.triggerScan()
        }
        function rescan(): void {
            root.triggerScan()
        }
    }

    // Global Shortcut Handler
    GlobalShortcut {
        name: "bluetoothToggle"
        description: "Show Bluetooth HUD on first press, expand Controller on second press"
        appid: "quickshell"
        onPressed: {
            var now = Date.now()
            if (now - root.lastToggleTime < 250) return
            root.lastToggleTime = now

            if (root.hideAll) {
                // 1st Press: Show glance HUD
                PopoutCoordinator.claim("bluetooth")
                root.hudVisible = true
                root.isExpanded = false
            } else if (root.hudVisible && !root.isExpanded) {
                // 2nd Press: Expand into full controller
                PopoutCoordinator.claim("bluetooth")
                root.isExpanded = true
                root.hudVisible = false
            } else {
                // 3rd Press or while expanded: Close
                root.isExpanded = false
                root.hudVisible = false
                PopoutCoordinator.release("bluetooth")
            }
        }
    }

    // Auto-hide Timer for Glance HUD (only active when collapsed)
    Timer {
        id: autoHideTimer
        interval: 3500
        running: root.hudVisible && !root.isExpanded
        onTriggered: {
            root.hudVisible = false
        }
    }

    // Helper Actions
    //
    // These go through the Quickshell Bluetooth API rather than shelling
    // out to omarchy-bluetooth-device. The packaged command needs
    // bluetoothctl and swallows every error, so a machine without it
    // showed buttons that silently did nothing.
    function toggleDiscovery() {
        if (adapter) adapter.discovering = !adapter.discovering
    }

    function triggerScan() {
        if (!adapter) return
        if (!adapter.enabled) {
            adapter.enabled = true
        }
        root.toggleDiscovery()
    }

    function togglePower() {
        if (adapter) adapter.enabled = !adapter.enabled
    }

    function launchBlueman() {
        Quickshell.execDetached(["hyprctl", "dispatch", "exec", "[float; size 750 500; center] blueman-manager"])
    }

    function connectDevice(dev) {
        if (!dev || !dev.deviceObject) return
        if (dev.connected) {
            dev.deviceObject.disconnect()
        } else if (dev.paired) {
            dev.deviceObject.connect()
        } else {
            dev.deviceObject.pair()
        }
    }

    function disconnectDevice(dev) {
        if (!dev || !dev.deviceObject) return
        dev.deviceObject.disconnect()
    }

    function forgetDevice(dev) {
        if (!dev || !dev.deviceObject) return
        dev.deviceObject.forget()
    }

    // Trust is a writable BlueZ property, but Quickshell only exposes it
    // read-only, so it goes through the system bus using the device's own
    // object path.
    function toggleTrust(dev) {
        if (!dev || !dev.deviceObject) return
        var path = dev.deviceObject.dbusPath
        if (!path) return
        var value = dev.deviceObject.trusted ? "false" : "true"
        Quickshell.execDetached(["busctl", "--system", "set", "org.bluez", path, "org.bluez.Device1", "Trusted", "b", value])
    }

    // Favorites are a property of this shell, not of Bluetooth. They are
    // kept in a state file, one address per line.
    function toggleFavorite(dev) {
        if (!dev || !dev.address) return
        Quickshell.execDetached([
            "bash", "-c",
            "file=\"$1\"; addr=\"$2\"; mkdir -p \"$(dirname \"$file\")\"; touch \"$file\"; " +
            "if grep -qxF \"$addr\" \"$file\"; then grep -vxF \"$addr\" \"$file\" >\"$file.tmp\" && mv \"$file.tmp\" \"$file\"; " +
            "else printf '%s\\n' \"$addr\" >>\"$file\"; fi",
            "_", favoritesFile.path, dev.address
        ])

        // The file is written by another process, so the watch may not see
        // it. Re-read it shortly after.
        favoritesReload.restart()
    }

    function isFavorite(dev) {
        if (!dev || !dev.address) return false
        return root.favoriteAddresses.indexOf(dev.address) >= 0
    }

    // Rename writes the device's alias, which is the writable "name"
    // property on the Quickshell device.
    //
    // The text field lives inside the panel's delegate, so the root
    // cannot reach it directly. The state is held here and the field
    // binds to it; the focus is moved by the delegate's Connections
    // block, which watches renamingChanged.
    function beginRename(dev) {
        if (!dev || !dev.deviceObject) return
        root.renameAddress = dev.address
        root.renameText = dev.deviceObject.name || dev.deviceName || dev.name || ""
        root.renaming = true
    }

    function commitRename() {
        if (!root.renaming) return
        var target = null
        for (var i = 0; i < root.flattenedDevices.length; i++) {
            var item = root.flattenedDevices[i]
            if (item && item.data && item.data.address === root.renameAddress) {
                target = item.data
                break
            }
        }
        if (target && target.deviceObject) {
            var text = String(root.renameText).trim()
            target.deviceObject.name = text
        }
        root.renaming = false
        root.renameText = ""
        root.renameAddress = ""
    }

    function cancelRename() {
        root.renaming = false
        root.renameText = ""
        root.renameAddress = ""
    }

    function revealDeviceCursor() {
        if (root.totalDeviceCount <= 0 || typeof deviceList === "undefined") return
        deviceList.currentIndex = root.selectedDeviceIndex
        if (deviceList.contentHeight > deviceList.height) {
            deviceList.positionViewAtIndex(root.selectedDeviceIndex, ListView.Contain)
        } else {
            deviceList.contentY = 0
        }
    }

    function selectDevice(delta) {
        if (root.totalDeviceCount <= 0) return
        root.focusSection = "devices"
        root.deviceActionFocused = false
        var next = root.selectedDeviceIndex + delta
        if (next < 0) {
            next = root.totalDeviceCount - 1
        } else if (next >= root.totalDeviceCount) {
            next = 0
        }
        root.selectedDeviceIndex = next
        root.revealDeviceCursor()
    }

    function activateHeader() {
        if (root.headerIndex === 0) {
            toggleDiscovery()
        } else if (root.headerIndex === 1) {
            togglePower()
        }
    }

    function activateSelectedDevice() {
        if (root.selectedDeviceIndex >= 0 && root.selectedDeviceIndex < root.totalDeviceCount) {
            var item = root.flattenedDevices[root.selectedDeviceIndex]
            if (!item || !item.data) return
            var dev = item.data

            if (dev.connected) {
                disconnectDevice(dev)
            } else {
                connectDevice(dev)
            }
        }
    }

    // The device the keyboard actions apply to.
    function selectedDevice() {
        if (root.selectedDeviceIndex < 0 || root.selectedDeviceIndex >= root.totalDeviceCount) return null
        var item = root.flattenedDevices[root.selectedDeviceIndex]
        return item && item.data ? item.data : null
    }

    // Favorites live in a state file, one address per line. The file is
    // watched so the star in the device list follows a change made
    // elsewhere.
    FileView {
        id: favoritesFile
        path: Quickshell.env("HOME") + "/.local/state/nooxshell/bluetooth-favorites"
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
    }

    Timer {
        id: favoritesReload
        interval: 300
        onTriggered: favoritesFile.reload()
    }

    // Multi-Monitor Twin Dismissal (For secondary monitors only)
    BarVariants {
        model: root.isExpanded ? Quickshell.screens : []

        delegate: Component {
            PanelWindow {
                required property var modelData
                screen: modelData

                visible: root.isExpanded && !!Quickshell.screens[0] && modelData.name !== Quickshell.screens[0].name

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                color: "transparent"
                exclusionMode: ExclusionMode.Ignore

                WlrLayershell.namespace: "bluetooth-panel-twin-dismiss"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: {
                        root.isExpanded = false
                        root.hudVisible = false
                    }
                }
            }
        }
    }

    // Main Bluetooth Bar & Controller Window
    BarVariants {
        primaryOnly: true

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            visible: !root.hideAll || (cardContainer.y > -(cardContainer.height + 10))

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "bluetooth-panel-main"
            WlrLayershell.layer: WlrLayer.Overlay
            // Exclusive prime for 75ms forces Hyprland to transfer focus immediately, then settles on OnDemand
            WlrLayershell.keyboardFocus: root.isExpanded
                ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
                : WlrKeyboardFocus.None

            // When collapsed: only cardContainer is clickable (0 blocked pixels elsewhere)
            // When expanded: full-screen mask enables backdrop outside-click dismissal
            mask: Region {
                item: root.isExpanded ? null : (!root.hideAll ? cardContainer : null)
                width: root.isExpanded ? (panelWindow.screen ? panelWindow.screen.width : 1920) : 0
                height: root.isExpanded ? (panelWindow.screen ? panelWindow.screen.height : 1080) : 0
            }

            // ================================================================
            // Layer 0: Backdrop Click Dismissal Area (BEHIND the card, active when expanded)
            // ================================================================
            MouseArea {
                id: backdropDismissArea
                anchors.fill: parent
                enabled: root.isExpanded
                acceptedButtons: Qt.AllButtons
                onPressed: {
                    root.isExpanded = false
                    root.hudVisible = false
                }
            }

            // ================================================================
            // Layer 1: Focus Scope & Card Container (IN FRONT of Layer 0)
            // ================================================================
            Item {
                id: focusScope
                anchors.fill: parent
                focus: true

                Connections {
                    target: root
                    function onIsExpandedChanged() {
                        if (root.isExpanded) {
                            Qt.callLater(function() {
                                focusScope.forceActiveFocus()
                            })
                        }
                    }
                    function onRenamingChanged() {
                        // The rename field lives down in the details
                        // column, so the focus is moved from here.
                        if (root.renaming) {
                            Qt.callLater(function() {
                                renameInput.forceActiveFocus()
                                renameInput.selectAll()
                            })
                        } else {
                            Qt.callLater(function() {
                                focusScope.forceActiveFocus()
                            })
                        }
                    }
                }

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    // While renaming, the text field owns the keyboard.
                    if (root.renaming) {
                        if (event.key === Qt.Key_Escape) {
                            root.cancelRename()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.commitRename()
                            event.accepted = true
                        }
                        return
                    }

                    if (event.key === Qt.Key_Escape) {
                        root.isExpanded = false
                        root.hudVisible = false
                        event.accepted = true
                        return
                    }

                    // A modifier means the key belongs to something else.
                    var plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                    var key = event.text ? event.text.toLowerCase() : ""

                    // --- Scan on/off ('s') ---
                    if (plain && key === "s") {
                        root.triggerScan()
                        event.accepted = true
                        return
                    }

                    // --- Unpair ('u') ---
                    if (plain && key === "u") {
                        var unpairTarget = root.selectedDevice()
                        if (unpairTarget) root.forgetDevice(unpairTarget)
                        event.accepted = true
                        return
                    }

                    // --- Un/Trust ('t') ---
                    if (plain && key === "t") {
                        var trustTarget = root.selectedDevice()
                        if (trustTarget) root.toggleTrust(trustTarget)
                        event.accepted = true
                        return
                    }

                    // --- Un/Favorite ('f') ---
                    if (plain && key === "f") {
                        var favoriteTarget = root.selectedDevice()
                        if (favoriteTarget) root.toggleFavorite(favoriteTarget)
                        event.accepted = true
                        return
                    }

                    // --- Rename ('e') ---
                    if (plain && key === "e") {
                        var renameTarget = root.selectedDevice()
                        if (renameTarget) root.beginRename(renameTarget)
                        event.accepted = true
                        return
                    }

                    // --- Up (Arrow Up) ---
                    if (event.key === Qt.Key_Up) {
                        if (root.focusSection === "devices") {
                            // Up from the first row escapes to the header
                            // rather than wrapping to the bottom of the
                            // list. Wrapping made everything above the
                            // list unreachable without Tab.
                            if (root.selectedDeviceIndex <= 0) {
                                root.focusSection = "header"
                                root.deviceActionFocused = false
                            } else {
                                root.selectDevice(-1)
                            }
                        }
                        event.accepted = true
                        return
                    }

                    // --- Down (Arrow Down) ---
                    if (event.key === Qt.Key_Down) {
                        if (root.focusSection === "header") {
                            if (root.totalDeviceCount > 0) {
                                root.focusSection = "devices"
                                if (root.selectedDeviceIndex < 0) root.selectedDeviceIndex = 0
                                root.deviceActionFocused = false
                                root.revealDeviceCursor()
                            }
                        } else if (root.focusSection === "devices") {
                            root.selectDevice(1)
                        }
                        event.accepted = true
                        return
                    }

                    // --- Arrow Left Navigation ---
                    if (event.key === Qt.Key_Left) {
                        if (root.focusSection === "header") {
                            root.headerIndex = Math.max(0, root.headerIndex - 1)
                        } else if (root.focusSection === "devices") {
                            root.deviceActionFocused = false
                        }
                        event.accepted = true
                        return
                    }

                    // --- Arrow Right Navigation ---
                    if (event.key === Qt.Key_Right) {
                        if (root.focusSection === "header") {
                            root.headerIndex = Math.min(1, root.headerIndex + 1)
                        } else if (root.focusSection === "devices") {
                            root.deviceActionFocused = true
                        }
                        event.accepted = true
                        return
                    }

                    // --- Tab / Shift+Tab Navigation ---
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        var forward = event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)
                        if (forward) {
                            if (root.focusSection === "header") root.focusSection = "devices"
                            else root.focusSection = "header"
                        } else {
                            if (root.focusSection === "devices") root.focusSection = "header"
                            else root.focusSection = "devices"
                        }
                        event.accepted = true
                        return
                    }

                    // --- Dis/Connect (Return / Enter / Space) ---
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        if (root.focusSection === "header") {
                            root.activateHeader()
                        } else if (root.focusSection === "devices") {
                            root.activateSelectedDevice()
                        }
                        event.accepted = true
                        return
                    }
                }

                // ============================================================
                // Pinned Right-Anchored Card Container
                // Fits dynamically to children with full bottom padding & max height cap
                // ============================================================
                Item {
                    id: cardContainer
                    anchors.right: parent.right
                    y: root.hideAll ? -(height + 30) : 0

                    width: (root.isExpanded ? 390 : Math.max(3 * Theme.rounding, btLabel.implicitWidth + (batteryPill.visible ? (batteryPill.width + Theme.spacing) : 0) + Theme.rounding * 3)) + 4
                    height: (root.isExpanded ? Math.min(520, summaryHeader.height + detailsColumn.implicitHeight + Theme.rounding + Theme.spacing * 2) : (Theme.rounding * 3)) + 4

                    Behavior on width {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on height {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    // Unified single-vector background contour (position: topRight)
                    ScoopV2 {
                        id: backgroundShape
                        anchors.fill: parent
                        position: "topRight"
                        color: Theme.bgc
                        radius: Theme.rounding
                        cornerRadius: Theme.rounding
                    }

                    // Main Content Container
                    Item {
                        id: background
                        anchors.fill: parent
                        anchors.leftMargin: Theme.rounding + 4
                        anchors.bottomMargin: Theme.rounding + 4
                        clip: true

                        // Swallow clicks on card so they do NOT bubble to Layer 0 backdrop
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                        }

                        // ====================================================
                        // 1. SUMMARY (Header - Always Visible)
                        // ====================================================
                        Item {
                            id: summaryHeader
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: Theme.rounding * 2

                            // Click header to toggle expansion
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.isExpanded = !root.isExpanded
                                    if (root.isExpanded) {
                                        PopoutCoordinator.claim("bluetooth")
                                        root.hudVisible = false
                                    } else {
                                        root.hudVisible = false
                                        PopoutCoordinator.release("bluetooth")
                                    }
                                }
                            }

                            // Device Label (Visually centered with corner scoops icon)
                            Text {
                                id: btLabel
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.topMargin: 10
                                anchors.leftMargin: Theme.spacing
                                text: {
                                    if (!root.adapter || !root.adapter.enabled) return "Bluetooth Off"
                                    if (root.hasConnection) {
                                        return root.primaryConnectedDevice.name || root.primaryConnectedDevice.deviceName || "Connected"
                                    }
                                    return "Bluetooth"
                                }
                                color: root.hasConnection ? Theme.brand : (root.adapter && root.adapter.enabled ? Theme.lightForeground : Theme.darkForeground)
                                font.family: Theme.brandFont
                                font.pixelSize: Theme.rounding
                                font.weight: Font.Bold
                                font.capitalization: Font.AllUppercase
                            }

                            // Small Pill Badge with Percentage as Number
                            Rectangle {
                                id: batteryPill
                                visible: root.hasConnection && root.primaryConnectedDevice.batteryAvailable && root.primaryConnectedDevice.battery > 0
                                anchors.left: btLabel.right
                                anchors.leftMargin: Theme.spacing
                                anchors.verticalCenter: btLabel.verticalCenter
                                anchors.verticalCenterOffset: -3
                                height: 18
                                width: batteryText.implicitWidth + 12
                                radius: 9
                                color: root.hasConnection && root.primaryConnectedDevice.battery < 0.2 
                                    ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25)
                                    : (root.hasConnection && root.primaryConnectedDevice.battery < 0.4 
                                        ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.25)
                                        : Qt.rgba(Theme.brand.r, Theme.brand.g, Theme.brand.b, 0.25))
                                border.color: root.hasConnection && root.primaryConnectedDevice.battery < 0.2 
                                    ? Theme.red 
                                    : (root.hasConnection && root.primaryConnectedDevice.battery < 0.4 ? Theme.yellow : Theme.brand)
                                border.width: 1

                                Text {
                                    id: batteryText
                                    anchors.centerIn: parent
                                    text: root.hasConnection ? Model.formatBattery(root.primaryConnectedDevice.battery) : ""
                                    color: root.hasConnection && root.primaryConnectedDevice.battery < 0.2 
                                        ? Theme.red 
                                        : (root.hasConnection && root.primaryConnectedDevice.battery < 0.4 ? Theme.yellow : Theme.brand)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            // Bluetooth Nested Concentric Scoops (Matching aesthetic design)
                            ScoopShape {
                                bgColor: root.hasConnection ? Theme.brand : Theme.brandBgc
                                anchors.top: parent.top
                                anchors.right: parent.right
                                cornerPosition: scoopPosition.bottomLeft
                            }

                            ScoopShape {
                                bgColor: root.hasConnection ? Theme.brand : Theme.brandBgc
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacing
                                anchors.topMargin: Theme.spacing
                                scale: 0.7
                                cornerPosition: scoopPosition.bottomLeft
                            }

                            ScoopShape {
                                bgColor: root.hasConnection ? Theme.brand : Theme.brandBgc
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacing * 2
                                anchors.topMargin: Theme.spacing * 2
                                scale: 0.5
                                cornerPosition: scoopPosition.bottomLeft
                            }
                        }

                        // ====================================================
                        // 2. DETAILS (Second Child - Below Header When Expanded)
                        // ====================================================
                        ColumnLayout {
                            id: detailsColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: summaryHeader.bottom
                            anchors.leftMargin: Theme.spacing * 2
                            anchors.rightMargin: Theme.spacing * 2
                            anchors.topMargin: Theme.spacing
                            spacing: Theme.spacing * 1.5
                            visible: root.isExpanded
                            opacity: root.isExpanded ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.selection
                            }

                            // --- Quick Actions / Controls Bar (Status on Left, Actions on Right) ---
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing

                                Text {
                                    text: {
                                        if (!root.adapter || !root.adapter.enabled) return "BLUETOOTH OFF"
                                        if (root.adapter.discovering) return "SCANNING..."
                                        if (root.connectedDevices.length > 0) return "CONNECTED (" + root.connectedDevices.length + ")"
                                        return "NOT CONNECTED"
                                    }
                                    color: {
                                        if (!root.adapter || !root.adapter.enabled) return Theme.red
                                        if (root.adapter.discovering) return Theme.cyan
                                        if (root.connectedDevices.length > 0) return Theme.brand
                                        return Theme.yellow
                                    }
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Spacer to push action buttons strictly to the right
                                Item {
                                    Layout.fillWidth: true
                                }

                                // Scan / Discovery Toggle Button
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 6
                                    color: (root.adapter && root.adapter.discovering) ? Qt.rgba(Theme.cyan.r, Theme.cyan.g, Theme.cyan.b, 0.25) : Theme.surface
                                    border.color: root.focusSection === "header" && root.headerIndex === 0 ? Theme.accent : (root.adapter && root.adapter.discovering ? Theme.cyan : Theme.selection)
                                    border.width: root.focusSection === "header" && root.headerIndex === 0 ? 1.5 : 1
                                    visible: root.adapter && root.adapter.enabled

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰂰"
                                        color: (root.adapter && root.adapter.discovering) ? Theme.cyan : Theme.lightForeground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onEntered: { root.focusSection = "header"; root.headerIndex = 0 }
                                        onClicked: root.toggleDiscovery()
                                    }
                                }

                                // Master Bluetooth Power Switch
                                Rectangle {
                                    width: 40
                                    height: 22
                                    radius: 11
                                    color: (root.adapter && root.adapter.enabled) ? Theme.brand : Theme.selection
                                    border.color: root.focusSection === "header" && root.headerIndex === 1 ? Theme.foreground : ((root.adapter && root.adapter.enabled) ? Theme.brand : Theme.darkForeground)
                                    border.width: root.focusSection === "header" && root.headerIndex === 1 ? 1.5 : 1

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: (root.adapter && root.adapter.enabled) ? parent.width - width - 3 : 3
                                        color: (root.adapter && root.adapter.enabled) ? Theme.darkBackground : Theme.lightForeground
                                        Behavior on x { NumberAnimation { duration: 150 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onEntered: { root.focusSection = "header"; root.headerIndex = 1 }
                                        onClicked: root.togglePower()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.selection
                            }

                            // --- Device Section Title ---
                            Text {
                                text: {
                                    if (!root.adapter || !root.adapter.enabled) return "BLUETOOTH DISABLED"
                                    if (root.totalDeviceCount === 0) return root.adapter.discovering ? "SEARCHING FOR DEVICES..." : "NO DEVICES FOUND"
                                    return "BLUETOOTH DEVICES"
                                }
                                color: Theme.darkForeground
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }

                            // --- Devices ListView ---
                            ListView {
                                id: deviceList
                                currentIndex: root.selectedDeviceIndex
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(Math.max(contentHeight, 35), 240)
                                Layout.fillHeight: false
                                clip: true
                                spacing: 4
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: false

                                WheelHandler {
                                    target: null
                                    property real wheelAccumulator: 0
                                    onWheel: function(event) {
                                        if ((wheelAccumulator > 0 && event.angleDelta.y < 0) || (wheelAccumulator < 0 && event.angleDelta.y > 0)) {
                                            wheelAccumulator = 0
                                        }
                                        wheelAccumulator += event.angleDelta.y
                                        var threshold = 120
                                        while (wheelAccumulator <= -threshold) {
                                            root.selectDevice(1)
                                            wheelAccumulator += threshold
                                        }
                                        while (wheelAccumulator >= threshold) {
                                            root.selectDevice(-1)
                                            wheelAccumulator -= threshold
                                        }
                                        event.accepted = true
                                    }
                                }

                                model: root.flattenedDevices

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property var dev: modelData.data
                                    readonly property bool isSelected: root.focusSection === "devices" && root.selectedDeviceIndex === index

                                    width: deviceList.width
                                    height: 32
                                    radius: 6
                                    color: (isSelected && !root.deviceActionFocused) ? Theme.selection : (dev.connected ? Theme.selection : Theme.surface)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        spacing: 6

                                        // Device Type Icon
                                        Text {
                                            text: Model.deviceIcon(dev)
                                            color: dev.connected ? Theme.green : (modelData.section === "discovered" ? Theme.cyan : Theme.blue)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 13
                                        }

                                        // Favorite Star
                                        Text {
                                            text: "★"
                                            color: Theme.yellow
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            visible: root.isFavorite(dev)
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        // Device Name
                                        Text {
                                            text: dev.name || dev.deviceName || dev.address
                                            color: dev.connected ? Theme.brand : Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 11
                                            font.bold: dev.connected
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        // Battery Percentage Pill Badge
                                        Rectangle {
                                            visible: dev.batteryAvailable && dev.battery > 0
                                            height: 18
                                            width: rowBatteryText.implicitWidth + 8
                                            radius: 4
                                            color: dev.battery < 0.2 
                                                ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.2)
                                                : (dev.battery < 0.4 
                                                    ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.2)
                                                    : Qt.rgba(Theme.brand.r, Theme.brand.g, Theme.brand.b, 0.2))
                                            border.color: dev.battery < 0.2 ? Theme.red : (dev.battery < 0.4 ? Theme.yellow : Theme.brand)
                                            border.width: 1
                                            Layout.alignment: Qt.AlignVCenter

                                            Text {
                                                id: rowBatteryText
                                                anchors.centerIn: parent
                                                text: Model.formatBattery(dev.battery)
                                                color: dev.battery < 0.2 ? Theme.red : (dev.battery < 0.4 ? Theme.yellow : Theme.brand)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                                font.bold: true
                                            }
                                        }

                                        // Forget / Unpair Button (For paired devices)
                                        Rectangle {
                                            width: 20
                                            height: 20
                                            radius: 4
                                            color: "transparent"
                                            visible: modelData.section === "known"
                                            border.color: isSelected && root.deviceActionFocused ? Theme.red : Theme.selection
                                            border.width: isSelected && root.deviceActionFocused ? 1.5 : 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰅙"
                                                color: isSelected && root.deviceActionFocused ? Theme.red : Theme.darkForeground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                hoverEnabled: true
                                                onEntered: { root.focusSection = "devices"; root.selectedDeviceIndex = index; root.deviceActionFocused = true }
                                                onClicked: root.forgetDevice(dev)
                                            }
                                        }

                                        // Connect / Disconnect Action Button
                                        Rectangle {
                                            width: 60
                                            height: 20
                                            radius: 4
                                            color: dev.connected ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25) : Theme.brand
                                            border.color: isSelected && root.deviceActionFocused && modelData.section !== "known" ? Theme.foreground : (dev.connected ? Theme.red : Theme.brand)
                                            border.width: isSelected && root.deviceActionFocused && modelData.section !== "known" ? 1.5 : 1

                                            Text {
                                                anchors.centerIn: parent
                                                text: dev.connected ? "Disconnect" : (modelData.section === "known" ? "Connect" : "Pair")
                                                color: dev.connected ? Theme.red : Theme.darkBackground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                                font.bold: true
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                hoverEnabled: true
                                                onEntered: { root.focusSection = "devices"; root.selectedDeviceIndex = index; root.deviceActionFocused = true }
                                                onClicked: {
                                                    if (dev.connected) {
                                                        root.disconnectDevice(dev)
                                                    } else {
                                                        root.connectDevice(dev)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Row Hover & Click Handler
                                    MouseArea {
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        onEntered: { root.focusSection = "devices"; root.selectedDeviceIndex = index; root.deviceActionFocused = false }
                                        onClicked: {
                                            if (dev.connected) {
                                                root.disconnectDevice(dev)
                                            } else {
                                                root.connectDevice(dev)
                                            }
                                        }
                                    }
                                }
                            }

                            // --- Rename Field (shown while renaming) ---
                            RowLayout {
                                id: renameRow
                                Layout.fillWidth: true
                                spacing: Theme.spacing
                                visible: root.renaming
                                opacity: root.renaming ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }

                                Text {
                                    text: "RENAME"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 22
                                    radius: 4
                                    color: Theme.surface
                                    border.color: Theme.accent
                                    border.width: 1

                                    TextInput {
                                        id: renameInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 6
                                        anchors.rightMargin: 6
                                        verticalAlignment: TextInput.AlignVCenter
                                        text: root.renameText
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 11
                                        selectByMouse: true
                                        onAccepted: root.commitRename()
                                        // onTextEdited rather than onTextChanged:
                                        // a change handler would fight the
                                        // binding to root.renameText.
                                        onTextEdited: root.renameText = text
                                    }
                                }

                                Text {
                                    text: "ENTER ✓   ESC ✗"
                                    color: Theme.darkForeground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            // --- Keybinding Legend (bluetui style) ---
                            //
                            // Two fixed rows rather than a flow: a flow's
                            // implicit height depends on its width, which
                            // is not known when the card measures itself,
                            // so the second row was clipped.
                            Item {
                                id: legend
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                visible: !root.renaming
                                opacity: root.renaming ? 0 : 0.75

                                Behavior on opacity {
                                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }

                                Row {
                                    id: legendRow1
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    spacing: 0

                                    Repeater {
                                        model: [
                                            { key: "s", label: "Scan on/off" },
                                            { key: "u", label: "Unpair" },
                                            { key: "↵", label: "Dis/Connect" },
                                            { key: "t", label: "Un/Trust" }
                                        ]

                                        delegate: Row {
                                            required property var modelData

                                            spacing: 4

                                            Text {
                                                text: modelData.key
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                text: modelData.label
                                                color: Theme.darkForeground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                text: "|"
                                                color: Theme.selection
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                rightPadding: 6
                                            }
                                        }
                                    }
                                }

                                Row {
                                    id: legendRow2
                                    anchors.top: legendRow1.bottom
                                    anchors.left: parent.left
                                    spacing: 0

                                    Repeater {
                                        model: [
                                            { key: "f", label: "Un/Favorite" },
                                            { key: "e", label: "Rename" },
                                            { key: "⇥", label: "Nav" }
                                        ]

                                        delegate: Row {
                                            required property var modelData

                                            spacing: 4

                                            Text {
                                                text: modelData.key
                                                color: Theme.accent
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                font.bold: true
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                text: modelData.label
                                                color: Theme.darkForeground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}