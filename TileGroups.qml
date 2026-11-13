import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import "TileTree.js" as TileTree

// Tile groups: a dot on each split between tiled windows stands for the
// windows on both sides of that split, the branch of the dwindle tree it
// cuts. Hovering a dot picks that group:
//
//   - Super+Shift+arrows then moves the whole group one step, trading
//     places with the neighbour on that side, instead of swapping the
//     active window.
//   - Dragging the dot onto a window, or onto another dot, trades the two.
//   - Clicking the dot keeps the group picked until it is clicked again,
//     so the pointer can move away while the keys do the work.
//
// A hover pick lasts exactly as long as the hover, except that a group moved
// with the keys stays picked until Super is released: the move slides its
// dot out from under the pointer. Dwindle itself cannot move a branch, so
// the moves are done by QsTiles.apply in hypr/quickshell-islands.lua, which
// rebuilds the workspace into the new tree in one go.
Scope {
    id: root

    // The picked group: the sorted addresses of its windows, which stay the
    // same wherever the group moves to.
    property string armedKey: ""
    property bool pinned: false

    // The dot under the pointer, tracked even while it cannot pick.
    property string hoverKey: ""

    // A key move happened and Super is still down.
    property bool held: false

    // A rebuild slides every dot to a new place, and a dot that slides under
    // a resting pointer must not take over the pick.
    property double settleUntil: 0

    readonly property int hitSize: 26
    readonly property int dotSize: 6
    readonly property int pickedDotSize: 10

    // The window corners and see-through, read from Hyprland so the filled
    // gaps of a picked group match its windows.
    property int rounding: 16
    property real windowOpacity: 0.87

    // What fills a picked group's inner gaps: the windows' own background,
    // so the seams disappear and the group reads as one piece.
    readonly property color fuseColor: Theme.background

    Process {
        id: lookProcess
        running: true
        command: ["sh", "-c", "hyprctl -j getoption decoration:rounding; hyprctl -j getoption decoration:active_opacity"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var text = String(this.text || "")
                var r = text.match(/"int":\s*(\d+)/)
                var o = text.match(/"float":\s*([\d.]+)/)
                if (r)
                    root.rounding = Number(r[1])
                if (o)
                    root.windowOpacity = Number(o[1])
            }
        }
    }

    // Hyprland's Super+Shift+arrow binds read this to choose between moving
    // the group and swapping the window.
    // Sent on every change rather than only on a flip, so a Hyprland reload
    // (which resets the flag) is caught up by the next hover.
    onArmedKeyChanged: syncArmed()
    Component.onCompleted: syncArmed()

    function syncArmed() {
        Hyprland.dispatch("function() if QsTiles then QsTiles.armed = " + (armedKey !== "") + " end end")
    }

    function enter(key) {
        hoverKey = key
        if (held || pinned || Date.now() < settleUntil)
            return
        armedKey = key
    }

    function leave(key) {
        if (hoverKey === key)
            hoverKey = ""
        if (held || pinned)
            return
        armedKey = ""
    }

    function togglePin(key) {
        if (pinned && armedKey === key) {
            pinned = false
            armedKey = hoverKey
        } else {
            armedKey = key
            pinned = true
        }
    }

    function disarm() {
        pinned = false
        held = false
        armedKey = ""
    }

    // Super came up after a key move: the move is over, so the pick is too,
    // even with a dot under the pointer. Moving onto a dot picks again.
    function holdEnd() {
        if (!held)
            return
        held = false
        if (!pinned)
            armedKey = ""
    }

    // The tree last built on each workspace, so the next look at the
    // windows reads them the same way where the geometry alone is ambiguous.
    property var builtTrees: ({})

    function apply(wsId, tree) {
        if (!tree)
            return
        settleUntil = Date.now() + 450
        builtTrees[wsId] = tree
        Hyprland.dispatch("function() if QsTiles then QsTiles.apply(" + TileTree.lua(tree) + ") end end")
        refreshTimer.restart()
    }

    function move(dir) {
        var outs = screens.instances
        for (var i = 0; i < outs.length; i++) {
            if (outs[i].moveGroup(armedKey, dir)) {
                held = true
                return
            }
        }
        // The group is gone (closed, moved away): behave as the plain bind.
        disarm()
        Hyprland.dispatch("hl.dsp.window.swap({ direction = \"" + dir + "\" })")
    }

    Timer {
        id: refreshTimer
        interval: 40
        onTriggered: {
            Hyprland.refreshMonitors()
            Hyprland.refreshToplevels()
        }
    }

    Connections {
        target: Hyprland

        // A pick is not dropped on a workspace or monitor change: hovering a
        // dot on another monitor moves the focus there, which would drop the
        // pick it just made. A pick whose group is no longer on screen falls
        // back to the plain window swap in move().
        function onRawEvent(event) {
            switch (event.name) {
            case "configreloaded":
                // A Hyprland reload resets QsTiles.armed.
                root.syncArmed()
                lookProcess.running = true
                break
            case "workspacev2":
            case "focusedmonv2":
            case "activespecialv2":
            case "moveworkspacev2":
            case "openwindow":
            case "closewindow":
            case "movewindowv2":
            case "changefloatingmode":
            case "fullscreen":
            case "togglegroup":
            case "moveintogroup":
            case "moveoutofgroup":
            case "activewindowv2":
                refreshTimer.restart()
                break
            }
        }
    }

    // Sent by Hyprland when Super comes up after a key move.
    GlobalShortcut {
        name: "tilesHoldEnd"
        description: "End a tile group key move"
        appid: "quickshell"
        onPressed: root.holdEnd()
    }

    GlobalShortcut {
        name: "tilesMoveLeft"
        description: "Move the picked tile group left"
        appid: "quickshell"
        onPressed: root.move("l")
    }

    GlobalShortcut {
        name: "tilesMoveRight"
        description: "Move the picked tile group right"
        appid: "quickshell"
        onPressed: root.move("r")
    }

    GlobalShortcut {
        name: "tilesMoveUp"
        description: "Move the picked tile group up"
        appid: "quickshell"
        onPressed: root.move("u")
    }

    GlobalShortcut {
        name: "tilesMoveDown"
        description: "Move the picked tile group down"
        appid: "quickshell"
        onPressed: root.move("d")
    }

    Variants {
        id: screens
        model: Quickshell.screens

        Scope {
            id: output
            required property var modelData

            function moveGroup(key, dir) {
                return panel.moveGroup(key, dir)
            }

        PanelWindow {
            id: panel
            readonly property var modelData: output.modelData
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell-tile-groups"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            visible: handles.length > 0

            // Only the dots take the pointer, except during a drag, when the
            // whole screen does so the drop lands here and not in a window.
            mask: dragging ? fullRegion : dotsRegion
            property Region fullRegion: Region { item: fullArea }
            // A square around each dot. Regions created on the fly are not
            // picked up reliably, so there is a fixed set of 24 whose
            // positions follow the dots; unused ones are empty.
            property Region dotsRegion: Region {
                Region { x: panel.slotX(0); y: panel.slotY(0); width: panel.slotSize(0); height: panel.slotSize(0) }
                Region { x: panel.slotX(1); y: panel.slotY(1); width: panel.slotSize(1); height: panel.slotSize(1) }
                Region { x: panel.slotX(2); y: panel.slotY(2); width: panel.slotSize(2); height: panel.slotSize(2) }
                Region { x: panel.slotX(3); y: panel.slotY(3); width: panel.slotSize(3); height: panel.slotSize(3) }
                Region { x: panel.slotX(4); y: panel.slotY(4); width: panel.slotSize(4); height: panel.slotSize(4) }
                Region { x: panel.slotX(5); y: panel.slotY(5); width: panel.slotSize(5); height: panel.slotSize(5) }
                Region { x: panel.slotX(6); y: panel.slotY(6); width: panel.slotSize(6); height: panel.slotSize(6) }
                Region { x: panel.slotX(7); y: panel.slotY(7); width: panel.slotSize(7); height: panel.slotSize(7) }
                Region { x: panel.slotX(8); y: panel.slotY(8); width: panel.slotSize(8); height: panel.slotSize(8) }
                Region { x: panel.slotX(9); y: panel.slotY(9); width: panel.slotSize(9); height: panel.slotSize(9) }
                Region { x: panel.slotX(10); y: panel.slotY(10); width: panel.slotSize(10); height: panel.slotSize(10) }
                Region { x: panel.slotX(11); y: panel.slotY(11); width: panel.slotSize(11); height: panel.slotSize(11) }
                Region { x: panel.slotX(12); y: panel.slotY(12); width: panel.slotSize(12); height: panel.slotSize(12) }
                Region { x: panel.slotX(13); y: panel.slotY(13); width: panel.slotSize(13); height: panel.slotSize(13) }
                Region { x: panel.slotX(14); y: panel.slotY(14); width: panel.slotSize(14); height: panel.slotSize(14) }
                Region { x: panel.slotX(15); y: panel.slotY(15); width: panel.slotSize(15); height: panel.slotSize(15) }
                Region { x: panel.slotX(16); y: panel.slotY(16); width: panel.slotSize(16); height: panel.slotSize(16) }
                Region { x: panel.slotX(17); y: panel.slotY(17); width: panel.slotSize(17); height: panel.slotSize(17) }
                Region { x: panel.slotX(18); y: panel.slotY(18); width: panel.slotSize(18); height: panel.slotSize(18) }
                Region { x: panel.slotX(19); y: panel.slotY(19); width: panel.slotSize(19); height: panel.slotSize(19) }
                Region { x: panel.slotX(20); y: panel.slotY(20); width: panel.slotSize(20); height: panel.slotSize(20) }
                Region { x: panel.slotX(21); y: panel.slotY(21); width: panel.slotSize(21); height: panel.slotSize(21) }
                Region { x: panel.slotX(22); y: panel.slotY(22); width: panel.slotSize(22); height: panel.slotSize(22) }
                Region { x: panel.slotX(23); y: panel.slotY(23); width: panel.slotSize(23); height: panel.slotSize(23) }
            }

            function slotX(i) {
                return i < handles.length ? Math.round(handles[i].x - root.hitSize / 2) : 0
            }
            function slotY(i) {
                return i < handles.length ? Math.round(handles[i].y - root.hitSize / 2) : 0
            }
            function slotSize(i) {
                return i < handles.length ? root.hitSize : 0
            }

            property var tree: null
            property int workspaceId: -1
            property var handles: []
            property string handleSig: ""

            property bool dragging: false
            property string dragKey: ""

            // The picked group drawn as one piece, see TileTree.fusion.
            readonly property string pickedKey: dragging ? dragKey : root.armedKey
            readonly property var fusion: {
                var n = pickedKey && tree ? TileTree.find(tree, pickedKey) : null
                return n && !TileTree.isLeaf(n) ? TileTree.fusion(n, root.rounding) : null
            }
            // Off while the windows slide to new places, so the filled gaps
            // don't show ahead of them.
            property bool fuseReady: true

            Timer {
                id: fuseTimer
                interval: 380
                onTriggered: panel.fuseReady = true
            }
            property point dragPoint: Qt.point(0, 0)
            property var dropNode: null

            readonly property var hyprMonitor: Hyprland.monitorFor(modelData)

            // The tiled windows on this screen's workspace, in screen
            // coordinates. Nothing when a group can't be moved here: a
            // fullscreen window, a tabbed group, a special workspace on top,
            // or too few windows for any split but the whole screen.
            readonly property string snapshot: {
                var mon = hyprMonitor
                if (!mon || !mon.activeWorkspace)
                    return ""
                var ipc = mon.lastIpcObject || {}
                if (ipc.specialWorkspace && ipc.specialWorkspace.id)
                    return ""
                var ox = ipc.x !== undefined ? ipc.x : modelData.x
                var oy = ipc.y !== undefined ? ipc.y : modelData.y
                var wsId = mon.activeWorkspace.id
                workspaceId = wsId

                var parts = []
                var tops = Hyprland.toplevels.values
                for (var i = 0; i < tops.length; i++) {
                    var o = tops[i].lastIpcObject
                    if (!o || !o.address || !o.workspace || o.workspace.id !== wsId)
                        continue
                    if (o.floating || o.hidden || o.mapped === false)
                        continue
                    if (o.fullscreen)
                        return ""
                    if (o.grouped && o.grouped.length)
                        return ""
                    parts.push(o.address + ":" + (o.at[0] - ox) + "," + (o.at[1] - oy)
                        + "," + o.size[0] + "," + o.size[1])
                }
                parts.sort()
                return parts.length >= 3 ? parts.join(";") : ""
            }

            onSnapshotChanged: recompute()
            Component.onCompleted: recompute()

            function recompute() {
                var wins = []
                if (snapshot) {
                    var parts = snapshot.split(";")
                    for (var i = 0; i < parts.length; i++) {
                        var p = parts[i].split(":")
                        var n = p[1].split(",").map(Number)
                        wins.push({ addr: p[0], x: n[0], y: n[1], w: n[2], h: n[3] })
                    }
                }
                tree = TileTree.build(wins, root.builtTrees[workspaceId])

                var hs = TileTree.handles(tree, root.hitSize)
                var out = []
                var sig = []
                for (var j = 0; j < hs.length; j++) {
                    var r = groupRect(hs[j].node)
                    out.push({ key: hs[j].key, x: hs[j].x, y: hs[j].y, rect: r })
                    sig.push(hs[j].key + "@" + Math.round(hs[j].x) + "," + Math.round(hs[j].y)
                        + "/" + r.x + "," + r.y + "," + r.w + "," + r.h)
                }
                sig = sig.join("|")
                if (sig !== handleSig) {
                    handleSig = sig
                    handles = out
                    fuseReady = false
                    fuseTimer.restart()
                    // The dots are made anew, and a dot destroyed under the
                    // pointer never reports the pointer leaving it.
                    root.hoverKey = ""
                }
            }

            // The windows a group covers, as drawn: its box short of the gaps.
            function groupRect(node) {
                return TileTree.rectOf(node)
            }

            function moveGroup(key, dir) {
                var node = TileTree.find(tree, key)
                if (!node || TileTree.isLeaf(node))
                    return false
                var other = TileTree.neighbour(node, dir)
                if (other)
                    root.apply(workspaceId, TileTree.swapped(tree, node, other))
                return true
            }

            // What a dragged group would trade places with at a point: the
            // group whose dot is there, else the window.
            function dropAt(x, y) {
                var src = TileTree.find(tree, dragKey)
                if (!src)
                    return null
                var target = null
                for (var i = 0; i < handles.length; i++) {
                    var h = handles[i]
                    if (Math.abs(h.x - x) <= root.hitSize / 2 && Math.abs(h.y - y) <= root.hitSize / 2) {
                        target = TileTree.find(tree, h.key)
                        break
                    }
                }
                if (!target)
                    target = TileTree.leafAt(tree, x, y)
                if (!target || !TileTree.swapped(tree, src, target))
                    return null
                return target
            }

            // Window sizes change without any event (a resize by mouse or
            // keys), so the dots are checked again while there are any.
            Timer {
                interval: 1000
                repeat: true
                running: panel.visible && !panel.dragging
                onTriggered: Hyprland.refreshToplevels()
            }

            Item {
                id: fullArea
                anchors.fill: parent

                // Where a drag would land.
                Rectangle {
                    readonly property var r: panel.dropNode
                        ? (TileTree.isLeaf(panel.dropNode) ? panel.dropNode.rect : panel.groupRect(panel.dropNode))
                        : null
                    visible: panel.dragging && r !== null
                    x: r ? r.x : 0
                    y: r ? r.y : 0
                    width: r ? r.w : 0
                    height: r ? r.h : 0
                    radius: Theme.rounding
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                    border.width: 2
                    border.color: Theme.accent
                }

                Repeater {
                    id: dotRepeater
                    model: panel.handles

                    delegate: Item {
                        id: dot
                        required property var modelData
                        readonly property bool picked: root.armedKey === modelData.key
                            || (panel.dragging && panel.dragKey === modelData.key)

                        x: Math.round(modelData.x - width / 2)
                        y: Math.round(modelData.y - height / 2)
                        width: root.hitSize
                        height: root.hitSize

                        Rectangle {
                            anchors.centerIn: parent
                            width: dot.picked || mouse.containsMouse ? root.pickedDotSize : root.dotSize
                            height: width
                            radius: width / 2
                            color: Theme.accent
                            opacity: dot.picked || mouse.containsMouse ? 1 : 0.75
                            border.width: 1
                            border.color: Theme.background

                            Behavior on width {
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: panel.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            property point pressPoint: Qt.point(0, 0)

                            onEntered: root.enter(dot.modelData.key)
                            onExited: root.leave(dot.modelData.key)

                            onPressed: mouse => {
                                pressPoint = Qt.point(mouse.x, mouse.y)
                                panel.dragKey = dot.modelData.key
                            }

                            onPositionChanged: mouse => {
                                if (!pressed)
                                    return
                                var p = mapToItem(fullArea, mouse.x, mouse.y)
                                if (!panel.dragging) {
                                    if (Math.abs(mouse.x - pressPoint.x) + Math.abs(mouse.y - pressPoint.y) < 6)
                                        return
                                    panel.dragging = true
                                    root.armedKey = dot.modelData.key
                                }
                                panel.dragPoint = p
                                panel.dropNode = panel.dropAt(p.x, p.y)
                            }

                            onReleased: mouse => {
                                if (!panel.dragging) {
                                    root.togglePin(dot.modelData.key)
                                    return
                                }
                                var src = TileTree.find(panel.tree, panel.dragKey)
                                var target = panel.dropNode
                                panel.dragging = false
                                panel.dropNode = null
                                if (src && target)
                                    root.apply(panel.workspaceId, TileTree.swapped(panel.tree, src, target))
                                if (!root.pinned)
                                    root.armedKey = root.hoverKey
                            }

                            onCanceled: {
                                panel.dragging = false
                                panel.dropNode = null
                            }
                        }
                    }
                }

                // The dragged dot, under the pointer.
                Rectangle {
                    visible: panel.dragging
                    x: panel.dragPoint.x - width / 2
                    y: panel.dragPoint.y - height / 2
                    width: root.pickedDotSize + 4
                    height: width
                    radius: width / 2
                    color: Theme.accent
                    border.width: 1
                    border.color: Theme.background
                }
            }
        }

        // Under the windows: the picked group's inner gaps filled in the
        // windows' own colour, so the group reads as one piece and the gaps
        // around it stay open. Being underneath, the fill only shows where
        // no window is, and any edge it overshoots is hidden.
        PanelWindow {
            screen: output.modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell-tile-groups-fuse"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}

            visible: panel.visible

            Item {
                id: fused
                anchors.fill: parent

                // Drawn opaque and faded as one layer, so the places where
                // strips and corners overlap are no darker than the rest.
                layer.enabled: true
                opacity: panel.fusion && panel.fuseReady ? root.windowOpacity : 0

                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                // Kept through the fade out, so the fill fades where it was.
                property var shown: null
                readonly property var current: panel.fuseReady ? panel.fusion : null
                onCurrentChanged: if (current) shown = current

                Repeater {
                    model: fused.shown ? fused.shown.strips : []

                    delegate: Rectangle {
                        required property var modelData
                        x: modelData.x
                        y: modelData.y
                        width: modelData.w
                        height: modelData.h
                        color: root.fuseColor
                    }
                }

                // A window corner facing into the group, or one side of a
                // seam's rounded tip: the square at the point short of the
                // round part, drawn for the top left and turned for the
                // others (TileTree.fusion).
                Repeater {
                    model: fused.shown ? fused.shown.corners : []

                    delegate: Shape {
                        id: corner
                        required property var modelData
                        readonly property real r: modelData.r
                        x: modelData.turn === 0 || modelData.turn === 270 ? modelData.x : modelData.x - r
                        y: modelData.turn === 0 || modelData.turn === 90 ? modelData.y : modelData.y - r
                        width: r
                        height: r
                        rotation: modelData.turn
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            fillColor: root.fuseColor
                            strokeWidth: -1
                            startX: 0
                            startY: 0
                            PathLine { x: corner.r; y: 0 }
                            PathArc {
                                x: 0
                                y: corner.r
                                radiusX: corner.r
                                radiusY: corner.r
                                direction: PathArc.Counterclockwise
                            }
                            PathLine { x: 0; y: 0 }
                        }
                    }
                }
            }
        }
        }
    }
}
