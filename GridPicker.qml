import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import QtQuick

// The zooming grid the wallpaper and theme pickers share.
//
// The grid opens zoomed into the background on screen and pulls back to
// the cards; choosing a card zooms into it until it fills the screen, and
// the picker steps aside once the real background underneath matches it.
// Cancelling zooms back into the card the picker opened on, wherever the
// selection has moved since.
//
// A card shows its thumbnail in the grid. The image a zoom lands on is the
// card's still (or, for the card the picker opened on, its openStill),
// decoded at screen size so the hand-off is seamless. The theme picker
// uses this to zoom into the background a theme lands on rather than its
// preview.
//
// The picker owns the data and the side effects: it fills in the list on
// openRequested and calls present(), and it applies the choice on
// applyRequested and calls applyFinished(). Each item is
//   { name, label, thumbnail, still, openStill, path, isAnimated }
// where only thumbnail is required.
Scope {
    id: root

    property string namespace: "quickshell-grid-picker"

    signal openRequested()
    signal applyRequested(var item, int index)

    // ---- Geometry ----
    property real monitorWidth: (Quickshell.screens && Quickshell.screens.length > 0 && Quickshell.screens[0].width > 0) ? Quickshell.screens[0].width : 1920
    property real monitorHeight: (Quickshell.screens && Quickshell.screens.length > 0 && Quickshell.screens[0].height > 0) ? Quickshell.screens[0].height : 1080

    readonly property real cardWidth: 440
    readonly property real cardHeight: 248
    readonly property real colGap: 36
    readonly property real rowGap: 28
    readonly property real colStep: cardWidth + colGap
    readonly property real rowStep: cardHeight + rowGap
    readonly property real staggerY: (cardHeight + rowGap) / 2
    readonly property real baseY: 70
    readonly property real centerMargin: Math.max(0, (monitorWidth - (3 * cardWidth + 2 * colGap)) / 2)
    readonly property real cardRadius: 10

    readonly property int revealDuration: 300
    readonly property int applyDuration: 300
    readonly property int cancelDuration: 260

    // ---- State ----
    // closed     nothing on screen
    // loading    the picker is gathering its list
    // preparing  the list is in; waiting for the opening still and the
    //            card thumbnails to decode
    // revealing  zooming out of the background into the grid
    // browsing   the grid is interactive
    // applying   zooming into the chosen card while the picker applies it
    // dismissing zooming back into the card the picker opened on
    property string phase: "closed"
    readonly property bool shown: phase === "revealing" || phase === "browsing" || phase === "applying" || phase === "dismissing"
    // The window is mapped, empty and transparent, from the moment the
    // picker is asked to open: mapping a layer surface takes a few frames,
    // which would otherwise swallow the start of the reveal.
    readonly property bool mapped: phase !== "closed"
    readonly property bool busy: phase !== "closed" && phase !== "browsing"

    property var items: []
    property int selectedIndex: 0
    property int initialIndex: 0

    // The card the camera zooms into, and the image it lands on. During a
    // cancel this is the card the picker opened on, not the selected one.
    property int focusIndex: 0
    property string focusStill: ""

    // 0 = grid, 1 = the focus card fills the screen.
    property real zoomProgress: 0.0
    property real cameraScale: 1.0
    property real targetTx: 0.0
    property real targetTy: 0.0

    property real scrollX: 0.0
    Behavior on scrollX {
        enabled: root.phase === "browsing"
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // Hover selects only once the pointer has moved since the grid opened.
    // Cards slide under a cursor that is standing still as the grid
    // reveals, and Qt reports that as the cursor entering them, which
    // would steal the selection from the card the grid opened on.
    property bool pointerArmed: false
    property point pointerOrigin: Qt.point(-1, -1)

    function pointerMoved(scenePos) {
        if (pointerArmed) return true
        if (pointerOrigin.x < 0) {
            pointerOrigin = scenePos
            return false
        }
        if (Math.abs(scenePos.x - pointerOrigin.x) + Math.abs(scenePos.y - pointerOrigin.y) > 4) pointerArmed = true
        return pointerArmed
    }

    property bool focusReady: false
    property int thumbsPending: 0

    property bool zoomDone: false
    property bool applyDone: false
    property int settleMs: 0

    readonly property var selectedItem: (items && selectedIndex >= 0 && selectedIndex < items.length) ? items[selectedIndex] : null
    readonly property string selectedName: selectedItem ? (selectedItem.label || selectedItem.name || "") : ""

    function fileUrl(path) {
        if (!path) return ""
        return path.indexOf("file://") === 0 ? path : "file://" + path
    }

    // ---- Layout math ----
    function cardX(index) {
        return centerMargin + Math.floor(index / 3) * colStep
    }

    function cardY(index) {
        var col = Math.floor(index / 3)
        return baseY + (col % 2 === 1 ? staggerY : 0) + (index % 3) * rowStep
    }

    function scrollFor(index) {
        var col = Math.floor(index / 3)
        return col > 1 ? (col - 1) * colStep : 0
    }

    // Points the camera at a card as it sits on screen at the current scroll.
    function aimCamera(index) {
        if (!items || index < 0 || index >= items.length) {
            cameraScale = 1.0
            targetTx = 0.0
            targetTy = 0.0
            return
        }
        var px = cardX(index) - scrollX + cardWidth / 2
        var py = cardY(index) + cardHeight / 2
        // Cover the screen: the card is a hair wider than 16:9.
        var scale = Math.max(monitorWidth / cardWidth, monitorHeight / cardHeight)
        cameraScale = scale
        targetTx = monitorWidth / 2 - px * scale
        targetTy = monitorHeight / 2 - py * scale
    }

    // ---- Navigation ----
    function moveVertical(dir) {
        if (phase !== "browsing" || !items.length) return
        var row = selectedIndex % 3 + dir
        var next = Math.floor(selectedIndex / 3) * 3 + row
        if (row >= 0 && row <= 2 && next < items.length) selectedIndex = next
    }

    function moveHorizontal(dir) {
        if (phase !== "browsing" || !items.length) return
        var col = Math.floor(selectedIndex / 3) + dir
        if (col < 0 || col >= Math.ceil(items.length / 3)) return
        selectedIndex = Math.min(col * 3 + selectedIndex % 3, items.length - 1)
    }

    onSelectedIndexChanged: if (phase === "browsing") scrollX = scrollFor(selectedIndex)

    // ---- Flow ----
    function open() {
        if (phase !== "closed") return
        phase = "loading"
        openRequested()
    }

    function toggle() {
        if (phase === "browsing") cancel()
        else if (phase === "closed") open()
    }

    // Called by the picker with its list and the card for what is on
    // screen now. The grid appears once that card's still has decoded, so
    // the first frame matches the desktop under it, and the thumbnails
    // with it, so the cards do not pull back empty.
    function present(list, currentIndex) {
        if (phase !== "loading") return
        if (!list || list.length === 0) {
            phase = "closed"
            return
        }
        var idx = Math.max(0, Math.min(currentIndex, list.length - 1))
        zoomAnim.stop()
        // Everything the cards read is set before the cards exist: a
        // thumbnail still in the image cache reports ready as it is created.
        phase = "preparing"
        pointerArmed = false
        pointerOrigin = Qt.point(-1, -1)
        zoomProgress = 1.0
        selectedIndex = idx
        initialIndex = idx
        focusIndex = idx
        focusStill = list[idx].openStill || list[idx].still || ""
        focusReady = !focusStill
        thumbsPending = list.length
        scrollX = scrollFor(idx)
        items = list
        aimCamera(idx)
        prepareTimeout.restart()
        maybeReveal()
    }

    function focusStillReady() {
        focusReady = true
        maybeReveal()
    }

    function thumbSettled() {
        thumbsPending = Math.max(0, thumbsPending - 1)
        maybeReveal()
    }

    function maybeReveal() {
        if (phase === "preparing" && focusReady && thumbsPending === 0) beginReveal()
    }

    function beginReveal() {
        prepareTimeout.stop()
        phase = "revealing"
        runZoom(0.0, revealDuration, Easing.OutCubic)
    }

    function applySelected() {
        if (phase !== "browsing" || !selectedItem) return
        focusIndex = selectedIndex
        focusStill = selectedItem.still || ""
        aimCamera(selectedIndex)
        zoomDone = false
        applyDone = false
        phase = "applying"
        applyRequested(selectedItem, selectedIndex)
        runZoom(1.0, applyDuration, Easing.InOutCubic)
    }

    // Called by the picker once the choice is on screen underneath. settle
    // is how long the background still needs to draw, in ms.
    function applyFinished(settle) {
        if (phase !== "applying") return
        settleMs = settle === undefined ? 180 : settle
        applyDone = true
        maybeClose()
    }

    function cancel() {
        if (phase !== "browsing") return
        focusIndex = initialIndex
        var item = items[initialIndex]
        focusStill = item ? (item.openStill || item.still || "") : ""
        aimCamera(initialIndex)
        phase = "dismissing"
        runZoom(1.0, cancelDuration, Easing.InOutCubic)
    }

    function maybeClose() {
        if (phase === "applying" && zoomDone && applyDone) settleTimer.restart()
    }

    function close() {
        settleTimer.stop()
        prepareTimeout.stop()
        zoomAnim.stop()
        phase = "closed"
        zoomDone = false
        applyDone = false
    }

    function runZoom(to, duration, easing) {
        zoomAnim.stop()
        zoomAnim.from = zoomProgress
        zoomAnim.to = to
        zoomAnim.duration = duration
        zoomAnim.easing.type = easing
        zoomAnim.start()
    }

    NumberAnimation {
        id: zoomAnim
        target: root
        property: "zoomProgress"
        onFinished: {
            if (root.phase === "revealing") {
                root.phase = "browsing"
            } else if (root.phase === "applying") {
                root.zoomDone = true
                root.maybeClose()
            } else if (root.phase === "dismissing") {
                root.close()
            }
        }
    }

    // An image that never decodes must not keep the picker from opening.
    Timer {
        id: prepareTimeout
        interval: 600
        onTriggered: if (root.phase === "preparing") root.beginReveal()
    }

    Timer {
        id: settleTimer
        interval: root.settleMs
        onTriggered: root.close()
    }

    // ---- Window ----
    BarVariants {
        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            visible: root.mapped
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: root.namespace
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: root.mapped ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // Clicks pass through until the grid is on screen.
            mask: root.shown ? null : emptyRegion

            Region { id: emptyRegion }

            onWidthChanged: if (width > 0) root.monitorWidth = width
            onHeightChanged: if (height > 0) root.monitorHeight = height

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                visible: root.shown

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.cancel()
                }
            }

            Item {
                id: keyFilter
                anchors.fill: parent
                focus: true

                Component.onCompleted: forceActiveFocus()

                Connections {
                    target: root
                    function onPhaseChanged() {
                        if (root.shown) keyFilter.forceActiveFocus()
                    }
                }

                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    event.accepted = true
                    if (root.phase !== "browsing") return
                    switch (event.key) {
                    case Qt.Key_Escape: root.cancel(); break
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space: root.applySelected(); break
                    case Qt.Key_Down: root.moveVertical(1); break
                    case Qt.Key_Up: root.moveVertical(-1); break
                    case Qt.Key_Right: root.moveHorizontal(1); break
                    case Qt.Key_Left: root.moveHorizontal(-1); break
                    default: event.accepted = false
                    }
                }
            }

            // The camera: scales and moves the ribbon so the focus card
            // fills the screen at zoomProgress 1.
            Item {
                id: camera
                anchors.fill: parent
                // Laid out and decoding while preparing, but not drawn.
                opacity: root.shown ? 1 : 0

                transform: [
                    Scale {
                        xScale: 1.0 + (root.cameraScale - 1.0) * root.zoomProgress
                        yScale: 1.0 + (root.cameraScale - 1.0) * root.zoomProgress
                    },
                    Translate {
                        x: root.targetTx * root.zoomProgress
                        y: root.targetTy * root.zoomProgress
                    }
                ]

                Item {
                    id: ribbon
                    x: -root.scrollX
                    width: parent.width
                    height: parent.height

                    Repeater {
                        model: root.items

                        delegate: Item {
                            id: card
                            required property int index
                            required property var modelData

                            readonly property bool isSelected: index === root.selectedIndex
                            readonly property bool isFocus: index === root.focusIndex
                            readonly property bool isAnimated: !!(modelData && modelData.isAnimated)
                            // While zoomed, only the focus card is drawn at
                            // screen size; the rest fade out of the way.
                            readonly property bool zoomed: isFocus && root.zoomProgress > 0

                            x: root.cardX(index)
                            y: root.cardY(index)
                            width: root.cardWidth
                            height: root.cardHeight
                            z: isFocus ? 20 : (isSelected ? 10 : 1)
                            opacity: (isFocus || root.zoomProgress === 0) ? 1.0 : Math.max(0.0, 1.0 - root.zoomProgress * 2.5)
                            visible: opacity > 0

                            readonly property real radius: root.cardRadius * (1.0 - (isFocus ? root.zoomProgress : 0))

                            Rectangle {
                                id: mask
                                anchors.fill: parent
                                radius: card.radius
                                color: "black"
                                visible: false
                                layer.enabled: true
                            }

                            Item {
                                id: imageLayer
                                anchors.fill: parent
                                layer.enabled: true
                                layer.smooth: true
                                // Rendered at its on-screen size while zoomed,
                                // or the still would be drawn at card size and
                                // blown up.
                                layer.textureSize: card.zoomed
                                    ? Qt.size(Math.ceil(card.width * root.cameraScale), Math.ceil(card.height * root.cameraScale))
                                    : Qt.size(0, 0)
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: mask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#121420"
                                }

                                Image {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    source: card.modelData ? root.fileUrl(card.modelData.thumbnail || card.modelData.path) : ""
                                    asynchronous: true
                                    sourceSize: Qt.size(880, 496)
                                    property bool counted: false
                                    onStatusChanged: {
                                        if (!counted && (status === Image.Ready || status === Image.Error)) {
                                            counted = true
                                            root.thumbSettled()
                                        }
                                    }
                                    visible: !(card.isAnimated && card.isSelected && root.phase === "browsing")
                                }

                                AnimatedImage {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    source: card.isAnimated && card.isSelected ? root.fileUrl(card.modelData.path) : ""
                                    asynchronous: true
                                    playing: root.phase === "browsing"
                                    visible: card.isAnimated && card.isSelected && root.phase === "browsing"
                                }

                                // The still the zoom lands on, faded in as the
                                // card grows, so the zoom carries the card's
                                // thumbnail into the real background.
                                Image {
                                    id: still
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    source: card.isFocus ? root.fileUrl(root.focusStill) : ""
                                    asynchronous: true
                                    cache: false
                                    sourceSize: Qt.size(root.monitorWidth, root.monitorHeight)
                                    opacity: Math.min(1.0, root.zoomProgress * 1.6)
                                    visible: status === Image.Ready && opacity > 0

                                    onStatusChanged: {
                                        if (card.isFocus && status !== Image.Loading && status !== Image.Null)
                                            root.focusStillReady()
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: card.radius
                                color: "transparent"
                                border.width: (card.isSelected ? 3 : 1) * (card.isFocus ? 1.0 - root.zoomProgress : 1.0)
                                border.color: card.isSelected ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                                visible: border.width > 0.01
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: function(mouse) {
                                    if (root.pointerMoved(mapToItem(null, mouse.x, mouse.y)) && root.phase === "browsing")
                                        root.selectedIndex = card.index
                                }
                                onClicked: {
                                    if (root.phase !== "browsing") return
                                    root.selectedIndex = card.index
                                    root.applySelected()
                                }
                            }
                        }
                    }
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 26
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.selectedName.toUpperCase()
                font.family: Theme.brandFont
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 2
                color: Theme.fgc
                opacity: Math.max(0.0, (1.0 - root.zoomProgress) * 0.75)
                visible: opacity > 0.01 && root.selectedName.length > 0
            }
        }
    }
}
