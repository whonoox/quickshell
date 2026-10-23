import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models
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
    readonly property var wifiDevice: (Networking.devices && Networking.devices.values) ? Networking.devices.values.find(
        dev => dev.type === DeviceType.Wifi
    ) : null

    property int networkStateVersion: 0

    readonly property var connectedWifiDevice: (wifiDevice && wifiDevice.connected) ? wifiDevice : null

    readonly property var connectedNetwork: {
        var _ = networkStateVersion
        if (!wifiDevice || !wifiDevice.connected || !wifiDevice.networks) return null
        var values = wifiDevice.networks.values
        for (var i = 0; i < values.length; i++) {
            var net = values[i]
            if (net && net.connected) return net
        }
        return null
    }

    readonly property bool hasConnection: connectedNetwork !== undefined && connectedNetwork !== null
    readonly property real signalStrength: hasConnection && connectedNetwork.signalStrength !== undefined ? connectedNetwork.signalStrength : 0

    property bool weakSignal: hasConnection && signalStrength >= 0
    property bool mediumSignal: hasConnection && signalStrength >= 0.25
    property bool strongSignal: hasConnection && signalStrength >= 0.5
    property bool veryStrongSignal: hasConnection && signalStrength >= 0.75

    // Connection State Tracking
    property string pendingConnectingSsid: ""
    property string pendingDisconnectingSsid: ""

    Timer {
        id: pendingTimeoutTimer
        interval: 15000
        onTriggered: {
            root.pendingConnectingSsid = ""
            root.pendingDisconnectingSsid = ""
        }
    }

    readonly property bool isConnecting: {
        var _ = networkStateVersion
        if (pendingConnectingSsid !== "") return true
        if (wifiDevice && wifiDevice.state === ConnectionState.Connecting) return true
        if (sortedNetworks) {
            for (var i = 0; i < sortedNetworks.length; i++) {
                var n = sortedNetworks[i]
                if (n && n.networkObject && n.networkObject.state === ConnectionState.Connecting) return true
            }
        }
        return false
    }

    readonly property bool isDisconnecting: {
        var _ = networkStateVersion
        if (pendingDisconnectingSsid !== "") return true
        if (wifiDevice && wifiDevice.state === ConnectionState.Disconnecting) return true
        if (sortedNetworks) {
            for (var i = 0; i < sortedNetworks.length; i++) {
                var n = sortedNetworks[i]
                if (n && n.networkObject && n.networkObject.state === ConnectionState.Disconnecting) return true
            }
        }
        return false
    }

    readonly property string connectingSsid: {
        var _ = networkStateVersion
        if (pendingConnectingSsid !== "") return pendingConnectingSsid
        if (sortedNetworks) {
            for (var i = 0; i < sortedNetworks.length; i++) {
                var n = sortedNetworks[i]
                if (n && n.networkObject && n.networkObject.state === ConnectionState.Connecting) {
                    return n.ssid || ""
                }
            }
        }
        return ""
    }

    readonly property string disconnectingSsid: {
        var _ = networkStateVersion
        if (pendingDisconnectingSsid !== "") return pendingDisconnectingSsid
        if (sortedNetworks) {
            for (var i = 0; i < sortedNetworks.length; i++) {
                var n = sortedNetworks[i]
                if (n && n.networkObject && n.networkObject.state === ConnectionState.Disconnecting) {
                    return n.ssid || ""
                }
            }
        }
        if (connectedNetwork && connectedNetwork.name) return connectedNetwork.name
        return ""
    }

    onIsConnectingChanged: {
        if (root.isConnecting) {
            root.revealGlance()
        }
    }

    onIsDisconnectingChanged: {
        if (root.isDisconnecting) {
            root.revealGlance()
        }
    }

    // Wi-Fi Signal Wave Animation Step Timers
    property int connectingStep: 0
    Timer {
        interval: 220
        running: root.isConnecting
        repeat: true
        onTriggered: root.connectingStep = (root.connectingStep + 1) % 4
    }

    property int disconnectingStep: 0
    Timer {
        interval: 220
        running: root.isDisconnecting
        repeat: true
        onTriggered: root.disconnectingStep = (root.disconnectingStep + 1) % 4
    }

    function barColor(barLevel) {
        if (root.isConnecting) {
            var lit = root.connectingStep >= (barLevel - 1)
            return lit ? Theme.yellow : Theme.brandBgc
        }
        if (root.isDisconnecting) {
            var lit = (3 - root.disconnectingStep) >= (barLevel - 1)
            return lit ? Theme.red : Theme.brandBgc
        }
        if (barLevel === 4) return root.veryStrongSignal ? Theme.brand : Theme.brandBgc
        if (barLevel === 3) return root.strongSignal ? Theme.brand : Theme.brandBgc
        if (barLevel === 2) return root.mediumSignal ? Theme.brand : Theme.brandBgc
        if (barLevel === 1) return root.weakSignal ? Theme.brand : Theme.brandBgc
        return Theme.brandBgc
    }

    // Connection Monitoring for Auto-Reveal on Connect
    readonly property string currentConnectionId: {
        var _ = networkStateVersion
        if (hasConnection && connectedNetwork && connectedNetwork.name) return connectedNetwork.name
        if (hasConnection) return "connected"
        if (sortedNetworks && sortedNetworks.length > 0 && sortedNetworks[0].connected) return sortedNetworks[0].ssid || "connected"
        return ""
    }
    property string prevConnectionId: ""
    property bool connectionWatchReady: false

    function revealGlance() {
        if (root.isExpanded) return
        PopoutCoordinator.claim("wifi")
        root.hudVisible = true
        autoHideTimer.restart()
    }

    Timer {
        id: connectionStartupTimer
        interval: 1500
        running: true
        onTriggered: {
            root.prevConnectionId = root.currentConnectionId
            root.connectionWatchReady = true
        }
    }

    onCurrentConnectionIdChanged: {
        if (!root.connectionWatchReady) return
        if (root.currentConnectionId !== "" && root.currentConnectionId !== root.prevConnectionId) {
            root.revealGlance()
        }
        root.prevConnectionId = root.currentConnectionId
    }

    Connections {
        target: root.wifiDevice || null
        enabled: !!root.wifiDevice
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            root.networkStateVersion++
            if (root.wifiDevice && root.wifiDevice.connected) {
                root.pendingConnectingSsid = ""
                root.pendingDisconnectingSsid = ""
                if (root.connectionWatchReady) root.revealGlance()
            }
        }
        function onStateChanged() {
            root.networkStateVersion++
            if (root.wifiDevice) {
                if (root.wifiDevice.state === ConnectionState.Connected) {
                    root.pendingConnectingSsid = ""
                    root.pendingDisconnectingSsid = ""
                    if (root.connectionWatchReady) root.revealGlance()
                } else if (root.wifiDevice.state === ConnectionState.Disconnected) {
                    root.pendingConnectingSsid = ""
                    root.pendingDisconnectingSsid = ""
                }
            }
        }
    }

    Instantiator {
        model: (root.wifiDevice && root.wifiDevice.networks) ? root.wifiDevice.networks.values : []
        delegate: Connections {
            target: modelData
            ignoreUnknownSignals: true
            function onConnectedChanged() {
                root.networkStateVersion++
                root.syncWifiNetworks()
                if (modelData && modelData.connected) {
                    root.pendingConnectingSsid = ""
                    root.pendingDisconnectingSsid = ""
                    if (root.connectionWatchReady) root.revealGlance()
                }
            }
            function onStateChanged() {
                root.networkStateVersion++
                root.syncWifiNetworks()
                if (modelData.state === ConnectionState.Connected || modelData.state === ConnectionState.Disconnected) {
                    if (root.pendingConnectingSsid === modelData.name) root.pendingConnectingSsid = ""
                    if (root.pendingDisconnectingSsid === modelData.name) root.pendingDisconnectingSsid = ""
                }
            }
        }
    }

    Connections {
        target: (root.wifiDevice && root.wifiDevice.networks) ? root.wifiDevice.networks : null
        enabled: !!(root.wifiDevice && root.wifiDevice.networks)
        ignoreUnknownSignals: true
        function onValuesChanged() {
            root.syncWifiNetworks()
        }
    }

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
    property string passwordText: ""
    property string passwordFocusItem: "input" // "input" | "ok" | "cancel"
    signal requestPasswordInputFocus()
    signal requestMainFocus()

    // The list used to be a live binding over the device's networks, so every
    // NetworkManager signal -- including a bare signal-strength tick -- produced
    // a brand new array. Reassigning ListView.model destroys and recreates every
    // delegate, which is what used to delete the focused password field
    // mid-typing along with the text in it. Rows are now rebuilt imperatively and
    // only when the *set* of rows actually changes.
    property var sortedNetworks: []
    readonly property string networkKey: {
        var _ = networkStateVersion
        if (!wifiDevice || !wifiDevice.networks) return ""
        var values = wifiDevice.networks.values
        var parts = []
        for (var i = 0; i < values.length; i++) {
            var net = values[i]
            if (!net) continue
            // Deliberately excludes signal strength: a strength tick must not
            // change the identity of the list. State is included so transitions
            // to connecting/disconnecting update row sorting and action buttons.
            parts.push((net.name || "") + " " + (net.connected ? 1 : 0) + " " + (net.known ? 1 : 0) + " " + (net.state !== undefined ? net.state : 0))
        }
        parts.sort()
        return parts.join(" ")
    }
    readonly property int networksCount: sortedNetworks.length
    readonly property bool hasKnownNetworks: sortedNetworks.length > 0 && (sortedNetworks[0].known || sortedNetworks[0].connected)
    readonly property bool hasOtherNetworks: sortedNetworks.length > 0 && !sortedNetworks[sortedNetworks.length - 1].known

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
        function onWifiDeviceChanged() {
            if (root.wifiDevice && root.isExpanded && Networking.wifiEnabled) {
                root.wifiDevice.scannerEnabled = true
            }
            root.syncWifiNetworks()
        }
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

    Timer {
        id: scanTimer
        interval: 12000
        repeat: true
        running: root.isExpanded && Networking.wifiEnabled
        onTriggered: {
            if (root.wifiDevice) root.wifiDevice.scannerEnabled = true
            Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"])
        }
    }

    Connections {
        target: Networking
        ignoreUnknownSignals: true
        function onWifiEnabledChanged() {
            if (root.wifiDevice && root.isExpanded) {
                root.wifiDevice.scannerEnabled = Networking.wifiEnabled
                if (Networking.wifiEnabled) {
                    Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"])
                }
            }
            root.syncWifiNetworks()
        }
    }

    function rescanWifi() {
        if (!Networking.wifiEnabled) {
            Networking.wifiEnabled = true
        }
        if (root.wifiDevice) root.wifiDevice.scannerEnabled = true
        Quickshell.execDetached(["nmcli", "device", "wifi", "rescan"])
        scanTimer.restart()
        root.syncWifiNetworks()
    }

    onIsExpandedChanged: {
        if (isExpanded) {
            focusPrimed = false
            focusPrimeTimer.restart()
            focusSection = networksCount > 0 ? "wifi" : "dns"
            selectedWifiIndex = 0
            wifiActionFocused = false
            root.rescanWifi()
        } else {
            focusPrimeTimer.stop()
            focusPrimed = false
            root.stopStatus()
            scanTimer.stop()
            if (wifiDevice) {
                wifiDevice.scannerEnabled = false
            }
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
            root.revealGlance()
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
        function rescan(): void {
            root.rescanWifi()
        }
        function scan(): void {
            root.rescanWifi()
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

    // Auto-hide Timer for Glance HUD (only active when collapsed and idle)
    Timer {
        id: autoHideTimer
        interval: 3500
        running: root.hudVisible && !root.isExpanded && !root.isConnecting && !root.isDisconnecting
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

    function wifiIndexForSsid(ssid) {
        if (!ssid || !root.sortedNetworks) return -1
        for (var i = 0; i < root.sortedNetworks.length; i++) {
            if (root.sortedNetworks[i] && root.sortedNetworks[i].ssid === ssid) return i
        }
        return -1
    }

    function openPasswordPrompt(ssid) {
        root.activePasswordSsid = ssid
        root.passwordText = ""
        root.passwordFocusItem = "input"
        var idx = root.wifiIndexForSsid(ssid)
        if (idx >= 0) {
            root.selectedWifiIndex = idx
            if (typeof networkList !== "undefined") {
                networkList.positionViewAtIndex(idx, ListView.Contain)
            }
        }
        root.requestPasswordInputFocus()
    }

    function submitPasswordPrompt() {
        if (!root.activePasswordSsid) return
        var idx = root.wifiIndexForSsid(root.activePasswordSsid)
        if (idx >= 0 && root.sortedNetworks[idx] && root.sortedNetworks[idx].networkObject) {
            var netObj = root.sortedNetworks[idx].networkObject
            root.pendingConnectingSsid = root.activePasswordSsid
            root.pendingDisconnectingSsid = ""
            pendingTimeoutTimer.restart()
            netObj.connectWithPsk(root.passwordText)
            root.activePasswordSsid = ""
            root.passwordText = ""
            root.passwordFocusItem = "input"
            root.requestMainFocus()
        }
    }

    function connectToNetwork(net) {
        if (!net) return
        var ssid = net.name || ""
        if (!Model.isProtected(net.security, WifiSecurityType.Open) || net.known) {
            root.pendingConnectingSsid = ssid
            root.pendingDisconnectingSsid = ""
            pendingTimeoutTimer.restart()
            net.connect()
        } else {
            root.openPasswordPrompt(ssid)
        }
    }

    function disconnectNetwork(net) {
        if (!net) return
        root.pendingDisconnectingSsid = net.name || (connectedNetwork ? connectedNetwork.name : "")
        root.pendingConnectingSsid = ""
        pendingTimeoutTimer.restart()
        net.disconnect()
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
            var isConnecting = (row.networkObject.state === ConnectionState.Connecting) || (root.pendingConnectingSsid === row.ssid)
            var isDisconnecting = (row.networkObject.state === ConnectionState.Disconnecting) || (root.pendingDisconnectingSsid === row.ssid)
            if (isConnecting || isDisconnecting) return

            if (row.connected) {
                disconnectNetwork(row.networkObject)
            } else {
                connectToNetwork(row.networkObject)
            }
        }
    }

    // Multi-Monitor Twin Dismissal (Only for secondary monitors)
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

                WlrLayershell.namespace: "wifi-panel-twin-dismiss"
                WlrLayershell.layer: WlrLayer.Top
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

            WlrLayershell.namespace: "wifi-panel-main"
            WlrLayershell.layer: WlrLayer.Top
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
                    function onRequestMainFocus() {
                        Qt.callLater(function() {
                            focusScope.forceActiveFocus()
                        })
                    }
                }

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {

                    if (event.key === Qt.Key_Escape) {
                        if (root.activePasswordSsid !== "") {
                            root.activePasswordSsid = ""
                            root.passwordText = ""
                            root.passwordFocusItem = "input"
                            event.accepted = true
                            return
                        }
                        root.isExpanded = false
                        root.hudVisible = false
                        root.activePasswordSsid = ""
                        event.accepted = true
                        return
                    }

                    // --- When inline password prompt is open ---
                    if (root.activePasswordSsid !== "") {
                        if (root.passwordFocusItem === "input") {
                            // Let printable keys and text editing pass through to TextInput
                            return
                        }

                        // When focus is on OK or Cancel buttons:
                        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            var fwd = event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)
                            if (fwd) {
                                if (root.passwordFocusItem === "ok") {
                                    root.passwordFocusItem = "cancel"
                                } else if (root.passwordFocusItem === "cancel") {
                                    // Tab out of the prompt to the next section (header)
                                    root.passwordFocusItem = "input"
                                    root.focusSection = "header"
                                    root.headerIndex = 0
                                }
                            } else {
                                if (root.passwordFocusItem === "cancel") {
                                    root.passwordFocusItem = "ok"
                                } else if (root.passwordFocusItem === "ok") {
                                    root.passwordFocusItem = "input"
                                    root.requestPasswordInputFocus()
                                }
                            }
                            event.accepted = true
                            return
                        }

                        if (event.key === Qt.Key_Right) {
                            if (root.passwordFocusItem === "ok") {
                                root.passwordFocusItem = "cancel"
                                event.accepted = true
                                return
                            }
                        }
                        if (event.key === Qt.Key_Left) {
                            if (root.passwordFocusItem === "cancel") {
                                root.passwordFocusItem = "ok"
                                event.accepted = true
                                return
                            } else if (root.passwordFocusItem === "ok") {
                                root.passwordFocusItem = "input"
                                root.requestPasswordInputFocus()
                                event.accepted = true
                                return
                            }
                        }

                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            if (root.passwordFocusItem === "ok") {
                                root.submitPasswordPrompt()
                            } else if (root.passwordFocusItem === "cancel") {
                                root.activePasswordSsid = ""
                                root.passwordText = ""
                                root.passwordFocusItem = "input"
                            }
                            event.accepted = true
                            return
                        }

                        if (event.key === Qt.Key_Down) {
                            root.activePasswordSsid = ""
                            root.passwordText = ""
                            root.passwordFocusItem = "input"
                            root.focusSection = "wifi"
                            root.selectWifi(1)
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Up) {
                            root.activePasswordSsid = ""
                            root.passwordText = ""
                            root.passwordFocusItem = "input"
                            root.focusSection = "wifi"
                            if (root.selectedWifiIndex <= 0) {
                                root.focusSection = "dns"
                                root.wifiActionFocused = false
                            } else {
                                root.selectWifi(-1)
                            }
                            event.accepted = true
                            return
                        }

                        event.accepted = true
                        return
                    }

                    // --- Rescan Wi-Fi ('s' / 'S') ---
                    if (event.key === Qt.Key_S || event.key === Qt.Key_s || event.text.toLowerCase() === "s") {
                        if (root.activePasswordSsid === "") {
                            root.rescanWifi()
                            event.accepted = true
                            return
                        }
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
                            else if (root.focusSection === "dns") {
                                root.focusSection = "wifi"
                                if (root.activePasswordSsid !== "") {
                                    root.passwordFocusItem = "input"
                                    root.requestPasswordInputFocus()
                                }
                            }
                            else root.focusSection = "header"
                        } else {
                            if (root.focusSection === "wifi") root.focusSection = "dns"
                            else if (root.focusSection === "dns") root.focusSection = "header"
                            else {
                                root.focusSection = "wifi"
                                if (root.activePasswordSsid !== "") {
                                    root.passwordFocusItem = "input"
                                    root.requestPasswordInputFocus()
                                }
                            }
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
                    anchors.right: parent.right
                    y: root.hideAll ? -(height + 30) : 0

                    width: (root.isExpanded ? 390 : Math.max(3 * Theme.rounding, wifiName.implicitWidth + Theme.rounding * 3)) + 4
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
                                text: {
                                    if (root.isConnecting) {
                                        var isNew = false
                                        if (root.sortedNetworks && root.connectingSsid) {
                                            for (var i = 0; i < root.sortedNetworks.length; i++) {
                                                if (root.sortedNetworks[i] && root.sortedNetworks[i].ssid === root.connectingSsid) {
                                                    isNew = !root.sortedNetworks[i].known
                                                    break
                                                }
                                            }
                                        }
                                        var prefix = isNew ? "JOINING: " : "CONNECTING: "
                                        return root.connectingSsid ? (prefix + root.connectingSsid) : (isNew ? "JOINING..." : "CONNECTING...")
                                    }
                                    if (root.isDisconnecting) {
                                        return root.disconnectingSsid ? ("DISCONNECTING: " + root.disconnectingSsid) : "DISCONNECTING..."
                                    }
                                    if (root.hasConnection && connectedNetwork && connectedNetwork.name) {
                                        return connectedNetwork.name
                                    }
                                    return Networking.wifiEnabled ? "Wi-Fi" : "Wi-Fi Off"
                                }
                                color: {
                                    if (root.isConnecting) return Theme.yellow
                                    if (root.isDisconnecting) return Theme.red
                                    if (root.hasConnection) return Theme.brand
                                    return Theme.darkForeground
                                }
                                font.family: Theme.brandFont
                                font.pixelSize: Theme.rounding
                                font.weight: Font.Bold
                                font.capitalization: Font.AllUppercase
                            }

                            // Custom Wi-Fi Signal Bars (Nested Rounded Rectangles)
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                implicitWidth: Theme.spacing * 4.5
                                implicitHeight: implicitWidth
                                color: root.barColor(4)
                                radius: Theme.spacing
                                bottomLeftRadius: Theme.rounding + Theme.spacing
                                border.width: Theme.spacing / 2
                                border.color: Theme.bgc
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                implicitWidth: Theme.spacing * 3.5
                                implicitHeight: implicitWidth
                                color: root.barColor(3)
                                radius: Theme.spacing
                                bottomLeftRadius: Theme.rounding + Theme.spacing
                                border.width: Theme.spacing / 2
                                border.color: Theme.bgc
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                implicitWidth: Theme.spacing * 2.5
                                implicitHeight: implicitWidth
                                color: root.barColor(2)
                                radius: Theme.spacing
                                bottomLeftRadius: Theme.rounding + Theme.spacing
                                border.width: Theme.spacing / 2
                                border.color: Theme.bgc
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                implicitWidth: Theme.spacing * 1.5
                                implicitHeight: implicitWidth
                                color: root.barColor(1)
                                radius: Theme.spacing
                                bottomLeftRadius: Theme.rounding + Theme.spacing
                                border.width: Theme.spacing / 2
                                border.color: Theme.bgc
                                Behavior on color { ColorAnimation { duration: 150 } }
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

                                RowLayout {
                                    spacing: 6
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: root.isConnecting
                                            ? Theme.yellow
                                            : (root.isDisconnecting
                                                ? Theme.red
                                                : (root.hasConnection
                                                    ? Theme.green
                                                    : (Networking.wifiEnabled ? Theme.yellow : Theme.red)))
                                        Layout.alignment: Qt.AlignVCenter

                                        SequentialAnimation on opacity {
                                            running: root.isConnecting || root.isDisconnecting
                                            loops: Animation.Infinite
                                            NumberAnimation { from: 1.0; to: 0.25; duration: 450; easing.type: Easing.InOutQuad }
                                            NumberAnimation { from: 0.25; to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
                                        }
                                    }

                                    Text {
                                        text: {
                                            if (root.isConnecting) {
                                                return root.connectingSsid ? ("CONNECTING TO " + root.connectingSsid.toUpperCase() + "...") : "CONNECTING..."
                                            }
                                            if (root.isDisconnecting) {
                                                return root.disconnectingSsid ? ("DISCONNECTING " + root.disconnectingSsid.toUpperCase() + "...") : "DISCONNECTING..."
                                            }
                                            if (root.hasConnection) return "CONNECTED"
                                            return Networking.wifiEnabled ? "NOT CONNECTED" : "WI-FI DISABLED"
                                        }
                                        color: {
                                            if (root.isConnecting) return Theme.yellow
                                            if (root.isDisconnecting) return Theme.red
                                            if (root.hasConnection) return Theme.brand
                                            return Networking.wifiEnabled ? Theme.yellow : Theme.red
                                        }
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.bold: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }
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
                                text: (root.hasKnownNetworks && root.hasOtherNetworks) ? "KNOWN NETWORKS" : "AVAILABLE NETWORKS"
                                color: Theme.darkForeground
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                            }

                            ListView {
                                id: networkList
                                currentIndex: root.selectedWifiIndex
                                onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(Math.max(contentHeight, 35), 240)
                                implicitHeight: Layout.preferredHeight
                                Layout.fillHeight: false
                                clip: true
                                spacing: 4
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: contentHeight > height

                                ScrollBar.vertical: ScrollBar {
                                    policy: networkList.contentHeight > networkList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                }

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

                                delegate: Item {
                                    id: delegateRoot
                                    required property var modelData
                                    required property int index

                                    readonly property bool isFirstOther: !modelData.known && index > 0 && root.sortedNetworks[index - 1] && (root.sortedNetworks[index - 1].known || root.sortedNetworks[index - 1].connected)

                                    readonly property bool isItemConnecting: {
                                        var _ = root.networkStateVersion
                                        if (delegateRoot.modelData.networkObject && delegateRoot.modelData.networkObject.state === ConnectionState.Connecting) return true
                                        if (root.pendingConnectingSsid !== "" && root.pendingConnectingSsid === delegateRoot.modelData.ssid) return true
                                        return false
                                    }

                                    readonly property bool isItemDisconnecting: {
                                        var _ = root.networkStateVersion
                                        if (delegateRoot.modelData.networkObject && delegateRoot.modelData.networkObject.state === ConnectionState.Disconnecting) return true
                                        if (root.pendingDisconnectingSsid !== "" && root.pendingDisconnectingSsid === delegateRoot.modelData.ssid) return true
                                        return false
                                    }

                                    width: networkList.width
                                    height: delegateColumn.implicitHeight

                                    Connections {
                                        target: delegateRoot.modelData.networkObject || null
                                        ignoreUnknownSignals: true
                                        function onConnectedChanged() {
                                            if (delegateRoot.modelData.networkObject && delegateRoot.modelData.networkObject.connected) {
                                                if (root.pendingConnectingSsid === delegateRoot.modelData.ssid) {
                                                    root.pendingConnectingSsid = ""
                                                }
                                            }
                                        }
                                        function onConnectionFailed(reason) {
                                            if (root.pendingConnectingSsid === delegateRoot.modelData.ssid) {
                                                root.pendingConnectingSsid = ""
                                                root.openPasswordPrompt(delegateRoot.modelData.ssid)
                                            }
                                        }
                                    }

                                    Column {
                                        id: delegateColumn
                                        width: parent.width
                                        spacing: 4

                                        // Separator matching OmarchyMenu
                                        Item {
                                            width: parent.width
                                            height: delegateRoot.isFirstOther ? 12 : 0
                                            visible: delegateRoot.isFirstOther

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

                                        // Section header for other networks
                                        Text {
                                            width: parent.width
                                            visible: delegateRoot.isFirstOther
                                            text: "OTHER NETWORKS"
                                            color: Theme.darkForeground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        Rectangle {
                                            id: rowCard
                                            width: parent.width
                                            height: passwordBox.visible ? 60 : 30
                                            radius: 6
                                            color: (root.focusSection === "wifi" && root.selectedWifiIndex === delegateRoot.index && !root.wifiActionFocused) ? Theme.selection : (delegateRoot.modelData.connected ? Theme.selection : Theme.surface)

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 5
                                                spacing: 4

                                                Item {
                                                    Layout.fillWidth: true
                                                    height: 20

                                                    Text {
                                                        id: signalIcon
                                                        text: Model.wifiIconFor(delegateRoot.modelData.signal)
                                                        color: delegateRoot.isItemConnecting ? Theme.yellow : (delegateRoot.isItemDisconnecting ? Theme.red : (delegateRoot.modelData.connected ? Theme.green : Theme.blue))
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 12
                                                        anchors.left: parent.left
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }

                                                    // Connect / Disconnect Action Button
                                                    Rectangle {
                                                        id: actionBtn
                                                        width: delegateRoot.isItemConnecting ? (delegateRoot.modelData.known ? 76 : 64) : (delegateRoot.isItemDisconnecting ? 82 : (delegateRoot.modelData.connected ? 64 : 56))
                                                        height: 20
                                                        radius: 4
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: delegateRoot.isItemConnecting
                                                            ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.25)
                                                            : (delegateRoot.isItemDisconnecting
                                                                ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25)
                                                                : (delegateRoot.modelData.connected
                                                                    ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25)
                                                                    : Theme.brand))
                                                        border.color: root.focusSection === "wifi" && root.selectedWifiIndex === delegateRoot.index && root.wifiActionFocused
                                                            ? Theme.foreground
                                                            : (delegateRoot.isItemConnecting
                                                                ? Theme.yellow
                                                                : (delegateRoot.isItemDisconnecting || delegateRoot.modelData.connected
                                                                    ? Theme.red
                                                                    : Theme.brand))
                                                        border.width: root.focusSection === "wifi" && root.selectedWifiIndex === delegateRoot.index && root.wifiActionFocused ? 1.5 : 1

                                                        Behavior on width {
                                                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                                        }

                                                        SequentialAnimation on opacity {
                                                            running: delegateRoot.isItemConnecting || delegateRoot.isItemDisconnecting
                                                            loops: Animation.Infinite
                                                            NumberAnimation { from: 1.0; to: 0.35; duration: 450; easing.type: Easing.InOutQuad }
                                                            NumberAnimation { from: 0.35; to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: delegateRoot.isItemConnecting
                                                                ? (delegateRoot.modelData.known ? "Connecting" : "Joining")
                                                                : (delegateRoot.isItemDisconnecting
                                                                    ? "Disconnecting"
                                                                    : (delegateRoot.modelData.connected
                                                                        ? "Disconnect"
                                                                        : (delegateRoot.modelData.known ? "Connect" : "Join")))
                                                            color: delegateRoot.isItemConnecting
                                                                ? Theme.yellow
                                                                : (delegateRoot.isItemDisconnecting || delegateRoot.modelData.connected
                                                                    ? Theme.red
                                                                    : Theme.darkBackground)
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 9
                                                            font.bold: true
                                                        }

                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: (delegateRoot.isItemConnecting || delegateRoot.isItemDisconnecting) ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                            enabled: !delegateRoot.isItemConnecting && !delegateRoot.isItemDisconnecting
                                                            hoverEnabled: true
                                                            onEntered: { root.focusSection = "wifi"; root.selectedWifiIndex = delegateRoot.index; root.wifiActionFocused = true }
                                                            onClicked: {
                                                                root.selectedWifiIndex = delegateRoot.index
                                                                root.wifiActionFocused = true
                                                                if (delegateRoot.modelData.connected) {
                                                                    root.disconnectNetwork(delegateRoot.modelData.networkObject)
                                                                } else {
                                                                    root.connectToNetwork(delegateRoot.modelData.networkObject)
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        id: lockIcon
                                                        text: Model.isProtected(delegateRoot.modelData.security, WifiSecurityType.Open) ? "󰌾" : ""
                                                        color: Theme.yellow
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 10
                                                        visible: text !== ""
                                                        anchors.right: actionBtn.left
                                                        anchors.rightMargin: 6
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }

                                                    Text {
                                                        id: ssidText
                                                        text: delegateRoot.modelData.ssid || "Hidden Network"
                                                        color: delegateRoot.isItemConnecting ? Theme.yellow : (delegateRoot.isItemDisconnecting ? Theme.red : (delegateRoot.modelData.connected ? Theme.brand : Theme.foreground))
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 11
                                                        font.bold: delegateRoot.modelData.connected || delegateRoot.isItemConnecting
                                                        elide: Text.ElideRight
                                                        anchors.left: signalIcon.right
                                                        anchors.leftMargin: 6
                                                        anchors.right: lockIcon.visible ? lockIcon.left : actionBtn.left
                                                        anchors.rightMargin: 6
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }

                                                // Inline Password Input
                                                RowLayout {
                                                    id: passwordBox
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 22
                                                    visible: root.activePasswordSsid !== "" && root.activePasswordSsid === (delegateRoot.modelData.ssid || "")
                                                    spacing: 4

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        height: 22
                                                        radius: 4
                                                        color: Theme.darkBackground
                                                        border.color: (root.activePasswordSsid === delegateRoot.modelData.ssid && root.passwordFocusItem === "input") ? Theme.brand : Theme.selection
                                                        border.width: (root.activePasswordSsid === delegateRoot.modelData.ssid && root.passwordFocusItem === "input") ? 1.5 : 1

                                                        TextInput {
                                                            id: passwordInput
                                                            anchors.fill: parent
                                                            anchors.margins: 3
                                                            echoMode: TextInput.Password
                                                            color: Theme.brightForeground
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 10
                                                            focus: passwordBox.visible && root.passwordFocusItem === "input"
                                                            text: (root.activePasswordSsid === (delegateRoot.modelData.ssid || "")) ? root.passwordText : ""
                                                            onTextChanged: {
                                                                if (root.activePasswordSsid === (delegateRoot.modelData.ssid || "") && root.passwordText !== text) {
                                                                    root.passwordText = text
                                                                }
                                                            }
                                                            onActiveFocusChanged: {
                                                                if (activeFocus && root.activePasswordSsid === (delegateRoot.modelData.ssid || "")) {
                                                                    root.passwordFocusItem = "input"
                                                                }
                                                            }

                                                            Connections {
                                                                target: root
                                                                function onRequestPasswordInputFocus() {
                                                                    if (root.activePasswordSsid === (delegateRoot.modelData.ssid || "")) {
                                                                        passwordInput.forceActiveFocus()
                                                                    }
                                                                }
                                                            }

                                                            onVisibleChanged: {
                                                                if (visible) {
                                                                    text = ""
                                                                    Qt.callLater(function() {
                                                                        passwordInput.forceActiveFocus()
                                                                    })
                                                                }
                                                            }
                                                            Component.onCompleted: {
                                                                if (visible) {
                                                                    Qt.callLater(function() {
                                                                        passwordInput.forceActiveFocus()
                                                                    })
                                                                }
                                                            }

                                                            Keys.onPressed: function(event) {
                                                                if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                                                                    root.passwordFocusItem = "ok"
                                                                    root.requestMainFocus()
                                                                    event.accepted = true
                                                                    return
                                                                }
                                                                if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                                                                    root.focusSection = "dns"
                                                                    root.passwordFocusItem = "input"
                                                                    root.requestMainFocus()
                                                                    event.accepted = true
                                                                    return
                                                                }
                                                                if (event.key === Qt.Key_Escape) {
                                                                    root.activePasswordSsid = ""
                                                                    root.passwordText = ""
                                                                    root.passwordFocusItem = "input"
                                                                    root.requestMainFocus()
                                                                    event.accepted = true
                                                                    return
                                                                }
                                                                if (event.key === Qt.Key_Down) {
                                                                    root.activePasswordSsid = ""
                                                                    root.passwordText = ""
                                                                    root.passwordFocusItem = "input"
                                                                    root.focusSection = "wifi"
                                                                    root.selectWifi(1)
                                                                    root.requestMainFocus()
                                                                    event.accepted = true
                                                                    return
                                                                }
                                                                if (event.key === Qt.Key_Up) {
                                                                    root.activePasswordSsid = ""
                                                                    root.passwordText = ""
                                                                    root.passwordFocusItem = "input"
                                                                    root.focusSection = "wifi"
                                                                    if (root.selectedWifiIndex <= 0) {
                                                                        root.focusSection = "dns"
                                                                        root.wifiActionFocused = false
                                                                    } else {
                                                                        root.selectWifi(-1)
                                                                    }
                                                                    root.requestMainFocus()
                                                                    event.accepted = true
                                                                    return
                                                                }
                                                            }

                                                            onAccepted: {
                                                                root.submitPasswordPrompt()
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        id: okBtn
                                                        width: 40
                                                        height: 22
                                                        radius: 4
                                                        color: Theme.brand
                                                        border.color: (root.activePasswordSsid === delegateRoot.modelData.ssid && root.passwordFocusItem === "ok") ? Theme.foreground : Theme.brand
                                                        border.width: (root.activePasswordSsid === delegateRoot.modelData.ssid && root.passwordFocusItem === "ok") ? 1.5 : 1

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
                                                            onEntered: { root.focusSection = "wifi"; root.selectedWifiIndex = delegateRoot.index; root.passwordFocusItem = "ok" }
                                                            onClicked: {
                                                                root.submitPasswordPrompt()
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        id: cancelBtn
                                                        width: 40
                                                        height: 22
                                                        radius: 4
                                                        color: Theme.selection
                                                        border.color: (root.activePasswordSsid === delegateRoot.modelData.ssid && root.passwordFocusItem === "cancel") ? Theme.foreground : Theme.darkForeground
                                                        border.width: (root.activePasswordSsid === delegateRoot.modelData.ssid && root.passwordFocusItem === "cancel") ? 1.5 : 1

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
                                                            onEntered: { root.focusSection = "wifi"; root.selectedWifiIndex = delegateRoot.index; root.passwordFocusItem = "cancel" }
                                                            onClicked: {
                                                                root.activePasswordSsid = ""
                                                                root.passwordText = ""
                                                                root.passwordFocusItem = "input"
                                                                root.requestMainFocus()
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                z: -1
                                                hoverEnabled: true
                                                onEntered: { root.focusSection = "wifi"; root.selectedWifiIndex = delegateRoot.index; root.wifiActionFocused = false }
                                                onClicked: {
                                                    root.selectedWifiIndex = delegateRoot.index
                                                    root.wifiActionFocused = false
                                                    if (delegateRoot.modelData.connected) {
                                                        root.disconnectNetwork(delegateRoot.modelData.networkObject)
                                                    } else {
                                                        root.connectToNetwork(delegateRoot.modelData.networkObject)
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
    }
}
