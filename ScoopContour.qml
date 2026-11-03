import Quickshell
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    // Position preset:
    // "topLeft" | "topCenter" | "topRight" | "centerRight" |
    // "bottomRight" | "bottomCenter" | "bottomLeft" | "centerLeft"
    property string position: "topLeft"

    // Visual attributes
    property color fillColor: Theme.bgc
    property color borderColor: Qt.rgba(0, 0, 0, 0.01)
    property real borderWidth: Theme.borderWidth
    property real radius: Theme.rounding
    property real cornerRadius: Theme.rounding
    // Each flare meets the screen edge tangentially, so on its own its
    // border would taper to a hairline there. Instead the outline carries
    // on past the tangent point and turns off-screen through a convex arc
    // of this radius. Everything beyond the screen edge is clipped away;
    // what remains on screen is the border continuing a little way along
    // the edge as a gap-sized strip with a rounded end. Over tiled windows
    // that strip lies in the real window gap, so the old look is unchanged,
    // and over a fullscreen window the border ends softly instead of
    // sharply. The strip reaches Theme.scoopCapOverhang past the item
    // bounds along the screen edge; panels with tight windows reserve it.
    property real capRadius: Theme.scoopCapRadius

    // Effective dimensions and radii
    readonly property real effectiveWidth: width
    readonly property real effectiveHeight: height
    readonly property real r: radius
    readonly property real cr: cornerRadius
    readonly property real d: borderWidth
    // Kept at least d so the off-screen closing edges keep their whole
    // stroke off-screen too.
    readonly property real c: Math.max(capRadius, borderWidth)

    // 1. TOP LEFT
    Shape {
        id: shapeTopLeft
        visible: root.position === "topLeft"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.borderWidth * 2
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            fillColor: root.fillColor
            startX: -root.c
            startY: -root.c

            PathLine {
                x: root.effectiveWidth - root.d + root.c
                y: -root.c
            }
            PathArc {
                x: root.effectiveWidth - root.d
                y: 0
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.effectiveWidth - root.d - root.r
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.d - root.r
                y: root.effectiveHeight - root.d - root.r - root.cr
            }
            PathArc {
                x: root.effectiveWidth - root.d - root.r - root.cr
                y: root.effectiveHeight - root.d - root.r
                radiusX: root.cr
                radiusY: root.cr
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r
                y: root.effectiveHeight - root.d - root.r
            }
            PathArc {
                x: 0
                y: root.effectiveHeight - root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathArc {
                x: -root.c
                y: root.effectiveHeight - root.d + root.c
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathLine {
                x: -root.c
                y: -root.c
            }
        }
    }

    // 2. TOP CENTER
    Shape {
        id: shapeTopCenter
        visible: root.position === "topCenter"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.borderWidth * 2
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            fillColor: root.fillColor
            startX: root.d - root.c
            startY: -root.c

            PathArc {
                x: root.d
                y: 0
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Counterclockwise
            }
            PathArc {
                x: root.r + root.d
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r + root.d
                y: root.effectiveHeight - root.d - root.r
            }
            PathArc {
                x: 2 * root.r + root.d
                y: root.effectiveHeight - root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - 2 * root.r - root.d
                y: root.effectiveHeight - root.d
            }
            PathArc {
                x: root.effectiveWidth - root.r - root.d
                y: root.effectiveHeight - root.d - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r - root.d
                y: root.r
            }
            PathArc {
                x: root.effectiveWidth - root.d
                y: 0
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.effectiveWidth - root.d + root.c
                y: -root.c
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.d - root.c
                y: -root.c
            }
        }
    }

    // 3. TOP RIGHT
    Shape {
        id: shapeTopRight
        visible: root.position === "topRight"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.borderWidth * 2
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            fillColor: root.fillColor
            startX: root.d - root.c
            startY: -root.c

            PathArc {
                x: root.d
                y: 0
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Counterclockwise
            }
            PathArc {
                x: root.r + root.d
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r + root.d
                y: root.effectiveHeight - root.d - root.r - root.cr
            }
            PathArc {
                x: root.r + root.d + root.cr
                y: root.effectiveHeight - root.d - root.r
                radiusX: root.cr
                radiusY: root.cr
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.d - root.r
            }
            PathArc {
                x: root.effectiveWidth
                y: root.effectiveHeight - root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.effectiveWidth + root.c
                y: root.effectiveHeight - root.d + root.c
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth + root.c
                y: -root.c
            }
            PathLine {
                x: root.d - root.c
                y: -root.c
            }
        }
    }

    // 4. CENTER RIGHT
    Shape {
        id: shapeCenterRight
        visible: root.position === "centerRight"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.borderWidth * 2
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            fillColor: root.fillColor
            startX: root.effectiveWidth + root.c
            startY: root.d - root.c

            PathArc {
                x: root.effectiveWidth
                y: root.d
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Counterclockwise
            }
            PathArc {
                x: root.effectiveWidth - root.r
                y: root.r + root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r + root.d
                y: root.r + root.d
            }
            PathArc {
                x: root.d
                y: 2 * root.r + root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.d
                y: root.effectiveHeight - 2 * root.r - root.d
            }
            PathArc {
                x: root.r + root.d
                y: root.effectiveHeight - root.r - root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.r - root.d
            }
            PathArc {
                x: root.effectiveWidth
                y: root.effectiveHeight - root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.effectiveWidth + root.c
                y: root.effectiveHeight - root.d + root.c
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth + root.c
                y: root.d - root.c
            }
        }
    }

    // 5. BOTTOM RIGHT
    Shape {
        id: shapeBottomRight
        visible: root.position === "bottomRight"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.borderWidth * 2
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            fillColor: root.fillColor
            startX: root.effectiveWidth + root.c
            startY: root.effectiveHeight + root.c

            PathLine {
                x: root.d - root.c
                y: root.effectiveHeight + root.c
            }
            PathArc {
                x: root.d
                y: root.effectiveHeight
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.r + root.d
                y: root.effectiveHeight - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.r + root.d
                y: root.d + root.r + root.cr
            }
            PathArc {
                x: root.r + root.d + root.cr
                y: root.d + root.r
                radiusX: root.cr
                radiusY: root.cr
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.d + root.r
            }
            PathArc {
                x: root.effectiveWidth
                y: root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathArc {
                x: root.effectiveWidth + root.c
                y: root.d - root.c
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth + root.c
                y: root.effectiveHeight + root.c
            }
        }
    }

    // 6. BOTTOM CENTER
    Shape {
        id: shapeBottomCenter
        visible: root.position === "bottomCenter"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.borderWidth * 2
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            fillColor: root.fillColor
            startX: root.d - root.c
            startY: root.effectiveHeight + root.c

            PathArc {
                x: root.d
                y: root.effectiveHeight
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.r + root.d
                y: root.effectiveHeight - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.r + root.d
                y: root.d + root.r
            }
            PathArc {
                x: 2 * root.r + root.d
                y: root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - 2 * root.r - root.d
                y: root.d
            }
            PathArc {
                x: root.effectiveWidth - root.r - root.d
                y: root.d + root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r - root.d
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: root.effectiveWidth - root.d
                y: root.effectiveHeight
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathArc {
                x: root.effectiveWidth - root.d + root.c
                y: root.effectiveHeight + root.c
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.d - root.c
                y: root.effectiveHeight + root.c
            }
        }
    }

    // 7. BOTTOM LEFT
    Shape {
        id: shapeBottomLeft
        visible: root.position === "bottomLeft"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.borderWidth * 2
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            fillColor: root.fillColor
            startX: -root.c
            startY: root.d - root.c

            PathArc {
                x: 0
                y: root.d
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.r
                y: root.d + root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.d - root.r - root.cr
                y: root.d + root.r
            }
            PathArc {
                x: root.effectiveWidth - root.d - root.r
                y: root.d + root.r + root.cr
                radiusX: root.cr
                radiusY: root.cr
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - root.d - root.r
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: root.effectiveWidth - root.d
                y: root.effectiveHeight
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathArc {
                x: root.effectiveWidth - root.d + root.c
                y: root.effectiveHeight + root.c
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathLine {
                x: -root.c
                y: root.effectiveHeight + root.c
            }
            PathLine {
                x: -root.c
                y: root.d - root.c
            }
        }
    }

    // 8. CENTER LEFT
    Shape {
        id: shapeCenterLeft
        visible: root.position === "centerLeft"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: root.borderWidth * 2
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            fillColor: root.fillColor
            startX: -root.c
            startY: root.d - root.c

            PathArc {
                x: 0
                y: root.d
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.r
                y: root.d + root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.d - root.r
                y: root.d + root.r
            }
            PathArc {
                x: root.effectiveWidth - root.d
                y: root.d + 2 * root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - root.d
                y: root.effectiveHeight - root.d - 2 * root.r
            }
            PathArc {
                x: root.effectiveWidth - root.d - root.r
                y: root.effectiveHeight - root.d - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r
                y: root.effectiveHeight - root.d - root.r
            }
            PathArc {
                x: 0
                y: root.effectiveHeight - root.d
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathArc {
                x: -root.c
                y: root.effectiveHeight - root.d + root.c
                radiusX: root.c
                radiusY: root.c
                direction: PathArc.Clockwise
            }
            PathLine {
                x: -root.c
                y: root.d - root.c
            }
        }
    }
}
