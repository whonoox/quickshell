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

    // Effective dimensions and radii
    readonly property real effectiveWidth: width
    readonly property real effectiveHeight: height
    readonly property real r: radius
    readonly property real cr: cornerRadius
    readonly property real d: borderWidth

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
            startX: 0
            startY: 0

            PathLine {
                x: root.effectiveWidth - root.d
                y: 0
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
            PathLine {
                x: 0
                y: 0
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
            startX: root.d
            startY: 0

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
            PathLine {
                x: root.d
                y: 0
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
            startX: root.d
            startY: 0

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
            PathLine {
                x: root.effectiveWidth
                y: 0
            }
            PathLine {
                x: root.d
                y: 0
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
            startX: root.effectiveWidth
            startY: root.d

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
            PathLine {
                x: root.effectiveWidth
                y: root.d
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
            startX: root.effectiveWidth
            startY: root.effectiveHeight

            PathLine {
                x: root.d
                y: root.effectiveHeight
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
            PathLine {
                x: root.effectiveWidth
                y: root.effectiveHeight
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
            startX: root.d
            startY: root.effectiveHeight

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
            PathLine {
                x: root.d
                y: root.effectiveHeight
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
            startX: 0
            startY: root.d

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
            PathLine {
                x: 0
                y: root.effectiveHeight
            }
            PathLine {
                x: 0
                y: root.d
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
            startX: 0
            startY: root.d

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
            PathLine {
                x: 0
                y: root.d
            }
        }
    }
}
