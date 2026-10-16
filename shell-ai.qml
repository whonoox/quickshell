import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets

ShellRoot {
    id: root

    // Primary green color hex
    readonly property color brandGreen: "#00946d"
    // Map of workspaceId -> Array of window clients
    property var clientsMap: ({
    })
    // Visibility States
    property bool timeVisible: false
    property bool wifiVisible: false
    property bool bluetoothVisible: false
    property bool workspacesVisible: false
    property bool barVisible: false
    property int wifiSelectedIndex: 0
    property int bluetoothSelectedIndex: 0
    property bool wifiPasswordMode: false
    property string wifiTargetSsid: ""

    // Root-level hideAll function callable from both IPC and QML
    function hideAll() {
        root.wifiVisible = false;
        root.bluetoothVisible = false;
        root.barVisible = false;
        root.timeVisible = false;
        root.workspacesVisible = false;
    }

    // Helper functions for Dynamic Workspaces & Client App Icons/Badges
    function getWorkspaceList() {
        var wsSet = {
            "1": true,
            "2": true,
            "3": true,
            "4": true
        };
        for (var key in root.clientsMap) {
            var id = parseInt(key);
            if (id > 0)
                wsSet[id] = true;

        }
        if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0)
            wsSet[Hyprland.focusedWorkspace.id] = true;

        var result = [];
        for (var k in wsSet) {
            result.push(parseInt(k));
        }
        result.sort(function(a, b) {
            return a - b;
        });
        return result;
    }

    function getClientsForWorkspace(wsId) {
        return root.clientsMap[wsId] || [];
    }

    function getAppIcon(cls) {
        if (!cls)
            return "application-x-executable";

        var c = cls.toLowerCase();
        if (c.indexOf("ghostty") !== -1)
            return "com.mitchellh.ghostty";

        if (c.indexOf("zen") !== -1)
            return "zen";

        if (c.indexOf("firefox") !== -1)
            return "firefox";

        if (c.indexOf("chromium") !== -1)
            return "chromium";

        if (c.indexOf("chrome") !== -1)
            return "google-chrome";

        if (c.indexOf("figma") !== -1)
            return "figma-linux";

        if (c.indexOf("telegram") !== -1)
            return "org.telegram.desktop";

        if (c.indexOf("code") !== -1)
            return "vscode";

        if (c.indexOf("kitty") !== -1)
            return "kitty";

        if (c.indexOf("alacritty") !== -1)
            return "Alacritty";

        if (c.indexOf("foot") !== -1)
            return "foot";

        if (c.indexOf("discord") !== -1)
            return "discord";

        if (c.indexOf("spotify") !== -1)
            return "spotify";

        return cls;
    }

    // Helper function for 3-letter day name
    function getDayName() {
        var days = ["SUN", "MON", "TUE", "WED", "THR", "FRI", "SAT"];
        var today = new Date();
        return days[today.getDay()];
    }

    // IPC Handler for keybindings
    IpcHandler {
        function toggleTime() {
            root.timeVisible = !root.timeVisible;
            if (root.timeVisible)
                timeTimer.restart();

        }

        function toggleWifi() {
            root.wifiVisible = !root.wifiVisible;
            if (root.wifiVisible) {
                root.bluetoothVisible = false;
                root.wifiSelectedIndex = 0;
                wifiScanProcess.running = true;
            }
        }

        function toggleBluetooth() {
            root.bluetoothVisible = !root.bluetoothVisible;
            if (root.bluetoothVisible) {
                root.wifiVisible = false;
                root.bluetoothSelectedIndex = 0;
            }
        }

        function toggleWorkspaces() {
            root.workspacesVisible = !root.workspacesVisible;
            if (root.workspacesVisible)
                workspacesTimer.restart();

        }

        function toggleBar() {
            var newState = !root.barVisible;
            root.barVisible = newState;
            root.timeVisible = newState;
            root.workspacesVisible = newState;
            root.wifiVisible = false;
            root.bluetoothVisible = false;
            if (newState)
                barTimer.restart();

        }

        function hideAll() {
            root.hideAll();
        }

        target: "bar"
    }

    // Process to fetch client windows via hyprctl JSON API
    Process {
        id: clientsFetchProcess

        command: ["hyprctl", "clients", "-j"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    var map = {
                    };
                    for (var i = 0; i < data.length; i++) {
                        var c = data[i];
                        if (c.workspace && c.workspace.id > 0 && c.mapped) {
                            var wsId = c.workspace.id;
                            if (!map[wsId])
                                map[wsId] = [];

                            map[wsId].push({
                                "class": c.class || c.initialClass || "application-x-executable",
                                "title": c.title
                            });
                        }
                    }
                    root.clientsMap = map;
                } catch (e) {
                }
            }
        }

    }

    // Periodic refresh timer for clients map
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: clientsFetchProcess.running = true
    }

    // Workspace Change Trigger & Window Event Refresher
    Connections {
        function onFocusedWorkspaceChanged() {
            root.workspacesVisible = true;
            workspacesTimer.restart();
            clientsFetchProcess.running = true;
        }

        function onRawEvent(event) {
            if (event.name === "workspace" || event.name === "focusedmon" || event.name.indexOf("window") !== -1)
                clientsFetchProcess.running = true;

            if (event.name === "workspace" || event.name === "focusedmon") {
                root.workspacesVisible = true;
                workspacesTimer.restart();
            }
            // When user clicks a window outside the panel, Hyprland emits activewindow.
            // Close popups when this happens while they are open.
            if (event.name === "activewindow" && (root.wifiVisible || root.bluetoothVisible)) {
                root.wifiVisible = false;
                root.bluetoothVisible = false;
            }
        }

        target: Hyprland
    }

    // Auto-hide Timers
    Timer {
        id: timeTimer

        interval: 5000
        repeat: false
        onTriggered: {
            if (!timeMouseArea.containsMouse)
                root.timeVisible = false;
            else
                timeTimer.restart();
        }
    }

    Timer {
        id: workspacesTimer

        interval: 5000
        repeat: false
        onTriggered: {
            if (!workspacesMouseArea.containsMouse)
                root.workspacesVisible = false;
            else
                workspacesTimer.restart();
        }
    }

    Timer {
        id: barTimer

        interval: 8000
        repeat: false
        onTriggered: {
            if (!topPanelMouseArea.containsMouse && !root.wifiVisible && !root.bluetoothVisible) {
                root.barVisible = false;
                root.timeVisible = false;
                root.workspacesVisible = false;
            } else {
                barTimer.restart();
            }
        }
    }

    // Network Model & Scanning Process
    ListModel {
        id: wifiModel
    }

    Process {
        id: wifiScanProcess

        command: ["bash", "-c", "iwctl station wlan0 scan && sleep 0.5 && iwctl station wlan0 get-networks | sed 's/\\x1b\\[[0-9;]*m//g'"]

        stdout: StdioCollector {
            onStreamFinished: {
                wifiModel.clear();
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (line === "" || line.indexOf("Available networks") !== -1 || line.indexOf("---") !== -1 || line.indexOf("Network name") !== -1)
                        continue;

                    var isConnected = line.startsWith(">");
                    var cleanLine = line.replace(">", "").trim();
                    var parts = cleanLine.split(/\s{2,}/);
                    if (parts.length >= 1) {
                        var ssid = parts[0].trim();
                        var security = parts.length > 1 ? parts[1].trim() : "open";
                        var signal = parts.length > 2 ? parts[2].trim() : "****";
                        wifiModel.append({
                            "ssid": ssid,
                            "security": security,
                            "signal": signal,
                            "connected": isConnected
                        });
                    }
                }
            }
        }

    }

    Process {
        id: wifiConnectProcess

        command: ["bash", "-c", "echo ''"]
        onExited: {
            wifiScanProcess.running = true;
        }
    }

    // Top Overlay Panel Window
    PanelWindow {
        id: topPanel

        // Overlay mode: FLOATS over windows without reserving margins or pushing tiled windows!
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive keyboard focus when popups are open so we receive key events
        WlrLayershell.keyboardFocus: (root.wifiVisible || root.bluetoothVisible) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        // Dynamic overlay bounds — when full-screen (bottom-anchored), implicitHeight is ignored
        implicitHeight: (root.wifiVisible || root.bluetoothVisible) ? 0 : ((root.timeVisible || root.workspacesVisible || root.barVisible) ? 55 : 0)

        anchors {
            top: true
            left: true
            right: true
            // Full-screen when popups are open so background MouseArea covers entire screen
            bottom: (root.wifiVisible || root.bluetoothVisible) ? true : false
        }

        // Content root item that receives keyboard focus
        Item {
            id: contentRoot

            anchors.fill: parent
            focus: true
            // Escape key handler - works because WlrKeyboardFocus.Exclusive delivers keys to this surface
            Keys.onEscapePressed: function(event) {
                if (root.wifiVisible || root.bluetoothVisible) {
                    root.hideAll();
                    event.accepted = true;
                }
            }
            // Arrow / Enter / S key handler for Wi-Fi and Bluetooth navigation
            Keys.onPressed: function(event) {
                if (root.wifiVisible) {
                    if (root.wifiPasswordMode)
                        return ;

                    if (event.key === Qt.Key_S || event.key === Qt.Key_s) {
                        wifiScanProcess.running = true;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        if (wifiListView.count > 0)
                            root.wifiSelectedIndex = (root.wifiSelectedIndex + 1) % wifiListView.count;

                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        if (wifiListView.count > 0)
                            root.wifiSelectedIndex = (root.wifiSelectedIndex - 1 + wifiListView.count) % wifiListView.count;

                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        if (wifiListView.count > 0 && root.wifiSelectedIndex < wifiListView.count) {
                            var item = wifiModel.get(root.wifiSelectedIndex);
                            if (!item.connected) {
                                if (item.security && item.security.toLowerCase() !== "open") {
                                    root.wifiTargetSsid = item.ssid;
                                    root.wifiPasswordMode = true;
                                } else {
                                    wifiConnectProcess.command = ["bash", "-c", "iwctl station wlan0 connect '" + item.ssid + "'"];
                                    wifiConnectProcess.running = true;
                                }
                            }
                        }
                        event.accepted = true;
                    }
                } else if (root.bluetoothVisible) {
                    var btLen = Bluetooth.devices.length !== undefined ? Bluetooth.devices.length : (Bluetooth.devices.count !== undefined ? Bluetooth.devices.count : 0);
                    if (event.key === Qt.Key_S || event.key === Qt.Key_s) {
                        if (Bluetooth.defaultAdapter)
                            Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering;

                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        if (btLen > 0)
                            root.bluetoothSelectedIndex = (root.bluetoothSelectedIndex + 1) % btLen;

                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        if (btLen > 0)
                            root.bluetoothSelectedIndex = (root.bluetoothSelectedIndex - 1 + btLen) % btLen;

                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        if (btLen > 0 && root.bluetoothSelectedIndex < btLen) {
                            var dev = typeof Bluetooth.devices.get === "function" ? Bluetooth.devices.get(root.bluetoothSelectedIndex) : Bluetooth.devices[root.bluetoothSelectedIndex];
                            if (dev) {
                                if (dev.paired) {
                                    dev.connected ? dev.disconnect() : dev.connect();
                                } else {
                                    dev.pair();
                                    dev.connect();
                                }
                            }
                        }
                        event.accepted = true;
                    }
                }
            }

            // Background click catcher at z:-1 — catches clicks on empty/transparent
            // areas within the panel bounds, but content MouseAreas on top take priority
            MouseArea {
                anchors.fill: parent
                z: -1
                visible: root.wifiVisible || root.bluetoothVisible
                onClicked: root.hideAll()
            }

            MouseArea {
                id: topPanelMouseArea

                anchors.fill: parent
                hoverEnabled: true
                // Qt.NoButton: only track hover for auto-hide timers, don't consume clicks
                acceptedButtons: Qt.NoButton
            }

            Item {
                anchors.fill: parent

                // -------------------------------------------------------------
                // 1. LEFT CONTAINER: Workspaces & NuuX Username
                // -------------------------------------------------------------
                Item {
                    id: leftModule

                    readonly property real rInv: 16
                    readonly property real rBot: 18
                    readonly property real innerWidth: Math.max(280, leftContentRow.implicitWidth + 28)

                    anchors.left: parent.left
                    anchors.leftMargin: 0
                    anchors.top: parent.top
                    width: innerWidth + rInv
                    height: 40
                    opacity: (root.barVisible || root.workspacesVisible) ? 1 : 0
                    visible: opacity > 0.001

                    Shape {
                        anchors.fill: parent

                        // Fill Shape
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: Qt.rgba(16 / 255, 20 / 255, 18 / 255, 0.95)

                            PathMove {
                                x: 0
                                y: 0
                            }

                            PathLine {
                                x: leftModule.width
                                y: 0
                            }

                            PathQuad {
                                x: leftModule.innerWidth
                                y: leftModule.rInv
                                controlX: leftModule.innerWidth
                                controlY: 0
                            }

                            PathLine {
                                x: leftModule.innerWidth
                                y: leftModule.height - leftModule.rBot
                            }

                            PathQuad {
                                x: leftModule.innerWidth - leftModule.rBot
                                y: leftModule.height
                                controlX: leftModule.innerWidth
                                controlY: leftModule.height
                            }

                            PathLine {
                                x: leftModule.rInv
                                y: leftModule.height
                            }

                            PathQuad {
                                x: 0
                                y: leftModule.height + leftModule.rInv
                                controlX: 0
                                controlY: leftModule.height
                            }

                            PathLine {
                                x: 0
                                y: 0
                            }

                        }

                        // Green Border Line ONLY on visible inner edges
                        ShapePath {
                            strokeColor: root.brandGreen
                            strokeWidth: 1.5
                            fillColor: "transparent"

                            PathMove {
                                x: 0
                                y: leftModule.height + leftModule.rInv
                            }

                            PathQuad {
                                x: leftModule.rInv
                                y: leftModule.height
                                controlX: 0
                                controlY: leftModule.height
                            }

                            PathLine {
                                x: leftModule.innerWidth - leftModule.rBot
                                y: leftModule.height
                            }

                            PathQuad {
                                x: leftModule.innerWidth
                                y: leftModule.height - leftModule.rBot
                                controlX: leftModule.innerWidth
                                controlY: leftModule.height
                            }

                            PathLine {
                                x: leftModule.innerWidth
                                y: leftModule.rInv
                            }

                            PathQuad {
                                x: leftModule.width
                                y: 0
                                controlX: leftModule.innerWidth
                                controlY: 0
                            }

                        }

                    }

                    MouseArea {
                        id: workspacesMouseArea

                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: workspacesTimer.stop()
                        onExited: {
                            if (root.workspacesVisible) {
                                workspacesTimer.restart();
                            }
                        }
                    }

                    Item {
                        x: 0
                        y: 0
                        width: leftModule.innerWidth
                        height: 40
                        clip: true

                        RowLayout {
                            id: leftContentRow

                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Text {
                                id: nuuxascii

                                text: "      ▄█\n█▄    ███  █▄     ▄█   █▄     ▄█  █▄     ▄█\n███   ███  ███   ███   ███   ███  ███   ███\n████  ███  ███   ███   ███   ███  ███   ███\n███▀█ ███  ███   ███   ███   ███   ▀█████▀\n███ █████  ███   ███   ███   ███   ▄█████▄\n███  ████  ███   ███   ███  ███   ███\n███   ███  ███   ███   ███   ███  ███   ███\n███    ▀█   ▀█████▀     ▀█████▀   █▀     ▀█\n ▀█                                       "
                                font.pixelSize: 2
                                font.family: 'Cascadia Code'
                                lineHeight: 0.8
                                color: root.brandGreen
                            }

                            Rectangle {
                                width: 1
                                height: 16
                                color: root.brandGreen
                                opacity: 0.5
                            }

                            RowLayout {
                                spacing: 6

                                Repeater {
                                    model: root.getWorkspaceList()

                                    Rectangle {
                                        id: wsButton

                                        readonly property int wsId: modelData
                                        readonly property bool isFocused: Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.id === wsId) : (wsId === 1)
                                        readonly property var clientList: root.getClientsForWorkspace(wsId)

                                        Layout.preferredWidth: wsInnerRow.implicitWidth + 14
                                        height: 24
                                        radius: 12
                                        color: isFocused ? Qt.rgba(13 / 255, 40 / 255, 31 / 255, 0.95) : "transparent"
                                        border.color: isFocused ? root.brandGreen : "transparent"
                                        border.width: isFocused ? 1.5 : 0

                                        RowLayout {
                                            id: wsInnerRow

                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                text: wsButton.wsId.toString()
                                                color: "#ffffff"
                                                font.bold: wsButton.isFocused
                                                font.pixelSize: 11
                                            }

                                            RowLayout {
                                                spacing: 4
                                                visible: wsButton.isFocused && wsButton.clientList.length > 0

                                                Repeater {
                                                    model: wsButton.clientList

                                                    Item {
                                                        width: 16
                                                        height: 16

                                                        IconImage {
                                                            id: iconImg

                                                            anchors.fill: parent
                                                            source: "image://icon/" + root.getAppIcon(modelData.class)
                                                            visible: status === Image.Ready
                                                        }

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 8
                                                            color: "#142c22"
                                                            border.color: root.brandGreen
                                                            border.width: 1
                                                            visible: iconImg.status !== Image.Ready

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: (modelData.class || "A").substring(0, 1).toUpperCase()
                                                                color: root.brandGreen
                                                                font.pixelSize: 9
                                                                font.bold: true
                                                            }

                                                        }

                                                    }

                                                }

                                            }

                                            Rectangle {
                                                visible: !wsButton.isFocused && wsButton.clientList.length > 0
                                                width: 16
                                                height: 16
                                                radius: 8
                                                color: root.brandGreen
                                                opacity: 0.95

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: wsButton.clientList.length.toString()
                                                    color: "#ffffff"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                }

                                            }

                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Hyprland.dispatch("workspace " + wsButton.wsId)
                                        }

                                        Behavior on Layout.preferredWidth {
                                            NumberAnimation {
                                                duration: 250
                                                easing.type: Easing.OutExpo
                                            }

                                        }

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 150
                                            }

                                        }

                                    }

                                }

                            }

                        }

                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutExpo
                        }

                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }

                    }

                }

                // -------------------------------------------------------------
                // 2. CENTER CONTAINER: Dynamic Time Pill
                // -------------------------------------------------------------
                Item {
                    id: centerModule

                    readonly property real rInv: 16
                    readonly property real rBot: 18

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: 220 + (2 * rInv)
                    height: 40
                    opacity: (root.barVisible || root.timeVisible) ? 1 : 0
                    visible: opacity > 0.001

                    Shape {
                        anchors.fill: parent

                        // Background Fill
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: Qt.rgba(16 / 255, 20 / 255, 18 / 255, 0.95)

                            PathMove {
                                x: centerModule.rInv
                                y: centerModule.rInv
                            }

                            PathQuad {
                                x: 0
                                y: 0
                                controlX: centerModule.rInv
                                controlY: 0
                            }

                            PathLine {
                                x: centerModule.width
                                y: 0
                            }

                            PathQuad {
                                x: centerModule.width - centerModule.rInv
                                y: centerModule.rInv
                                controlX: centerModule.width - centerModule.rInv
                                controlY: 0
                            }

                            PathLine {
                                x: centerModule.width - centerModule.rInv
                                y: centerModule.height - centerModule.rBot
                            }

                            PathQuad {
                                x: centerModule.width - centerModule.rInv - centerModule.rBot
                                y: centerModule.height
                                controlX: centerModule.width - centerModule.rInv
                                controlY: centerModule.height
                            }

                            PathLine {
                                x: centerModule.rInv + centerModule.rBot
                                y: centerModule.height
                            }

                            PathQuad {
                                x: centerModule.rInv
                                y: centerModule.height - centerModule.rBot
                                controlX: centerModule.rInv
                                controlY: centerModule.height
                            }

                            PathLine {
                                x: centerModule.rInv
                                y: centerModule.rInv
                            }

                        }

                        // Green Border Line ONLY on visible inner edges
                        ShapePath {
                            strokeColor: root.brandGreen
                            strokeWidth: 1.5
                            fillColor: "transparent"

                            PathMove {
                                x: 0
                                y: 0
                            }

                            PathQuad {
                                x: centerModule.rInv
                                y: centerModule.rInv
                                controlX: centerModule.rInv
                                controlY: 0
                            }

                            PathLine {
                                x: centerModule.rInv
                                y: centerModule.height - centerModule.rBot
                            }

                            PathQuad {
                                x: centerModule.rInv + centerModule.rBot
                                y: centerModule.height
                                controlX: centerModule.rInv
                                controlY: centerModule.height
                            }

                            PathLine {
                                x: centerModule.width - centerModule.rInv - centerModule.rBot
                                y: centerModule.height
                            }

                            PathQuad {
                                x: centerModule.width - centerModule.rInv
                                y: centerModule.height - centerModule.rBot
                                controlX: centerModule.width - centerModule.rInv
                                controlY: centerModule.height
                            }

                            PathLine {
                                x: centerModule.width - centerModule.rInv
                                y: centerModule.rInv
                            }

                            PathQuad {
                                x: centerModule.width
                                y: 0
                                controlX: centerModule.width - centerModule.rInv
                                controlY: 0
                            }

                        }

                    }

                    MouseArea {
                        id: timeMouseArea

                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: timeTimer.stop()
                        onExited: {
                            if (root.timeVisible) {
                                timeTimer.restart();
                            }
                        }
                        onClicked: root.toggleTime()
                    }

                    Item {
                        x: centerModule.rInv
                        y: 0
                        width: 220
                        height: 40
                        clip: true

                        RowLayout {
                            id: centerTimeRow

                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: root.brandGreen

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite

                                    PropertyAnimation {
                                        to: 0.3
                                        duration: 800
                                    }

                                    PropertyAnimation {
                                        to: 1
                                        duration: 800
                                    }

                                }

                            }

                            Text {
                                id: timeTextDisplay

                                font.pointSize: 14
                                font.bold: true
                                font.family: "NuuXFont"
                                font.capitalization: Font.AllUppercase
                                color: "#ffffff"
                                text: root.getDayName() + " : " + Qt.formatDateTime(new Date(), "hh:mm AP")
                            }

                            Timer {
                                interval: 1000
                                running: true
                                repeat: true
                                onTriggered: {
                                    timeTextDisplay.text = root.getDayName() + " : " + Qt.formatDateTime(new Date(), "hh:mm AP");
                                }
                            }

                        }

                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }

                    }

                }

                // -------------------------------------------------------------
                // 3. RIGHT CONTAINER: Controls / Wi-Fi / Bluetooth
                // -------------------------------------------------------------
                Item {
                    id: rightModule

                    readonly property real rInv: 16
                    readonly property real rBot: 18

                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    anchors.top: parent.top
                    width: 360 + rInv
                    height: (root.wifiVisible || root.bluetoothVisible) ? 350 : 40
                    opacity: (root.barVisible || root.wifiVisible || root.bluetoothVisible) ? 1 : 0
                    visible: opacity > 0.001

                    Shape {
                        id: morphingBgShape

                        anchors.fill: parent

                        // Fill Shape
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: Qt.rgba(16 / 255, 20 / 255, 18 / 255, 0.95)

                            PathMove {
                                x: rightModule.rInv
                                y: rightModule.rInv
                            }

                            PathQuad {
                                x: 0
                                y: 0
                                controlX: rightModule.rInv
                                controlY: 0
                            }

                            PathLine {
                                x: rightModule.width
                                y: 0
                            }

                            PathLine {
                                x: rightModule.width
                                y: rightModule.height + rightModule.rInv
                            }

                            PathQuad {
                                x: rightModule.width - rightModule.rInv
                                y: rightModule.height
                                controlX: rightModule.width
                                controlY: rightModule.height
                            }

                            PathLine {
                                x: rightModule.rInv + rightModule.rBot
                                y: rightModule.height
                            }

                            PathQuad {
                                x: rightModule.rInv
                                y: rightModule.height - rightModule.rBot
                                controlX: rightModule.rInv
                                controlY: rightModule.height
                            }

                            PathLine {
                                x: rightModule.rInv
                                y: rightModule.rInv
                            }

                        }

                        // Green Border Line ONLY on visible inner edges
                        ShapePath {
                            strokeColor: root.brandGreen
                            strokeWidth: 1.5
                            fillColor: "transparent"

                            PathMove {
                                x: 0
                                y: 0
                            }

                            PathQuad {
                                x: rightModule.rInv
                                y: rightModule.rInv
                                controlX: rightModule.rInv
                                controlY: 0
                            }

                            PathLine {
                                x: rightModule.rInv
                                y: rightModule.height - rightModule.rBot
                            }

                            PathQuad {
                                x: rightModule.rInv + rightModule.rBot
                                y: rightModule.height
                                controlX: rightModule.rInv
                                controlY: rightModule.height
                            }

                            PathLine {
                                x: rightModule.width - rightModule.rInv
                                y: rightModule.height
                            }

                            PathQuad {
                                x: rightModule.width
                                y: rightModule.height + rightModule.rInv
                                controlX: rightModule.width
                                controlY: rightModule.height
                            }

                        }

                    }

                    // Top Header Bar
                    Item {
                        x: rightModule.rInv
                        y: 0
                        width: 360
                        height: 40
                        clip: true

                        RowLayout {
                            id: rightBarHeaderRow

                            anchors.centerIn: parent
                            spacing: 10

                            // Wi-Fi Status & Toggle Button Pill
                            Rectangle {
                                Layout.preferredWidth: wifiHeaderRow.implicitWidth + 22
                                height: 26
                                radius: 13
                                color: root.wifiVisible ? root.brandGreen : Qt.rgba(0 / 255, 148 / 255, 109 / 255, 0.15)
                                border.color: root.brandGreen
                                border.width: 1

                                RowLayout {
                                    id: wifiHeaderRow

                                    anchors.centerIn: parent
                                    spacing: 6

                                    Image {
                                        source: "./decorations/signal.svg"
                                        width: 14
                                        height: 14
                                    }

                                    Text {
                                        id: wifiLabelText

                                        text: wifiTextProcess.wifiSSID
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleWifi()
                                }

                            }

                            // Wi-Fi Connection SSID fetcher process
                            Process {
                                id: wifiTextProcess

                                property string wifiSSID: "Wi-Fi"

                                command: ["bash", "-c", "iwctl station wlan0 show | awk '/Connected network/ {print $NF}'"]
                                running: true

                                stdout: StdioCollector {
                                    onStreamFinished: {
                                        var res = this.text.trim();
                                        wifiTextProcess.wifiSSID = res.length > 0 ? res : "Disconnected";
                                    }
                                }

                            }

                            Timer {
                                interval: 4000
                                running: true
                                repeat: true
                                onTriggered: wifiTextProcess.running = true
                            }

                            // Battery Percentage Indicator Pill
                            Rectangle {
                                height: 26
                                Layout.preferredWidth: batRow.implicitWidth + 18
                                radius: 13
                                color: Qt.rgba(21 / 255, 37 / 255, 30 / 255, 0.8)
                                border.color: Qt.rgba(0 / 255, 148 / 255, 109 / 255, 0.4)
                                border.width: 1

                                RowLayout {
                                    id: batRow

                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: "⚡"
                                        font.pixelSize: 10
                                    }

                                    Text {
                                        text: UPower.devices.values.length > 0 ? Math.round(UPower.devices.values[0].percentage * 100) + "%" : "--%"
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                }

                            }

                            // Bluetooth Status & Toggle Button Pill
                            Rectangle {
                                Layout.preferredWidth: btHeaderRow.implicitWidth + 22
                                height: 26
                                radius: 13
                                color: root.bluetoothVisible ? root.brandGreen : Qt.rgba(0 / 255, 148 / 255, 109 / 255, 0.15)
                                border.color: root.brandGreen
                                border.width: 1

                                RowLayout {
                                    id: btHeaderRow

                                    anchors.centerIn: parent
                                    spacing: 6

                                    Image {
                                        source: "./decorations/bluetoothidle.svg"
                                        width: 14
                                        height: 14
                                    }

                                    Text {
                                        text: "BT"
                                        color: "#ffffff"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleBluetooth()
                                }

                            }

                        }

                    }

                    // -----------------------------------------------------------
                    // Y-AXIS SLIDING CONTROLLER CARDS WITH BREATHING ROOM
                    // -----------------------------------------------------------
                    Item {
                        id: contentClipViewport

                        x: rightModule.rInv + 16
                        y: 44
                        width: 328
                        height: Math.max(0, parent.height - 54)
                        clip: true

                        // Wi-Fi Controller Content
                        Item {
                            id: wifiContentBox

                            width: parent.width
                            height: 290
                            y: root.wifiVisible ? 0 : -290
                            opacity: root.wifiVisible ? 1 : 0
                            visible: opacity > 0.01

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 12

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: root.brandGreen
                                    opacity: 0.35
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        text: "WI-FI NETWORKS"
                                        font.bold: true
                                        font.pixelSize: 12
                                        color: root.brandGreen
                                        font.family: "Cascadia Code"
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        width: scanBtnText.implicitWidth + 16
                                        height: 24
                                        radius: 12
                                        color: root.brandGreen
                                        opacity: 0.9

                                        Text {
                                            id: scanBtnText

                                            anchors.centerIn: parent
                                            text: "Scan [S]"
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: wifiScanProcess.running = true
                                        }

                                    }

                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    ListView {
                                        id: wifiListView

                                        anchors.fill: parent
                                        visible: !root.wifiPasswordMode
                                        spacing: 6
                                        clip: true
                                        model: wifiModel
                                        currentIndex: root.wifiSelectedIndex

                                        delegate: Rectangle {
                                            width: wifiListView.width
                                            height: 42
                                            radius: 10
                                            color: index === root.wifiSelectedIndex ? root.brandGreen : (model.connected ? "#142c22" : Qt.rgba(18 / 255, 36 / 255, 27 / 255, 0.6))
                                            opacity: index === root.wifiSelectedIndex ? 0.95 : 0.85
                                            border.color: root.brandGreen
                                            border.width: model.connected || index === root.wifiSelectedIndex ? 1.5 : 0.5

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14
                                                anchors.rightMargin: 14
                                                spacing: 10

                                                Text {
                                                    text: model.connected ? "✓" : "•"
                                                    color: model.connected ? root.brandGreen : "#779988"
                                                    font.bold: true
                                                }

                                                Text {
                                                    text: model.ssid
                                                    color: "#ffffff"
                                                    font.bold: model.connected || index === root.wifiSelectedIndex
                                                    font.pixelSize: 12
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: model.security
                                                    color: "#88aa99"
                                                    font.pixelSize: 10
                                                }

                                                Text {
                                                    text: model.signal
                                                    color: root.brandGreen
                                                    font.pixelSize: 10
                                                }

                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.wifiSelectedIndex = index;
                                                    if (!model.connected) {
                                                        if (model.security && model.security.toLowerCase() !== "open") {
                                                            root.wifiTargetSsid = model.ssid;
                                                            root.wifiPasswordMode = true;
                                                        } else {
                                                            wifiConnectProcess.command = ["bash", "-c", "iwctl station wlan0 connect '" + model.ssid + "'"];
                                                            wifiConnectProcess.running = true;
                                                        }
                                                    }
                                                }
                                            }

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 150
                                                }

                                            }

                                        }

                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        visible: root.wifiPasswordMode
                                        radius: 10
                                        color: Qt.rgba(18 / 255, 36 / 255, 27 / 255, 0.6)
                                        border.color: root.brandGreen
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 12

                                            Text {
                                                text: "Password for " + root.wifiTargetSsid
                                                color: "#ffffff"
                                                font.pixelSize: 12
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 200
                                                Layout.preferredHeight: 32
                                                color: "#142c22"
                                                border.color: root.brandGreen
                                                radius: 6

                                                TextInput {
                                                    id: wifiPasswordInput

                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    color: "#ffffff"
                                                    font.pixelSize: 12
                                                    echoMode: TextInput.Password
                                                    clip: true
                                                    onVisibleChanged: {
                                                        if (visible) {
                                                            text = "";
                                                            forceActiveFocus();
                                                        }
                                                    }
                                                    onAccepted: {
                                                        if (text.length > 0) {
                                                            wifiConnectProcess.command = ["bash", "-c", "iwctl station wlan0 connect '" + root.wifiTargetSsid + "' --passphrase '" + text + "'"];
                                                            wifiConnectProcess.running = true;
                                                        } else {
                                                            wifiConnectProcess.command = ["bash", "-c", "iwctl station wlan0 connect '" + root.wifiTargetSsid + "'"];
                                                            wifiConnectProcess.running = true;
                                                        }
                                                        root.wifiPasswordMode = false;
                                                        text = "";
                                                        root.forceActiveFocus();
                                                    }
                                                    Keys.onEscapePressed: {
                                                        root.wifiPasswordMode = false;
                                                        text = "";
                                                        root.forceActiveFocus();
                                                    }
                                                }

                                            }

                                            Text {
                                                text: "Enter to connect, Esc to cancel"
                                                color: "#88aa99"
                                                font.pixelSize: 10
                                            }

                                        }

                                    }

                                }

                                Text {
                                    text: root.wifiPasswordMode ? "Type password and press Enter" : "Use ↑/↓ to navigate, Enter to connect, Esc to close"
                                    font.pixelSize: 10
                                    color: "#779988"
                                    Layout.alignment: Qt.AlignHCenter
                                }

                            }

                            Behavior on y {
                                NumberAnimation {
                                    duration: 350
                                    easing.type: Easing.OutExpo
                                }

                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 250
                                }

                            }

                        }

                        // Bluetooth Controller Content
                        Item {
                            id: bluetoothContentBox

                            width: parent.width
                            height: 290
                            y: root.bluetoothVisible ? 0 : -290
                            opacity: root.bluetoothVisible ? 1 : 0
                            visible: opacity > 0.01

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 12

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: root.brandGreen
                                    opacity: 0.35
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        text: "BLUETOOTH DEVICES"
                                        font.bold: true
                                        font.pixelSize: 12
                                        color: root.brandGreen
                                        font.family: "Cascadia Code"
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        width: btScanBtnText.implicitWidth + 16
                                        height: 24
                                        radius: 12
                                        color: root.brandGreen
                                        opacity: 0.9

                                        Text {
                                            id: btScanBtnText

                                            anchors.centerIn: parent
                                            text: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) ? "Stop [S]" : "Scan [S]"
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (Bluetooth.defaultAdapter)
                                                    Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering;

                                            }
                                        }

                                    }

                                }

                                Flickable {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    contentWidth: width
                                    contentHeight: btDevicesColumn.childrenRect.height

                                    Column {
                                        id: btDevicesColumn

                                        width: parent.width
                                        spacing: 6

                                        Text {
                                            text: "PAIRED DEVICES"
                                            font.pixelSize: 10
                                            color: "#88aa99"
                                        }

                                        Repeater {
                                            model: Bluetooth.devices

                                            delegate: Rectangle {
                                                width: btDevicesColumn.width
                                                height: modelData.paired ? 42 : 0
                                                visible: modelData.paired
                                                radius: 10
                                                color: index === root.bluetoothSelectedIndex ? root.brandGreen : (modelData.connected ? "#142c22" : Qt.rgba(18 / 255, 36 / 255, 27 / 255, 0.6))
                                                opacity: index === root.bluetoothSelectedIndex ? 0.95 : 0.85
                                                border.color: root.brandGreen
                                                border.width: modelData.connected || index === root.bluetoothSelectedIndex ? 1.5 : 0.5

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    spacing: 10
                                                    visible: parent.visible

                                                    Image {
                                                        source: "image://icon/" + (modelData.icon ? modelData.icon : "bluetooth")
                                                        sourceSize: Qt.size(16, 16)
                                                    }

                                                    Text {
                                                        text: modelData.name || "Unknown Device"
                                                        color: "#ffffff"
                                                        font.bold: modelData.connected || index === root.bluetoothSelectedIndex
                                                        font.pixelSize: 12
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: modelData.batteryAvailable ? modelData.battery + "%" : ""
                                                        color: "#88aa99"
                                                        font.pixelSize: 10
                                                        visible: modelData.batteryAvailable
                                                    }

                                                    Text {
                                                        text: BluetoothDeviceState.toString(modelData.state)
                                                        color: modelData.connected ? root.brandGreen : "#88aa99"
                                                        font.pixelSize: 10
                                                    }

                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.bluetoothSelectedIndex = index;
                                                        modelData.connected ? modelData.disconnect() : modelData.connect();
                                                    }
                                                }

                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 150
                                                    }

                                                }

                                            }

                                        }

                                        Item {
                                            width: 1
                                            height: 6
                                        }

                                        Text {
                                            text: "DISCOVERED DEVICES"
                                            font.pixelSize: 10
                                            color: "#88aa99"
                                        }

                                        Repeater {
                                            model: Bluetooth.devices

                                            delegate: Rectangle {
                                                width: btDevicesColumn.width
                                                height: !modelData.paired ? 42 : 0
                                                visible: !modelData.paired
                                                radius: 10
                                                color: index === root.bluetoothSelectedIndex ? root.brandGreen : Qt.rgba(18 / 255, 36 / 255, 27 / 255, 0.6)
                                                opacity: index === root.bluetoothSelectedIndex ? 0.95 : 0.85
                                                border.color: root.brandGreen
                                                border.width: index === root.bluetoothSelectedIndex ? 1.5 : 0.5

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    spacing: 10
                                                    visible: parent.visible

                                                    Image {
                                                        source: "image://icon/" + (modelData.icon ? modelData.icon : "bluetooth")
                                                        sourceSize: Qt.size(16, 16)
                                                    }

                                                    Text {
                                                        text: modelData.name || "Unknown Device"
                                                        color: "#ffffff"
                                                        font.bold: index === root.bluetoothSelectedIndex
                                                        font.pixelSize: 12
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: BluetoothDeviceState.toString(modelData.state)
                                                        color: "#88aa99"
                                                        font.pixelSize: 10
                                                    }

                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.bluetoothSelectedIndex = index;
                                                        modelData.pair();
                                                        modelData.connect();
                                                    }
                                                }

                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 150
                                                    }

                                                }

                                            }

                                        }

                                    }

                                }

                                Text {
                                    text: "Use ↑/↓ to navigate, Enter to toggle connection, Esc to close"
                                    font.pixelSize: 10
                                    color: "#779988"
                                    Layout.alignment: Qt.AlignHCenter
                                }

                            }

                            Behavior on y {
                                NumberAnimation {
                                    duration: 350
                                    easing.type: Easing.OutExpo
                                }

                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 250
                                }

                            }

                        }

                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.OutExpo
                        }

                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }

                    }

                }

            }

        }

    }

}
