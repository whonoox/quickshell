import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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

    // Bluetooth Adapter & Devices
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var allDevices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var deviceGroups: Model.deviceLists(allDevices)

    readonly property var connectedDevices: deviceGroups.connected || []
    readonly property var knownDevices: deviceGroups.known || []
    readonly property var discoveredDevices: deviceGroups.discovered || []

    readonly property var primaryConnectedDevice: connectedDevices.length > 0 ? connectedDevices[0] : null
    readonly property bool hasConnection: primaryConnectedDevice !== null

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
        interval: 3000
        running: root.hudVisible && !root.isExpanded
        onTriggered: {
            root.hudVisible = false
        }
    }

    // Helper Actions
    function toggleDiscovery() {
        if (adapter) adapter.discovering = !adapter.discovering
    }

    function togglePower() {
        if (adapter) adapter.enabled = !adapter.enabled
    }

    function launchBlueman() {
        Quickshell.execDetached(["hyprctl", "dispatch", "exec", "[float; size 750 500; center] blueman-manager"])
    }

    function connectDevice(dev) {
        if (!dev || !dev.address) return
        Quickshell.execDetached(["omarchy-bluetooth-device", dev.paired ? "connect" : "pair", dev.address])
    }

    function disconnectDevice(dev) {
        if (!dev || !dev.address) return
        Quickshell.execDetached(["omarchy-bluetooth-device", "disconnect", dev.address])
    }

    function forgetDevice(dev) {
        if (!dev || !dev.address) return
        Quickshell.execDetached(["omarchy-bluetooth-device", "forget", dev.address])
    }

    function revealDeviceCursor() {
        if (root.totalDeviceCount <= 0) return
        deviceList.currentIndex = root.selectedDeviceIndex
        if (root.selectedDeviceIndex === 0) {
            deviceList.positionViewAtIndex(0, ListView.Beginning)
            return
        }
        if (root.selectedDeviceIndex === root.totalDeviceCount - 1) {
            deviceList.positionViewAtIndex(root.totalDeviceCount - 1, ListView.End)
            return
        }
        deviceList.positionViewAtIndex(root.selectedDeviceIndex, ListView.Contain)

        var item = deviceList.itemAtIndex(root.selectedDeviceIndex)
        if (!item) return
        var reach = 36
        var maxY = Math.max(0, deviceList.contentHeight - deviceList.height)
        if (root.selectedDeviceIndex < root.totalDeviceCount - 1) {
            var overhang = item.y + item.height + reach - (deviceList.contentY + deviceList.height)
            if (overhang > 0) deviceList.contentY = Math.min(deviceList.contentY + overhang, maxY)
        }
        if (root.selectedDeviceIndex > 0) {
            var underhang = deviceList.contentY - (item.y - reach)
            if (underhang > 0) deviceList.contentY = Math.max(deviceList.contentY - underhang, 0)
        }
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

            if (root.deviceActionFocused && item.section === "known") {
                forgetDevice(dev)
            } else if (dev.connected) {
                disconnectDevice(dev)
            } else {
                connectDevice(dev)
            }
        }
    }

    // Multi-Monitor Twin Dismissal (For secondary monitors only)
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
                }

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root.isExpanded = false
                        root.hudVisible = false
                        event.accepted = true
                        return
                    }

                    // --- Arrow Down Navigation ---
                    if (event.key === Qt.Key_Down) {
                        if (root.focusSection === "header") {
                            if (root.totalDeviceCount > 0) {
                                root.focusSection = "devices"
                                if (root.selectedDeviceIndex < 0) root.selectedDeviceIndex = 0
                                root.deviceActionFocused = false
                                root.revealDeviceCursor()
                            }
                        } else if (root.focusSection === "devices") {
                            if (root.selectedDeviceIndex < root.totalDeviceCount - 1) {
                                root.selectedDeviceIndex++
                            } else {
                                root.selectedDeviceIndex = 0
                            }
                            root.deviceActionFocused = false
                            root.revealDeviceCursor()
                        }
                        event.accepted = true
                        return
                    }

                    // --- Arrow Up Navigation ---
                    if (event.key === Qt.Key_Up) {
                        if (root.focusSection === "devices") {
                            if (root.selectedDeviceIndex > 0) {
                                root.selectedDeviceIndex--
                                root.deviceActionFocused = false
                            } else {
                                root.selectedDeviceIndex = Math.max(0, root.totalDeviceCount - 1)
                                root.deviceActionFocused = false
                            }
                            root.revealDeviceCursor()
                        } else if (root.focusSection === "header") {
                            if (root.totalDeviceCount > 0) {
                                root.focusSection = "devices"
                                root.selectedDeviceIndex = root.totalDeviceCount - 1
                                root.deviceActionFocused = false
                                root.revealDeviceCursor()
                            }
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

                    // --- Activation (Return / Enter / Space) ---
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
                    x: root.hideAll ? (parent.width + 30) : (parent.width - width)
                    y: root.hideAll ? -(height + 30) : 0

                    width: root.isExpanded ? 390 : (headerLeftRow.implicitWidth + Theme.rounding * 3)
                    height: root.isExpanded ? Math.min(520, summaryHeader.height + detailsColumn.implicitHeight + Theme.rounding + Theme.spacing * 2) : (Theme.rounding * 2.5)

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
                            height: Theme.rounding * 2.5 - Theme.rounding

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

                            // Device Label & Battery Pill Row
                            RowLayout {
                                id: headerLeftRow
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacing
                                anchors.top: parent.top
                                anchors.topMargin: Theme.spacing
                                spacing: Theme.spacing

                                Text {
                                    id: btLabel
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
                                }

                                // Small Pill Badge with Percentage as Number
                                Rectangle {
                                    id: batteryPill
                                    visible: root.hasConnection && root.primaryConnectedDevice.batteryAvailable && root.primaryConnectedDevice.battery > 0
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
                                    Layout.alignment: Qt.AlignVCenter

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
                        }
                    }
                }
            }
        }
    }
}