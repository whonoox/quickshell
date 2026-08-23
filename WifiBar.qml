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

    // Wi-Fi Band State
    property string bandCurrent: ""
    property string bandSelected: "auto"
    property var bandAvailable: ["2.4", "5"]

    // DNS State
    property string activeDns: "DHCP"

    // Inline Password Entry
    property string activePasswordSsid: ""
    property string enteredPassword: ""

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
        } else {
            focusPrimeTimer.stop()
            focusPrimed = false
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
                root.hudVisible = true
                root.isExpanded = false
            } else if (root.hudVisible && !root.isExpanded) {
                // 2nd Press: Expand into full controller
                root.isExpanded = true
                root.hudVisible = false
                statusProcess.running = true
                bandProcess.running = true
            } else {
                // 3rd Press or while expanded: Close
                root.isExpanded = false
                root.hudVisible = false
                root.activePasswordSsid = ""
            }
        }
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
        onTriggered: statusProcess.running = true
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
        if (net.security === "open" || net.security === 0) {
            net.connect()
        } else if (net.known) {
            net.connect()
        } else {
            root.activePasswordSsid = net.name
            root.enteredPassword = ""
        }
    }

    // ========================================================================
    // Full-Screen Click Dismissal Layer (Mapped ONLY when expanded)
    // ========================================================================
    Variants {
        model: root.isExpanded ? Quickshell.screens : []

        delegate: Component {
            PanelWindow {
                required property var modelData
                screen: modelData

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                color: "transparent"
                exclusionMode: ExclusionMode.Ignore

                WlrLayershell.namespace: "wifi-panel-dismiss"
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

    // ========================================================================
    // Main Wi-Fi Bar & Expanding Controller Window
    // ========================================================================
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            anchors.right: true
            anchors.top: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "wifi-panel-main"
            WlrLayershell.layer: WlrLayer.Overlay
            // Exclusive prime for 75ms forces Hyprland to transfer focus immediately, then settles on OnDemand
            WlrLayershell.keyboardFocus: root.isExpanded
                ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
                : WlrKeyboardFocus.None

            implicitWidth: 420
            implicitHeight: 560

            // Diagonal corner slide
            margins.top: root.hideAll ? (root.isExpanded ? -560 : -(Theme.rounding * 2.5 + 20)) : 0
            margins.right: root.hideAll ? (root.isExpanded ? -420 : -(wifiName.implicitWidth + Theme.rounding * 4)) : 0

            Behavior on margins.top {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on margins.right {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

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
                }

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root.isExpanded = false
                        root.hudVisible = false
                        root.activePasswordSsid = ""
                        event.accepted = true
                    }
                }

                // ============================================================
                // Pinned Right-Anchored Card Container
                // Fits dynamically to children with full bottom padding & max height cap
                // ============================================================
                Item {
                    id: cardContainer
                    anchors.right: parent.right
                    anchors.top: parent.top

                    width: root.isExpanded ? 390 : (wifiName.implicitWidth + Theme.rounding * 3)
                    height: root.isExpanded ? Math.min(520, summaryHeader.height + detailsColumn.implicitHeight + Theme.rounding + Theme.spacing * 2) : (Theme.rounding * 2.5)

                    Behavior on width {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on height {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    // Top-left Scoop (Glides smoothly along left edge)
                    ScoopShape {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        cornerPosition: scoopPosition.bottomLeft
                    }

                    // Bottom-right Scoop (Anchored to bottom-right)
                    ScoopShape {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        cornerPosition: scoopPosition.bottomLeft
                    }

                    // Main Background Container
                    Rectangle {
                        id: background
                        anchors.fill: parent
                        anchors.leftMargin: Theme.rounding
                        anchors.bottomMargin: Theme.rounding
                        color: Theme.bgc
                        bottomLeftRadius: Theme.rounding
                        clip: true

                        // Swallow clicks on card so they don't trigger outside dismissal
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
                            height: Theme.rounding * 2.5 - Theme.rounding

                            // Click header to toggle expansion
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.isExpanded = !root.isExpanded
                                    if (root.isExpanded) {
                                        root.hudVisible = false
                                        statusProcess.running = true
                                        bandProcess.running = true
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
                                font.family: "Nuuxfont"
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
                                    border.color: Theme.selection
                                    border.width: 1
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
                                        onClicked: {
                                            var p = Qt.createQmlObject('import Quickshell.Io; Process { running: true; command: ["omarchy-shell", "shell", "summon", "omarchy.wifiqr"] }', root)
                                        }
                                    }
                                }

                                // Phosphor Gauge Speed Test Button
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 6
                                    color: Theme.surface
                                    border.color: Theme.selection
                                    border.width: 1

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
                                        onClicked: {
                                            var p = Qt.createQmlObject('import Quickshell.Io; Process { running: true; command: ["omarchy-shell", "shell", "summon", "omarchy.speedtest"] }', root)
                                        }
                                    }
                                }

                                // Master Wi-Fi Power Switch
                                Rectangle {
                                    width: 40
                                    height: 22
                                    radius: 11
                                    color: Networking.wifiEnabled ? Theme.brand : Theme.selection
                                    border.color: Networking.wifiEnabled ? Theme.brand : Theme.darkForeground
                                    border.width: 1

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

                                Text { text: "Ping:"; color: Theme.darkForeground; font.pixelSize: 10 }
                                Text { text: Model.formatPingLatency(root.internetPingLatency, true); color: Theme.cyan; font.pixelSize: 10; font.bold: true }

                                Text { text: "Loss:"; color: Theme.darkForeground; font.pixelSize: 10 }
                                Text { text: Model.formatPacketLoss(root.internetPingPacketLoss, true); color: root.internetPingPacketLoss > 0 ? Theme.red : Theme.lightForeground; font.pixelSize: 10; font.bold: true }

                                Text { text: "Down:"; color: Theme.darkForeground; font.pixelSize: 10 }
                                Text { text: Model.formatRate(root.downloadRate); color: Theme.blue; font.pixelSize: 10; font.bold: true }

                                Text { text: "Up:"; color: Theme.darkForeground; font.pixelSize: 10 }
                                Text { text: Model.formatRate(root.uploadRate); color: Theme.magenta; font.pixelSize: 10; font.bold: true }

                                Text { text: "IP:"; color: Theme.darkForeground; font.pixelSize: 10 }
                                Text { text: root.info.ip || "--"; color: Theme.brightForeground; font.pixelSize: 10; font.bold: true }

                                Text { text: "Gateway:"; color: Theme.darkForeground; font.pixelSize: 10 }
                                Text { text: root.info.gateway || "--"; color: Theme.lightForeground; font.pixelSize: 10 }
                            }

                            // --- DNS Selector ---
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "DNS:"
                                    color: Theme.darkForeground
                                    font.pixelSize: 10
                                    font.bold: true
                                }

                                Repeater {
                                    model: ["DHCP", "Cloudflare", "Google"]
                                    Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        height: 22
                                        radius: 4
                                        color: root.activeDns === modelData ? Theme.brand : Theme.surface
                                        border.color: root.activeDns === modelData ? Theme.brand : Theme.selection
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: root.activeDns === modelData ? Theme.darkBackground : Theme.lightForeground
                                            font.pixelSize: 10
                                            font.bold: root.activeDns === modelData
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
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
                                font.pixelSize: 10
                                font.bold: true
                            }

                            ListView {
                                id: networkList
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(Math.max(contentHeight, 35), 200)
                                Layout.fillHeight: false
                                clip: true
                                spacing: 4
                                boundsBehavior: Flickable.StopAtBounds

                                model: root.wifiDevice && root.wifiDevice.networks ? Model.sortWifiRows(root.wifiDevice.networks.values.map(Model.wifiRow)) : []

                                delegate: Rectangle {
                                    required property var modelData
                                    width: networkList.width
                                    height: passwordBox.visible ? 68 : 30
                                    radius: 6
                                    color: modelData.connected ? Theme.selection : Theme.surface
                                    border.color: modelData.connected ? Theme.brand : Theme.selection
                                    border.width: 1

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
                                                font.pixelSize: 12
                                            }

                                            Text {
                                                text: modelData.ssid || "Hidden Network"
                                                color: modelData.connected ? Theme.brand : Theme.foreground
                                                font.pixelSize: 11
                                                font.bold: modelData.connected
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: modelData.security !== "open" && modelData.security !== 0 ? "󰌾" : ""
                                                color: Theme.yellow
                                                font.pixelSize: 10
                                                visible: text !== ""
                                            }

                                            // Connect / Disconnect Action Button
                                            Rectangle {
                                                width: 60
                                                height: 20
                                                radius: 4
                                                color: modelData.connected ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25) : Theme.brand
                                                border.color: modelData.connected ? Theme.red : Theme.brand
                                                border.width: 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.connected ? "Disconnect" : (modelData.known ? "Connect" : "Join")
                                                    color: modelData.connected ? Theme.red : Theme.darkBackground
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
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
                                                    anchors.fill: parent
                                                    anchors.margins: 3
                                                    echoMode: TextInput.Password
                                                    color: Theme.brightForeground
                                                    font.pixelSize: 10
                                                    focus: passwordBox.visible
                                                    onTextChanged: root.enteredPassword = text
                                                    onAccepted: {
                                                        if (modelData.networkObject) {
                                                            modelData.networkObject.connectWithPsk(root.enteredPassword)
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
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.networkObject) {
                                                            modelData.networkObject.connectWithPsk(root.enteredPassword)
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
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
