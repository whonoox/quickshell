import Quickshell
import QtQuick

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

    // Border attributes (X-Ray native compositor border: near-zero alpha for 0-blur see-through)
    property real borderWidth: 4
    property color borderColor: Qt.rgba(0, 0, 0, 0.01)

    // Base minimum geometric constraints for single shape curve integrity
    readonly property real baseMinWidth: {
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

    readonly property real baseMinHeight: {
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

    // Effective border width
    readonly property real d: Math.max(0, borderWidth)

    // Minimum geometric constraints expanded to ensure inner shape also never breaks
    readonly property real minWidth: {
        var extra = (position === "topCenter" || position === "bottomCenter") ? 2 * d : d;
        return baseMinWidth + extra;
    }

    readonly property real minHeight: {
        var extra = (position === "centerLeft" || position === "centerRight") ? 2 * d : d;
        return baseMinHeight + extra;
    }

    // Effective dimensions (guaranteed >= minWidth & minHeight to prevent curve crossover)
    readonly property real effectiveWidth: Math.max(width, minWidth)
    readonly property real effectiveHeight: Math.max(height, minHeight)

    implicitWidth: minWidth
    implicitHeight: minHeight

    // Single-vector contour with stroked X-Ray border:
    // Sized to the full panel dimensions so the MSAA layer FBO covers the complete [0, W] x [0, H] area.
    // The path within ScoopContour applies borderWidth insets on non-screen edges, and the centered stroke
    // (width: 2 * borderWidth) extends outward to land flush at the bounding box with zero clipping.
    ScoopContour {
        id: innerShape
        anchors.fill: parent
        position: root.position
        radius: root.radius
        cornerRadius: root.cornerRadius
        fillColor: root.color
        borderColor: root.borderColor
        borderWidth: root.d
    }
}
