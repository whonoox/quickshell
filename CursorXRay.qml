import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Shapes

Scope {
    id: root

    // ---- State & Geometry ----
    property bool active: false
    property real cursorX: 0
    property real cursorY: 0

    // Standard cursor size (width & height in screen pixels)
    // Wayland/Hyprland default is 24px, 28px provides high clarity and visibility
    property real cursorSize: 28

    // Phosphor cursor vector coordinate metrics:
    // Apex of arrow tip in Phosphor 256x256 viewBox is at (36.72, 36.72)
    // Bottom-right tail extremity is at (224.0, 224.0)
    // Active span = 187.28 units
    readonly property real vectorSpan: 187.28
    readonly property real vectorTipX: 36.72
    readonly property real vectorTipY: 36.72
    readonly property real cursorScale: cursorSize / vectorSpan

    property real cursorScaleFactor: 0.85
    property real cursorOpacity: 0.0

    // Phosphor regular cursor outline path (256x256 viewBox)
    readonly property string phosphorOutlinePath: "M168,132.69,214.08,115l.33-.13A16,16,0,0,0,213,85.07L52.92,32.8A15.95,15.95,0,0,0,32.8,52.92L85.07,213a15.82,15.82,0,0,0,14.41,11l.78,0a15.84,15.84,0,0,0,14.61-9.59l.13-.33L132.69,168,184,219.31a16,16,0,0,0,22.63,0l12.68-12.68a16,16,0,0,0,0-22.63ZM195.31,208,144,156.69a16,16,0,0,0-26,4.93c0,.11-.09.22-.13.32l-17.65,46L48,48l159.85,52.2-45.95,17.64-.32.13a16,16,0,0,0-4.93,26h0L208,195.31Z"

    // Phosphor filled cursor body polygon (outer boundary)
    readonly property string phosphorFillPath: "M220.49,207.8,207.8,220.49a12,12,0,0,1-17,0l-56.57-56.57L115,214.08l-.13.33A15.84,15.84,0,0,1,100.26,224l-.78,0a15.82,15.82,0,0,1-14.41-11L32.8,52.92A15.95,15.95,0,0,1,52.92,32.8L213,85.07a16,16,0,0,1,1.41,29.8l-.33.13-50.16,19.27,56.57,56.56A12,12,0,0,1,220.49,207.8Z"

    // ---- Open / Close / Toggle Flow ----
    function open() {
        if (root.active) return
        initPosProc.running = true
        root.active = true
        showAnim.stop()
        hideAnim.stop()
        showAnim.start()
        notifyProc.command = ["bash", "-c", "omarchy-notification-send 'X-Ray Cursor: Active' -t 1200 2>/dev/null || true"]
        notifyProc.running = true
    }

    function close() {
        if (!root.active) return
        root.active = false
        showAnim.stop()
        hideAnim.stop()
        hideAnim.start()
        notifyProc.command = ["bash", "-c", "omarchy-notification-send 'X-Ray Cursor: Inactive' -t 1200 2>/dev/null || true"]
        notifyProc.running = true
    }

    function toggle() {
        if (root.active) {
            root.close()
        } else {
            root.open()
        }
    }

    // ---- Snappy Micro-Animations ----
    ParallelAnimation {
        id: showAnim
        NumberAnimation {
            target: root
            property: "cursorScaleFactor"
            from: root.cursorScaleFactor
            to: 1.0
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "cursorOpacity"
            from: root.cursorOpacity
            to: 1.0
            duration: 100
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: hideAnim
        NumberAnimation {
            target: root
            property: "cursorScaleFactor"
            from: root.cursorScaleFactor
            to: 0.85
            duration: 90
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root
            property: "cursorOpacity"
            from: root.cursorOpacity
            to: 0.0
            duration: 80
            easing.type: Easing.InCubic
        }
    }

    // ---- Initial Position & Notification Helpers ----
    Process {
        id: initPosProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = String(text || "").trim()
                var parts = raw.split(",")
                if (parts.length === 2) {
                    var x = parseFloat(parts[0].trim())
                    var y = parseFloat(parts[1].trim())
                    if (!isNaN(x) && !isNaN(y)) {
                        root.cursorX = x
                        root.cursorY = y
                    }
                }
            }
        }
    }

    Process {
        id: notifyProc
    }

    // ---- Live Cursor Tracking Process (120Hz Polling) ----
    Process {
        id: trackerProc
        running: root.active
        command: [
            "bash", "-c",
            "if [ -x \"$HOME/.config/quickshell/bin/cursor-tracker\" ]; then " +
            "  exec \"$HOME/.config/quickshell/bin/cursor-tracker\"; " +
            "else " +
            "  exec python3 -u \"$HOME/.config/quickshell/bin/cursor-tracker.py\"; " +
            "fi"
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                var raw = String(data || "").trim()
                if (!raw) return
                var parts = raw.split(" ")
                if (parts.length >= 2) {
                    var gx = parseFloat(parts[0])
                    var gy = parseFloat(parts[1])
                    if (!isNaN(gx) && !isNaN(gy)) {
                        root.cursorX = gx
                        root.cursorY = gy
                    }
                }
            }
        }
    }

    // ---- Global Shortcuts & IPC Handlers ----
    GlobalShortcut {
        name: "cursorXRayToggle"
        description: "Toggle Cursor X-Ray mode"
        appid: "quickshell"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "cursorXRay"
        function toggle(): string { root.toggle(); return root.active ? "on" : "off" }
        function open(): string { root.open(); return "ok" }
        function close(): string { root.close(); return "ok" }
        function status(): string { return root.active ? "on" : "off" }
        function getPos(): string { return root.cursorX + " " + root.cursorY }
        function setSize(val: real): string { if (val >= 16 && val <= 64) { root.cursorSize = val; return "ok" }; return "invalid" }
        function ping(): string { return "ok" }
    }

    // ---- Fullscreen Layershell Overlay per Screen ----
    BarVariants {
        everyScreen: true

        PanelWindow {
            id: panel
            required property var modelData

            visible: root.active || hideAnim.running
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"
            WlrLayershell.namespace: "cursor-xray-main"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            // Completely empty input region ensures 100% click-through
            mask: Region {}

            readonly property real screenX: modelData ? modelData.x : 0
            readonly property real screenY: modelData ? modelData.y : 0
            readonly property real screenW: modelData ? modelData.width : 1920
            readonly property real screenH: modelData ? modelData.height : 1080

            readonly property real localX: root.cursorX - screenX
            readonly property real localY: root.cursorY - screenY

            readonly property bool cursorOnScreen: localX >= -root.cursorSize &&
                                                   localX <= (screenW + root.cursorSize) &&
                                                   localY >= -root.cursorSize &&
                                                   localY <= (screenH + root.cursorSize)

            // Cursor Container: Tip positioned exactly at (localX, localY)
            Item {
                id: cursorContainer
                x: panel.localX - (root.vectorTipX * root.cursorScale)
                y: panel.localY - (root.vectorTipY * root.cursorScale)
                width: 256 * root.cursorScale
                height: 256 * root.cursorScale

                visible: panel.cursorOnScreen && (root.cursorOpacity > 0.01)
                opacity: root.cursorOpacity
                scale: root.cursorScaleFactor
                transformOrigin: Item.TopLeft

                // 1. Subtle drop-shadow for contrast over bright backgrounds
                Shape {
                    x: 1.2
                    y: 1.2
                    width: 256
                    height: 256
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale {
                        origin.x: 0
                        origin.y: 0
                        xScale: root.cursorScale
                        yScale: root.cursorScale
                    }

                    ShapePath {
                        fillColor: Qt.rgba(0, 0, 0, 0.40)
                        strokeWidth: 0
                        PathSvg {
                            path: root.phosphorFillPath
                        }
                    }
                }

                // 2. Main Phosphor X-Ray Cursor Shape
                Shape {
                    width: 256
                    height: 256
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale {
                        origin.x: 0
                        origin.y: 0
                        xScale: root.cursorScale
                        yScale: root.cursorScale
                    }

                    // Interior X-Ray Aperture (alpha > 0.005 triggers Hyprland xray blur)
                    ShapePath {
                        fillColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                        strokeWidth: 0
                        PathSvg {
                            path: root.phosphorFillPath
                        }
                    }

                    // Phosphor Cursor Signature Outline in Theme Accent
                    ShapePath {
                        fillColor: Theme.accent
                        strokeWidth: 0
                        PathSvg {
                            path: root.phosphorOutlinePath
                        }
                    }
                }
            }
        }
    }
}
