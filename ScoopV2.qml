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
    property color color: Theme.bgc
    property real radius: Theme.rounding
    property real cornerRadius: Theme.rounding

    // Minimum geometric constraints to ensure curves have ample room and never get cut or inverted
    readonly property real minWidth: {
        switch (position) {
            case "topCenter":
            case "bottomCenter":
                return 4 * radius;
            case "centerLeft":
            case "centerRight":
                return 2 * radius;
            default: // topLeft, topRight, bottomLeft, bottomRight
                return Math.max(3 * radius, radius + cornerRadius);
        }
    }

    readonly property real minHeight: {
        switch (position) {
            case "centerLeft":
            case "centerRight":
                return 4 * radius;
            case "topCenter":
            case "bottomCenter":
                return 2 * radius;
            default: // topLeft, topRight, bottomLeft, bottomRight
                return Math.max(3 * radius, radius + cornerRadius);
        }
    }

    // Effective dimensions (guaranteed >= minWidth & minHeight to prevent curve crossover)
    readonly property real effectiveWidth: Math.max(width, minWidth)
    readonly property real effectiveHeight: Math.max(height, minHeight)
    readonly property real r: radius
    readonly property real cr: cornerRadius

    implicitWidth: minWidth
    implicitHeight: minHeight

    // 1. TOP LEFT
    Shape {
        id: shapeTopLeft
        visible: root.position === "topLeft"
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: root.color
            startX: 0
            startY: 0

            PathLine {
                x: root.effectiveWidth
                y: 0
            }
            PathArc {
                x: root.effectiveWidth - root.r
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.r - root.cr
            }
            PathArc {
                x: root.effectiveWidth - root.r - root.cr
                y: root.effectiveHeight - root.r
                radiusX: root.cr
                radiusY: root.cr
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: 0
                y: root.effectiveHeight
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
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: root.color
            startX: 0
            startY: 0

            PathArc {
                x: root.r
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: 2 * root.r
                y: root.effectiveHeight
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - 2 * root.r
                y: root.effectiveHeight
            }
            PathArc {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.r
            }
            PathArc {
                x: root.effectiveWidth
                y: 0
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }

    // 3. TOP RIGHT
    Shape {
        id: shapeTopRight
        visible: root.position === "topRight"
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: root.color
            startX: 0
            startY: 0

            PathArc {
                x: root.r
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r
                y: root.effectiveHeight - root.r - root.cr
            }
            PathArc {
                x: root.r + root.cr
                y: root.effectiveHeight - root.r
                radiusX: root.cr
                radiusY: root.cr
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: root.effectiveWidth
                y: root.effectiveHeight
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth
                y: 0
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }

    // 4. CENTER RIGHT
    Shape {
        id: shapeCenterRight
        visible: root.position === "centerRight"
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: root.color
            startX: root.effectiveWidth
            startY: 0

            PathArc {
                x: root.effectiveWidth - root.r
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r
                y: root.r
            }
            PathArc {
                x: 0
                y: 2 * root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: 0
                y: root.effectiveHeight - 2 * root.r
            }
            PathArc {
                x: root.r
                y: root.effectiveHeight - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: root.effectiveWidth
                y: root.effectiveHeight
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth
                y: 0
            }
        }
    }

    // 5. BOTTOM RIGHT
    Shape {
        id: shapeBottomRight
        visible: root.position === "bottomRight"
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: root.color
            startX: root.effectiveWidth
            startY: root.effectiveHeight

            PathLine {
                x: 0
                y: root.effectiveHeight
            }
            PathArc {
                x: root.r
                y: root.effectiveHeight - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.r
                y: root.r + root.cr
            }
            PathArc {
                x: root.r + root.cr
                y: root.r
                radiusX: root.cr
                radiusY: root.cr
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.r
            }
            PathArc {
                x: root.effectiveWidth
                y: 0
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
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: root.color
            startX: 0
            startY: root.effectiveHeight

            PathArc {
                x: root.r
                y: root.effectiveHeight - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.r
                y: root.r
            }
            PathArc {
                x: 2 * root.r
                y: 0
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - 2 * root.r
                y: 0
            }
            PathArc {
                x: root.effectiveWidth - root.r
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: root.effectiveWidth
                y: root.effectiveHeight
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: 0
                y: root.effectiveHeight
            }
        }
    }

    // 7. BOTTOM LEFT
    Shape {
        id: shapeBottomLeft
        visible: root.position === "bottomLeft"
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: root.color
            startX: 0
            startY: 0

            PathArc {
                x: root.r
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r - root.cr
                y: root.r
            }
            PathArc {
                x: root.effectiveWidth - root.r
                y: root.r + root.cr
                radiusX: root.cr
                radiusY: root.cr
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: root.effectiveWidth
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
                y: 0
            }
        }
    }

    // 8. CENTER LEFT
    Shape {
        id: shapeCenterLeft
        visible: root.position === "centerLeft"
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: root.color
            startX: 0
            startY: 0

            PathArc {
                x: root.r
                y: root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: root.effectiveWidth - root.r
                y: root.r
            }
            PathArc {
                x: root.effectiveWidth
                y: 2 * root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.effectiveWidth
                y: root.effectiveHeight - 2 * root.r
            }
            PathArc {
                x: root.effectiveWidth - root.r
                y: root.effectiveHeight - root.r
                radiusX: root.r
                radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.r
                y: root.effectiveHeight - root.r
            }
            PathArc {
                x: 0
                y: root.effectiveHeight
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
}
