import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: root

    // Corner island: hidden by default, pops up on trigger, auto-hides like other HUD bars
    property bool hideBar: true
    property string lastTriggered: "none" // "notif" | "mic" | "none"
    property bool _initialized: false

    function reveal(triggerSource) {
        root.lastTriggered = triggerSource || "none"
        root.hideBar = false
        autoHideTimer.restart()
    }

    Timer {
        id: autoHideTimer
        interval: 2500
        onTriggered: {
            root.hideBar = true
            root.lastTriggered = "none"
        }
    }

    function toggleNotif() {
        ToggleState.toggleDnd()
        root.reveal("notif")
    }

    function toggleMic() {
        ToggleState.toggleMic()
        root.reveal("mic")
    }

    function toggleCursor() {
        ToggleState.toggleCursorXRay()
        root.reveal("cursor")
    }

    function toggleAwake() {
        ToggleState.toggleStayAwake()
        root.reveal("awake")
    }

    function toggleFnLock() {
        ToggleState.toggleFnLock()
        root.reveal("fnlock")
    }

    Connections {
        target: ToggleState
        function onMicMutedChanged() {
            if (root._initialized) {
                root.reveal("mic")
            }
        }
        function onDndChanged() {
            if (root._initialized) {
                root.reveal("notif")
            }
        }
        function onCursorXRayChanged() {
            if (root._initialized) {
                root.reveal("cursor")
            }
        }
        function onStayAwakeChanged() {
            if (root._initialized) {
                root.reveal("awake")
            }
        }
        function onFnLockChanged() {
            if (root._initialized) {
                root.reveal("fnlock")
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            root._initialized = true
        })
    }

    // ------------------------------------------------------------------
    // Global Shortcuts
    // ------------------------------------------------------------------
    GlobalShortcut {
        name: "notifToggle"
        description: "Toggle notifications Do Not Disturb"
        appid: "quickshell"
        onPressed: root.toggleNotif()
    }

    GlobalShortcut {
        name: "micToggle"
        description: "Toggle microphone mute"
        appid: "quickshell"
        onPressed: root.toggleMic()
    }

    GlobalShortcut {
        name: "cursorXRayToggle"
        description: "Toggle Cursor X-Ray mode"
        appid: "quickshell"
        onPressed: root.toggleCursor()
    }

    GlobalShortcut {
        name: "stayAwakeToggle"
        description: "Toggle stay awake idle inhibition"
        appid: "quickshell"
        onPressed: root.toggleAwake()
    }

    // ------------------------------------------------------------------
    // IPC Handler
    // ------------------------------------------------------------------
    IpcHandler {
        target: "toggleBar"

        function toggle(): string {
            root.hideBar = !root.hideBar
            if (!root.hideBar) {
                root.reveal("none")
            }
            return root.hideBar ? "closed" : "open"
        }

        function open(): string {
            root.reveal("none")
            return "open"
        }

        function close(): string {
            root.hideBar = true
            return "closed"
        }

        function toggleNotif(): string {
            root.toggleNotif()
            return ToggleState.dnd ? "dnd_on" : "dnd_off"
        }

        function toggleMic(): string {
            root.toggleMic()
            return ToggleState.micMuted ? "muted" : "live"
        }

        function toggleCursor(): string {
            root.toggleCursor()
            return ToggleState.cursorXRay ? "on" : "off"
        }

        function toggleAwake(): string {
            root.toggleAwake()
            return ToggleState.stayAwake ? "awake_on" : "awake_off"
        }

        function toggleFnLock(): string {
            root.toggleFnLock()
            return ToggleState.fnLock ? "fnlock_on" : "fnlock_off"
        }

        function revealMic(): string {
            root.reveal("mic")
            return "ok"
        }

        function revealNotif(): string {
            root.reveal("notif")
            return "ok"
        }

        function revealCursor(): string {
            root.reveal("cursor")
            return "ok"
        }

        function revealAwake(): string {
            root.reveal("awake")
            return "ok"
        }

        function revealFnLock(): string {
            root.reveal("fnlock")
            return "ok"
        }

        function notifStatus(): string {
            return ToggleState.dnd ? "dnd_on" : "dnd_off"
        }

        function micStatus(): string {
            return ToggleState.micMuted ? "muted" : "live"
        }

        function cursorStatus(): string {
            return ToggleState.cursorXRay ? "on" : "off"
        }

        function awakeStatus(): string {
            return ToggleState.stayAwake ? "awake_on" : "awake_off"
        }

        function fnLockStatus(): string {
            return ToggleState.fnLock ? "fnlock_on" : "fnlock_off"
        }

        function status(): string {
            return JSON.stringify({
                notifDnd: ToggleState.dnd,
                micMuted: ToggleState.micMuted,
                cursorXRay: ToggleState.cursorXRay,
                stayAwake: ToggleState.stayAwake,
                fnLock: ToggleState.fnLock,
                fnLockAvailable: ToggleState.fnLockAvailable,
                visible: !root.hideBar,
                lastTriggered: root.lastTriggered
            })
        }
    }

    // ------------------------------------------------------------------
    // Panel Window (Bottom-Left Corner)
    // ------------------------------------------------------------------
    BarVariants {
        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData

            visible: false

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            WlrLayershell.namespace: "toggle-panel-main"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            mask: Region {
                item: cardContainer
            }

            // Bottom-Left Anchored Card Container
            Item {
                id: cardContainer
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -(height + 20)

                width: contentRow.implicitWidth + Theme.spacing * 4 + Theme.rounding + Theme.borderWidth
                height: 44 + Theme.rounding + Theme.borderWidth

                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                NumberAnimation {
                    id: slideAnim
                    target: cardContainer
                    property: "anchors.bottomMargin"
                    duration: 250
                    easing.type: Easing.OutCubic
                    onFinished: {
                        if (root.hideBar) {
                            panelWindow.visible = false
                        }
                    }
                }

                Connections {
                    target: root
                    function onHideBarChanged() {
                        if (!root.hideBar) {
                            panelWindow.visible = true
                            slideAnim.stop()
                            cardContainer.anchors.bottomMargin = -(cardContainer.height + 20)
                            slideAnim.from = -(cardContainer.height + 20)
                            slideAnim.to = 0
                            slideAnim.start()
                        } else {
                            slideAnim.stop()
                            slideAnim.from = cardContainer.anchors.bottomMargin
                            slideAnim.to = -(cardContainer.height + 20)
                            slideAnim.start()
                        }
                    }
                }

                Component.onCompleted: {
                    if (!root.hideBar) {
                        panelWindow.visible = true
                        cardContainer.anchors.bottomMargin = 0
                    }
                }

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            autoHideTimer.stop()
                        } else {
                            autoHideTimer.restart()
                        }
                    }
                }

                // Unified single-vector background contour (position: bottomLeft)
                ScoopV2 {
                    id: backgroundShape
                    anchors.fill: parent
                    position: "bottomLeft"
                    color: Theme.bgc
                    radius: Theme.rounding
                    cornerRadius: Theme.rounding
                    borderWidth: Theme.borderWidth
                }

                // Inner Content Area
                Item {
                    id: background
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.rounding + Theme.borderWidth
                    anchors.top: parent.top
                    anchors.topMargin: Theme.rounding + Theme.borderWidth

                    Row {
                        id: contentRow
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacing * 1.5

                        // 1. Notification DND Toggle (No button background, no border)
                        Item {
                            id: notifButton
                            width: 24
                            height: 24

                            readonly property bool isDnd: ToggleState.dnd
                            readonly property bool isTriggered: root.lastTriggered === "notif"
                            readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                            readonly property bool isHovered: notifMouse.containsMouse

                            scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                            opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Image {
                                id: notifRawIcon
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                sourceSize.width: 32
                                sourceSize.height: 32
                                source: notifButton.isDnd ? "decorations/bell-slash.svg" : "decorations/bell.svg"
                                fillMode: Image.PreserveAspectFit
                                visible: false
                            }

                            MultiEffect {
                                anchors.fill: notifRawIcon
                                source: notifRawIcon
                                colorization: 1.0
                                colorizationColor: !notifButton.isDnd
                                    ? Theme.brand
                                    : (notifButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                                Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: notifMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleNotif()
                            }
                        }

                        // 2. Microphone Mute Toggle (No button background, no border)
                        Item {
                            id: micButton
                            width: 24
                            height: 24

                            readonly property bool isMuted: ToggleState.micMuted
                            readonly property bool isTriggered: root.lastTriggered === "mic"
                            readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                            readonly property bool isHovered: micMouse.containsMouse

                            scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                            opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Image {
                                id: micRawIcon
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                sourceSize.width: 32
                                sourceSize.height: 32
                                source: micButton.isMuted ? "decorations/microphone-slash.svg" : "decorations/microphone.svg"
                                fillMode: Image.PreserveAspectFit
                                visible: false
                            }

                            MultiEffect {
                                anchors.fill: micRawIcon
                                source: micRawIcon
                                colorization: 1.0
                                colorizationColor: !micButton.isMuted
                                    ? Theme.brand
                                    : (micButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                                Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: micMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleMic()
                            }
                        }

                        // 3. Cursor X-Ray Toggle (No button background, no border)
                        Item {
                            id: cursorButton
                            width: 24
                            height: 24

                            readonly property bool isXRay: ToggleState.cursorXRay
                            readonly property bool isTriggered: root.lastTriggered === "cursor"
                            readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                            readonly property bool isHovered: cursorMouse.containsMouse

                            scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                            opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Image {
                                id: cursorRawIcon
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                sourceSize.width: 32
                                sourceSize.height: 32
                                source: "decorations/cursor.svg"
                                fillMode: Image.PreserveAspectFit
                                visible: false
                            }

                            MultiEffect {
                                anchors.fill: cursorRawIcon
                                source: cursorRawIcon
                                colorization: 1.0
                                colorizationColor: cursorButton.isXRay
                                    ? Theme.brand
                                    : (cursorButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                                Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: cursorMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleCursor()
                            }
                        }

                        // 4. Stay Awake (Idle Inhibition) Toggle (No button background, no border)
                        Item {
                            id: awakeButton
                            width: 24
                            height: 24

                            readonly property bool isAwake: ToggleState.stayAwake
                            readonly property bool isTriggered: root.lastTriggered === "awake"
                            readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                            readonly property bool isHovered: awakeMouse.containsMouse

                            scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                            opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Image {
                                id: awakeRawIcon
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                sourceSize.width: 32
                                sourceSize.height: 32
                                source: "decorations/coffee.svg"
                                fillMode: Image.PreserveAspectFit
                                visible: false
                            }

                            MultiEffect {
                                anchors.fill: awakeRawIcon
                                source: awakeRawIcon
                                colorization: 1.0
                                colorizationColor: awakeButton.isAwake
                                    ? Theme.brand
                                    : (awakeButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                                Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: awakeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleAwake()
                            }
                        }

                        // 5. Fn Lock Toggle (No button background, no border)
                        Item {
                            id: fnLockButton
                            width: 24
                            height: 24
                            visible: ToggleState.fnLockAvailable

                            readonly property bool isFnLock: ToggleState.fnLock
                            readonly property bool isTriggered: root.lastTriggered === "fnlock"
                            readonly property bool isOtherTriggered: root.lastTriggered !== "none" && !isTriggered
                            readonly property bool isHovered: fnLockMouse.containsMouse

                            scale: isHovered ? 1.1 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.75 : 0.9))
                            opacity: isHovered ? 1.0 : (isTriggered ? 1.0 : (isOtherTriggered ? 0.4 : 0.85))

                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Image {
                                id: fnLockRawIcon
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                sourceSize.width: 32
                                sourceSize.height: 32
                                source: "decorations/function.svg"
                                fillMode: Image.PreserveAspectFit
                                visible: false
                            }

                            MultiEffect {
                                anchors.fill: fnLockRawIcon
                                source: fnLockRawIcon
                                colorization: 1.0
                                colorizationColor: fnLockButton.isFnLock
                                    ? Theme.brand
                                    : (fnLockButton.isHovered ? Theme.brightForeground : Theme.darkForeground)
                                Behavior on colorizationColor { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: fnLockMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleFnLock()
                            }
                        }
                    }
                }
            }
        }
    }
}
