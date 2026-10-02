import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import "WifiModel.js" as Model

Scope {
    id: root

    property bool hudVisible: false
    property bool isExpanded: false
    readonly property bool hideAll: !hudVisible && !isExpanded
    property real lastToggleTime: 0
    property bool focusPrimed: false

    // Keyboard Navigation State
    property string focusSection: "wifi" // "header" | "dns" | "wifi"
    property int headerIndex: 2         // 0: QR, 1: Gauge, 2: Wi-Fi Switch
    property int dnsIndex: 0            // 0: DHCP, 1: Cloudflare, 2: Google
    property int selectedWifiIndex: 0
    property bool wifiActionFocused: false

    // Wi-Fi Connection Properties
    readonly property var wifiDevice: Networking.devices.values.find(
        dev => dev.type === DeviceType.Wifi
    )

    readonly property var connectedWifiDevice: Networking.devices.values.find(
        dev => dev.type === DeviceType.Wifi && dev.state === ConnectionState.Connected
    )

    readonly property var connectedNetwork: connectedWifiDevice ? connectedWifiDevice.networks.values.find(
        net => net.connected === true
    ) : null

    readonly property bool hasConnection: connectedNetwork !== undefined && connectedNetwork !== null
    readonly property real signalStrength: hasConnection && connectedNetwork.signalStrength !== undefined ? connectedNetwork.signalStrength : 0

    property bool weakSignal: hasConnection && signalStrength >= 0
    property bool mediumSignal: hasConnection && signalStrength >= 0.25
    property bool strongSignal: hasConnection && signalStrength >= 0.5
    property bool veryStrongSignal: hasConnection && signalStrength >= 0.75

    // Diagnostics & Throughput State
    property var info: ({})
    property real prevRxBytes: 0
    property real prevTxBytes: 0
    property real prevSampleTime: 0
    property string prevIface: ""
    property real downloadRate: 0
    property real uploadRate: 0
    property var routerPingSamples: []
    property var internetPingSamples: []
    property real internetPingLatency: -1
    property int internetPingPacketLoss: 0
    // No probe has come back yet. The formatters take this explicitly so the
    // grid reads "--" instead of contradicting itself with "Timeout" next to
    // "0%" on the first frame after the panel opens.
    readonly property bool hasPingSamples: internetPingSamples.length > 0

    // Wi-Fi Band State
    property string bandCurrent: ""
    property string bandSelected: "auto"
    property var bandAvailable: ["2.4", "5"]

    // DNS State
    property string activeDns: "DHCP"

    // Inline Password Entry
    property string activePasswordSsid: ""

    // The list used to be a live binding over the device's networks, so every
    // NetworkManager signal -- including a bare signal-strength tick -- produced
    // a brand new array. Reassigning ListView.model destroys and recreates every
    // delegate, which is what used to delete the focused password field
    // mid-typing along with the text in it. Rows are now rebuilt imperatively and
    // only when the *set* of rows actually changes.
    property var sortedNetworks: []
    readonly property string networkKey: {
        if (!wifiDevice || !wifiDevice.networks) return ""
        var values = wifiDevice.networks.values
        var parts = []
        for (var i = 0; i < values.length; i++) {
            var net = values[i]
            if (!net) continue
            // Deliberately excludes signal strength: a strength tick must not
            // change the identity of the list.
            parts.push((net.name || "") + "" + (net.connected ? 1 : 0) + "" + (net.known ? 1 : 0))
        }
        parts.sort()
        return parts.join("")
    }
    readonly property int networksCount: sortedNetworks.length

    function syncWifiNetworks() {
        if (!wifiDevice || !wifiDevice.networks) {
            if (sortedNetworks.length > 0) sortedNetworks = []
            return
        }
        sortedNetworks = Model.sortWifiRows(wifiDevice.networks.values.map(Model.wifiRow))
    }

    // Clamp the cursor whenever the list changes underneath it. Without this a
    // stale index matches no delegate at all, so the highlight disappears and
    // the next Up/Down computes from a row that is no longer there.
    function clampWifiCursor() {
        if (sortedNetworks.length === 0) {
            selectedWifiIndex = 0
            wifiActionFocused = false
            return
        }
        if (selectedWifiIndex >= sortedNetworks.length) selectedWifiIndex = sortedNetworks.length - 1
        if (selectedWifiIndex < 0) selectedWifiIndex = 0
    }

    Connections {
        target: root
        function onNetworkKeyChanged() { root.syncWifiNetworks() }
        // A new adapter can expose the same SSIDs as the one it replaced, which
        // leaves networkKey untouched while every row's networkObject is now
        // dead. Rebuild on the device swap as well.
        function onWifiDeviceChanged() { root.syncWifiNetworks() }
    }

    onSortedNetworksChanged: root.clampWifiCursor()

    Component.onCompleted: root.syncWifiNetworks()

    // Focus Priming Timer (Brief 75ms Exclusive focus so Hyprland transfers keyboard focus immediately)
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
            focusSection = networksCount > 0 ? "wifi" : "dns"
            selectedWifiIndex = 0
            wifiActionFocused = false
        } else {
            focusPrimeTimer.stop()
            focusPrimed = false
            root.stopStatus()
        }
    }

    onHideAllChanged: {
        if (hideAll) PopoutCoordinator.release("wifi")
    }

    Connections {
        target: PopoutCoordinator
        function onActiveChanged() {
            if (PopoutCoordinator.active !== "" && PopoutCoordinator.active !== "wifi") {
                root.isExpanded = false
                root.hudVisible = false
                root.activePasswordSsid = ""
            }
        }
    }

    // IPC Handler
    IpcHandler {
        target: "wifiBar"
        function toggle() {
            if (root.hideAll) {
                PopoutCoordinator.claim("wifi")
                root.hudVisible = true
                root.isExpanded = false
            } else if (root.hudVisible && !root.isExpanded) {
                PopoutCoordinator.claim("wifi")
                root.isExpanded = true
                root.hudVisible = false
                root.refreshStatus()
            } else {
                root.isExpanded = false
                root.hudVisible = false
                root.activePasswordSsid = ""
                PopoutCoordinator.release("wifi")
            }
        }
        function open() {
            PopoutCoordinator.claim("wifi")
            root.hudVisible = true
            root.isExpanded = false
        }
        function expand() {
            PopoutCoordinator.claim("wifi")
            root.isExpanded = true
            root.hudVisible = false
            root.refreshStatus()
        }
        function close() {
            root.isExpanded = false
            root.hudVisible = false
            root.activePasswordSsid = ""
            PopoutCoordinator.release("wifi")
        }
    }

    // Global Shortcut Handler
    GlobalShortcut {
        name: "wifiToggle"
        description: "Show Wi-Fi HUD on first press, expand Controller on second press"
        appid: "quickshell"
        onPressed: {
            var now = Date.now()
            if (now - root.lastToggleTime < 250) return
            root.lastToggleTime = now

            if (root.hideAll) {
                // 1st Press: Show micro HUD
                PopoutCoordinator.claim("wifi")
                root.hudVisible = true
                root.isExpanded = false
            } else if (root.hudVisible && !root.isExpanded) {
                // 2nd Press: Expand into full controller
                PopoutCoordinator.claim("wifi")
                root.isExpanded = true
                root.hudVisible = false
                root.refreshStatus()
            } else {
                // 3rd Press or while expanded: Close
                root.isExpanded = false
                root.hudVisible = false
                root.activePasswordSsid = ""
                PopoutCoordinator.release("wifi")
            }
        }
    }

    // Single entry point for kicking the two helper processes, mirroring the
    // stock panel's `if (!detailsProc.running)` guard. Assigning `running = true`
    // to an already-running Process is simply ignored, so a poller tick that
    // lands mid-poll is a no-op rather than a queued respawn -- verified by
    // measuring spawn cadence at 10/50/100ms ticks against a 400ms command, which
    // comes out at the command's duration either way. The guard makes that
    // "drop the tick" contract explicit instead of leaving it to be discovered.
    // The real cost of the old form was that a refresh press during an in-flight
    // poll vanished without a word.
    function refreshStatus() {
        if (!statusProcess.running) statusProcess.running = true
        if (!bandProcess.running) bandProcess.running = true
    }

    // Drop any in-flight poll when the panel closes, so a poll started just
    // before dismissal isn't left running against a panel nobody is looking at.
    function stopStatus() {
        statusProcess.running = false
        bandProcess.running = false
    }

    function revealWifiCursor() {
        if (root.networksCount <= 0 || typeof networkList === "undefined") return
        networkList.currentIndex = root.selectedWifiIndex
        if (networkList.contentHeight > networkList.height) {
            networkList.positionViewAtIndex(root.selectedWifiIndex, ListView.Contain)
        } else {
            networkList.contentY = 0
        }
    }

    function selectWifi(delta) {
        if (root.networksCount <= 0) return
        root.focusSection = "wifi"
        root.wifiActionFocused = false
        var next = root.selectedWifiIndex + delta
        if (next < 0) {
            next = Math.max(0, root.networksCount - 1)
        } else if (next >= root.networksCount) {
            next = 0
        }
        root.selectedWifiIndex = next
        root.revealWifiCursor()
    }

    // Auto-hide Timer for Glance HUD (only active when collapsed)
    Timer {
        id: autoHideTimer
        interval: 3000
        running: root.hudVisible && !root.isExpanded
        onTriggered: {
            root.hudVisible = false
        }
    }

    // Periodic status poller when expanded
    Timer {
        interval: 1500
        running: root.isExpanded
        repeat: true
        onTriggered: root.refreshStatus()
    }

    // Diagnostics Process (omarchy-network-status --verbose)
    Process {
        id: statusProcess
        running: false
        command: ["omarchy-network-status", "--verbose"]
        stdout: StdioCollector {
            onStreamFinished: {
                var next = Model.parseKeyValue(this.text)
                root.info = next
                var now = Date.now()

                var tp = Model.throughputState({
                    prevIface: root.prevIface,
                    prevRxBytes: root.prevRxBytes,
                    prevTxBytes: root.prevTxBytes,
                    prevSampleTime: root.prevSampleTime,
                    downloadRate: root.downloadRate,
                    uploadRate: root.uploadRate
                }, next, now)

                root.prevIface = tp.prevIface
                root.prevRxBytes = tp.prevRxBytes
                root.prevTxBytes = tp.prevTxBytes
                root.prevSampleTime = tp.prevSampleTime
                root.downloadRate = tp.downloadRate
                root.uploadRate = tp.uploadRate

                var pingState = Model.pingLatencyState({
                    pingIface: root.prevIface,
                    routerPingSamples: root.routerPingSamples,
                    internetPingSamples: root.internetPingSamples
                }, next, 20, 5)

                root.routerPingSamples = pingState.routerPingSamples
                root.internetPingSamples = pingState.internetPingSamples
                root.internetPingLatency = pingState.internetPingLatency
                root.internetPingPacketLoss = pingState.internetPingPacketLoss
            }
        }
    }

    // Wi-Fi Band Process
    Process {
        id: bandProcess
        running: false
        command: ["omarchy-network-band"]
        stdout: StdioCollector {
            onStreamFinished: {
                var res = Model.parseBandStatus(this.text)
                root.bandCurrent = res.band
                root.bandSelected = res.selected
                if (res.available.length > 0) root.bandAvailable = res.available
            }
        }
    }

    // Helper Actions
    function setWifiBand(band) {
        root.bandSelected = band
        var p = Qt.createQmlObject('import Quickshell.Io; Process { running: true; command: ["omarchy-network-band", "' + band + '"] }', root)
    }

    function setDnsProvider(provider) {
        root.activeDns = provider
        var p = Qt.createQmlObject('import Quickshell.Io; Process { running: true; command: ["omarchy-shell", "shell", "call", "omarchy.network", "setDns", "' + provider + '"] }', root)
    }

    function connectToNetwork(net) {
        if (!net) return
        if (!Model.isProtected(net.security, WifiSecurityType.Open) || net.known) {
            net.connect()
        } else {
            root.activePasswordSsid = net.name
        }
    }

    function activateHeader() {
        if (root.headerIndex === 0 && root.hasConnection) {
            Qt.createQmlObject('import Quickshell.Io; Process { running: true; command: ["omarchy-shell", "shell", "summon", "omarchy.wifiqr"] }', root)
        } else if (root.headerIndex === 1) {
            Qt.createQmlObject('import Quickshell.Io; Process { running: true; command: ["omarchy-shell", "shell", "summon", "omarchy.speedtest"] }', root)
        } else if (root.headerIndex === 2) {
            Networking.wifiEnabled = !Networking.wifiEnabled
        }
    }

    function activateDns() {
        var providers = ["DHCP", "Cloudflare", "Google"]
        if (root.dnsIndex >= 0 && root.dnsIndex < providers.length) {
            setDnsProvider(providers[root.dnsIndex])
        }
    }

    function activateSelectedWifi() {
        if (root.selectedWifiIndex >= 0 && root.selectedWifiIndex < root.networksCount) {
            var row = root.sortedNetworks[root.selectedWifiIndex]
            if (!row || !row.networkObject) return
            if (row.connected) {
                row.networkObject.disconnect()
            } else {
                connectToNetwork(row.networkObject)
            }
        }
    }

    // Multi-Monitor Twin Dismissal (Only for secondary monitors)
    Variants {
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

                WlrLayershell.namespace: "wifi-panel-twin-dismiss"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: {
                        root.isExpanded = false
                        root.hudVisible = false
                        root.activePasswordSsid = ""
                    }
                }
            }
        }
    }

    // Main Wi-Fi Bar & Controller Window
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

            WlrLayershell.namespace: "wifi-panel-main"
            WlrLayershell.layer: WlrLayer.Overlay
            // Exclusive prime for 75ms forces Hyprland to transfer focus immediately, then settles on OnDemand
            WlrLayershell.keyboardFocus: root.isExpanded
                ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
                : WlrKeyboardFocus.None

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
                    root.activePasswordSsid = ""
                }
            }

            // ================================================================
            // Layer 1: Focus Scope & Keyboard Navigation
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
                    // The password field takes active focus while it is open, so
                    // hand the keyboard back when it closes or arrow keys stop
                    // working until the panel is clicked again.
                    function onActivePasswordSsidChanged() {
                        if (root.activePasswordSsid === "" && root.isExpanded) {
                            Qt.callLater(function() {
                                focusScope.forceActiveFocus()
                            })
                        }
                    }
                }

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {

                    if (event.key === Qt.Key_Escape) {
                        root.isExpanded = false
                        root.hudVisible = false
                        root.activePasswordSsid = ""
                        event.accepted = true
                        return
                    }

                    // --- Arrow Down Navigation ---
                    if (event.key === Qt.Key_Down) {
                        if (root.focusSection === "header") {
                            root.focusSection = "dns"
                        } else if (root.focusSection === "dns") {
                            if (root.networksCount > 0) {
                                root.focusSection = "wifi"
                                if (root.selectedWifiIndex < 0) root.selectedWifiIndex = 0
                                root.wifiActionFocused = false
                                root.revealWifiCursor()
                            }
                        } else if (root.focusSection === "wifi") {
                            root.selectWifi(1)
                        }
                        event.accepted = true
                        return
                    }

                    // --- Arrow Up Navigation ---
                    if (event.key === Qt.Key_Up) {
                        if (root.focusSection === "wifi") {
                            // Up from the first row escapes to the DNS section
                            // rather than wrapping to the bottom of the list.
                            // The wrap used to make the options above the list
                            // unreachable without Tab, since selectWifi(-1)
                            // deliberately wraps within the list.
                            if (root.networksCount > 0 && root.selectedWifiIndex <= 0) {
                                root.focusSection = "dns"
                                root.wifiActionFocused = false
                            } else {
                                root.selectWifi(-1)
                            }
                        } else if (root.focusSection === "dns") {
                            root.focusSection = "header"
                        }
                        event.accepted = true
                        return
                    }

                    // --- Arrow Left Navigation ---
                    if (event.key === Qt.Key_Left) {
                        if (root.focusSection === "header") {
                            root.headerIndex = Math.max(0, root.headerIndex - 1)
                        } else if (root.focusSection === "dns") {
                            root.dnsIndex = Math.max(0, root.dnsIndex - 1)
                        } else if (root.focusSection === "wifi") {
                            root.wifiActionFocused = false
                        }
                        event.accepted = true
                        return
                    }

                    // --- Arrow Right Navigation ---
                    if (event.key === Qt.Key_Right) {
                        if (root.focusSection === "header") {
                            root.headerIndex = Math.min(2, root.headerIndex + 1)
                        } else if (root.focusSection === "dns") {
                            root.dnsIndex = Math.min(2, root.dnsIndex + 1)
                        } else if (root.focusSection === "wifi") {
                            root.wifiActionFocused = true
                        }
                        event.accepted = true
                        return
                    }

                    // --- Tab / Shift+Tab Navigation ---
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        var forward = event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)
                        if (forward) {
                            if (root.focusSection === "header") root.focusSection = "dns"
                            else if (root.focusSection === "dns") root.focusSection = "wifi"
                            else root.focusSection = "header"
                        } else {
                            if (root.focusSection === "wifi") root.focusSection = "dns"
                            else if (root.focusSection === "dns") root.focusSection = "header"
                            else root.focusSection = "wifi"
                        }
                        event.accepted = true
                        return
                    }

                    // --- Activation (Return / Enter / Space) ---
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        if (root.focusSection === "header") {
                            root.activateHeader()
                        } else if (root.focusSection === "dns") {
                            root.activateDns()
                        } else if (root.focusSection === "wifi") {
                            root.activateSelectedWifi()
                        }
                        event.accepted = true
                        return
                    }
                }

                // ============================================================
                // Pinned Right-Anchored Card Container
                // ============================================================
                Item {
                    id: cardContainer
                    x: root.hideAll ? (parent.width + 30) : (parent.width - width)
                    y: root.hideAll ? -(height + 30) : 0

                    width: (root.isExpanded ? 390 : Math.max(3 * Theme.rounding, wifiName.implicitWidth + Theme.rounding * 3)) + 4
                    height: (root.isExpanded ? Math.min(520, summaryHeader.height + detailsColumn.implicitHeight + Theme.rounding + Theme.spacing * 2) : (Theme.rounding * 3)) + 4

                    Behavior on width {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on height {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on x {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
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

                        // Swallow clicks inside card
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
                                        root.hudVisible = false
                                        root.refreshStatus()
                                    } else {
                                        root.hudVisible = false
                                        root.activePasswordSsid = ""
                                    }
                                }
                            }

                            // SSID Text
                            Text {
                                id: wifiName
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.topMargin: Theme.spacing
                                anchors.leftMargin: Theme.spacing
                                text: root.hasConnection && connectedNetwork.name ? connectedNetwork.name : "Wi-Fi"
                                color: root.hasConnection ? Theme.brand : Theme.darkForeground
                                font.family: Theme.brandFont
                                font.pixelSize: Theme.rounding
                                font.weight: Font.Bold
                            }

                            // Custom Wi-Fi Signal Bars (Nested Rounded Rectangles)
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                implicitWidth: Theme.spacing * 4.5
                                implicitHeight: implicitWidth
                                color: root.veryStrongSignal ? Theme.brand : Theme.brandBgc
                                radius: Theme.spacing
                                bottomLeftRadius: Theme.rounding + Theme.spacing
                                border.width: Theme.spacing / 2
                                border.color: Theme.bgc
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                implicitWidth: Theme.spacing * 3.5
                                implicitHeight: implicitWidth
                                color: root.strongSignal ? Theme.brand : Theme.brandBgc
                                radius: Theme.spacing
                                bottomLeftRadius: Theme.rounding + Theme.spacing
                                border.width: Theme.spacing / 2
                                border.color: Theme.bgc
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                implicitWidth: Theme.spacing * 2.5
                                implicitHeight: implicitWidth
                                color: root.mediumSignal ? Theme.brand : Theme.brandBgc
                                radius: Theme.spacing
                                bottomLeftRadius: Theme.rounding + Theme.spacing
                                border.width: Theme.spacing / 2
                                border.color: Theme.bgc
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                implicitWidth: Theme.spacing * 1.5
                                implicitHeight: implicitWidth
                                color: root.weakSignal ? Theme.brand : Theme.brandBgc
                                radius: Theme.spacing
                                bottomLeftRadius: Theme.rounding + Theme.spacing
                                border.width: Theme.spacing / 2
                                border.color: Theme.bgc
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
                                    text: root.hasConnection ? "CONNECTED" : (Networking.wifiEnabled ? "NOT CONNECTED" : "WI-FI DISABLED")
                                    color: root.hasConnection ? Theme.brand : (Networking.wifiEnabled ? Theme.yellow : Theme.red)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Spacer to push action buttons strictly to the right
                                Item {
                                    Layout.fillWidth: true
                                }

                                // Phosphor QR Code Button
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 6
                                    color: Theme.surface
                                    border.color: root.focusSection === "header" && root.headerIndex === 0 ? Theme.accent : Theme.selection
                                    border.width: root.focusSection === "header" && root.headerIndex === 0 ? 1.5 : 1
                                    visible: root.hasConnection

                                    Image {
                                        anchors.centerIn: parent
                                        source: "decorations/qr-code.svg"
                                        sourceSize.width: 14
                                        sourceSize.height: 14
                                        width: 14
                                        height: 14
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onEntered: { root.focusSection = "header"; root.headerIndex = 0 }
                                        onClicked: root.activateHeader()
                                    }
                                }

                                // Phosphor Gauge Speed Test Button
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 6
                                    color: Theme.surface
                                    border.color: root.focusSection === "header" && root.headerIndex === 1 ? Theme.accent : Theme.selection
                                    border.width: root.focusSection === "header" && root.headerIndex === 1 ? 1.5 : 1

                                    Image {
                                        anchors.centerIn: parent
                                        source: "decorations/gauge.svg"
                                        sourceSize.width: 14
                                        sourceSize.height: 14
                                        width: 14
                                        height: 14
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onEntered: { root.focusSection = "header"; root.headerIndex = 1 }
                                        onClicked: root.activateHeader()
                                    }
                                }

                                // Master Wi-Fi Power Switch
                                Rectangle {
                                    width: 40
                                    height: 22
                                    radius: 11
                                    color: Networking.wifiEnabled ? Theme.brand : Theme.selection
                                    border.color: root.focusSection === "header" && root.headerIndex === 2 ? Theme.foreground : (Networking.wifiEnabled ? Theme.brand : Theme.darkForeground)
                                    border.width: root.focusSection === "header" && root.headerIndex === 2 ? 1.5 : 1

                                    Rectangle {
                                        width: 16
                                        height: 16
                                        radius: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Networking.wifiEnabled ? parent.width - width - 3 : 3
                                        color: Networking.wifiEnabled ? Theme.darkBackground : Theme.lightForeground
                                        Behavior on x { NumberAnimation { duration: 150 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onEntered: { root.focusSection = "header"; root.headerIndex = 2 }
                                        onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                                    }
                                }
                            }

                            // --- Diagnostics Grid ---
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 4
                                rowSpacing: 4
                                columnSpacing: 10
                                visible: root.hasConnection

                                Text { text: "Ping:"; color: Theme.darkForeground; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                Text { text: Model.formatPingLatency(root.internetPingLatency, root.hasPingSamples); color: Theme.cyan; font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true }

                                Text { text: "Loss:"; color: Theme.darkForeground; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                Text { text: Model.formatPacketLoss(root.internetPingPacketLoss, root.hasPingSamples); color: root.internetPingPacketLoss > 0 ? Theme.red : Theme.lightForeground; font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true }

                                Text { text: "Down:"; color: Theme.darkForeground; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                Text { text: Model.formatRate(root.downloadRate); color: Theme.blue; font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true }

                                Text { text: "Up:"; color: Theme.darkForeground; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                Text { text: Model.formatRate(root.uploadRate); color: Theme.magenta; font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true }

                                Text { text: "IP:"; color: Theme.darkForeground; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                Text { text: root.info.ip || "--"; color: Theme.brightForeground; font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true }

                                Text { text: "Gateway:"; color: Theme.darkForeground; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                Text { text: root.info.gateway || "--"; color: Theme.lightForeground; font.family: Theme.fontFamily; font.pixelSize: 10 }
                            }

                            // --- DNS Selector ---
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "DNS:"
                                    color: Theme.darkForeground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Repeater {
                                    model: ["DHCP", "Cloudflare", "Google"]
                                    Rectangle {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        height: 22
                                        radius: 4
                                        color: root.activeDns === modelData ? Theme.brand : Theme.surface
                                        border.color: root.focusSection === "dns" && root.dnsIndex === index ? Theme.foreground : (root.activeDns === modelData ? Theme.brand : Theme.selection)
                                        border.width: root.focusSection === "dns" && root.dnsIndex === index ? 1.5 : 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: root.activeDns === modelData ? Theme.darkBackground : Theme.lightForeground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: root.activeDns === modelData
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onEntered: { root.focusSection = "dns"; root.dnsIndex = index }
                                            onClicked: root.setDnsProvider(modelData)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.selection
                            }

                            // --- Available Networks ---
                            Text {
                                text: "AVAILABLE NETWORKS"
                                color: Theme.darkForeground
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }

                            ListView {
                                id: networkList
                                currentIndex: root.selectedWifiIndex
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(Math.max(contentHeight, 35), 200)
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
                                            root.selectWifi(1)
                                            wheelAccumulator += threshold
                                        }
                                        while (wheelAccumulator >= threshold) {
                                            root.selectWifi(-1)
                                            wheelAccumulator -= threshold
                                        }
                                        event.accepted = true
                                    }
                                }

                                model: root.sortedNetworks

                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: networkList.width
                                    height: passwordBox.visible ? 68 : 30
                                    radius: 6
                                    color: (root.focusSection === "wifi" && root.selectedWifiIndex === index && !root.wifiActionFocused) ? Theme.selection : (modelData.connected ? Theme.selection : Theme.surface)

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: Model.wifiIconFor(modelData.signal)
                                                color: modelData.connected ? Theme.green : Theme.blue
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                            }

                                            Text {
                                                text: modelData.ssid || "Hidden Network"
                                                color: modelData.connected ? Theme.brand : Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 11
                                                font.bold: modelData.connected
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: Model.isProtected(modelData.security, WifiSecurityType.Open) ? "󰌾" : ""
                                                color: Theme.yellow
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 10
                                                visible: text !== ""
                                            }

                                            // Connect / Disconnect Action Button
                                            Rectangle {
                                                width: 60
                                                height: 20
                                                radius: 4
                                                color: modelData.connected ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25) : Theme.brand
                                                border.color: root.focusSection === "wifi" && root.selectedWifiIndex === index && root.wifiActionFocused ? Theme.foreground : (modelData.connected ? Theme.red : Theme.brand)
                                                border.width: root.focusSection === "wifi" && root.selectedWifiIndex === index && root.wifiActionFocused ? 1.5 : 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.connected ? "Disconnect" : (modelData.known ? "Connect" : "Join")
                                                    color: modelData.connected ? Theme.red : Theme.darkBackground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    hoverEnabled: true
                                                    onEntered: { root.focusSection = "wifi"; root.selectedWifiIndex = index; root.wifiActionFocused = true }
                                                    onClicked: {
                                                        if (modelData.connected) {
                                                             modelData.networkObject.disconnect()
                                                        } else {
                                                             root.connectToNetwork(modelData.networkObject)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Inline Password Input
                                        RowLayout {
                                            id: passwordBox
                                            Layout.fillWidth: true
                                            visible: root.activePasswordSsid === modelData.ssid
                                            spacing: 4

                                            Rectangle {
                                                Layout.fillWidth: true
                                                height: 22
                                                radius: 4
                                                color: Theme.darkBackground
                                                border.color: Theme.brand
                                                border.width: 1

                                                TextInput {
                                                    id: passwordInput
                                                    anchors.fill: parent
                                                    anchors.margins: 3
                                                    echoMode: TextInput.Password
                                                    color: Theme.brightForeground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 10
                                                    focus: passwordBox.visible
                                                    // The prompt is per-row and reuses the
                                                    // delegate, so a stale passphrase would
                                                    // still be sitting here from the last
                                                    // time this network was picked.
                                                    onVisibleChanged: if (visible) text = ""
                                                    // Escape belongs to the field that has
                                                    // focus: focusScope's Keys handler never
                                                    // sees it while this prompt is up, so
                                                    // without this the prompt is
                                                    // undismissable from the keyboard.
                                                    Keys.onEscapePressed: function(event) {
                                                        root.activePasswordSsid = ""
                                                        event.accepted = true
                                                    }
                                                    onAccepted: {
                                                        if (modelData.networkObject) {
                                                            modelData.networkObject.connectWithPsk(text)
                                                            root.activePasswordSsid = ""
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: 40
                                                height: 22
                                                radius: 4
                                                color: Theme.brand
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "OK"
                                                    color: Theme.darkBackground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.networkObject) {
                                                            // Read the field itself rather than a
                                                            // shared property, so a cancelled
                                                            // prompt can never leak its passphrase
                                                            // into the next network.
                                                            modelData.networkObject.connectWithPsk(passwordInput.text)
                                                            root.activePasswordSsid = ""
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: 40
                                                height: 22
                                                radius: 4
                                                color: Theme.selection
                                                border.color: Theme.darkForeground
                                                border.width: 1
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Cancel"
                                                    color: Theme.lightForeground
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.activePasswordSsid = ""
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        onEntered: { root.focusSection = "wifi"; root.selectedWifiIndex = index; root.wifiActionFocused = false }
                                        onClicked: {
                                            if (modelData.connected) {
                                                modelData.networkObject.disconnect()
                                            } else {
                                                root.connectToNetwork(modelData.networkObject)
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
