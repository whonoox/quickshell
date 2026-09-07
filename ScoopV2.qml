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
    property color borderColor: Qt.rgba(0, 0, 0, 0.02)

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

    // Inner Overlay Offsets (0px on screen-touching edges, d px on interior/curved edges)
    readonly property real innerX: {
        switch (position) {
            case "topLeft":
            case "bottomLeft":
            case "centerLeft":
                return 0; // Touches left screen edge
            default:
                return d; // Non-left positions inset from left
        }
    }

    readonly property real innerY: {
        switch (position) {
            case "topLeft":
            case "topCenter":
            case "topRight":
                return 0; // Touches top screen edge
            default:
                return d; // Non-top positions inset from top
        }
    }

    readonly property real innerWidth: {
        switch (position) {
            case "topCenter":
            case "bottomCenter":
                return Math.max(0, effectiveWidth - 2 * d);
            default:
                return Math.max(0, effectiveWidth - d);
        }
    }

    readonly property real innerHeight: {
        switch (position) {
            case "centerLeft":
            case "centerRight":
                return Math.max(0, effectiveHeight - 2 * d);
            default:
                return Math.max(0, effectiveHeight - d);
        }
    }

    // Layer 1: Outer Shape (Underlay)
    // Sized to full effective dimensions.
    // When borderWidth > 0, filled with translucent borderColor (alpha ~0.28).
    // Hyprland X-Ray blur then blurs the desktop wallpaper through this layer.
    // When borderWidth === 0, filled with solid root.color.
    ScoopContour {
        id: outerShape
        x: 0
        y: 0
        width: root.effectiveWidth
        height: root.effectiveHeight
        position: root.position
        radius: root.radius
        cornerRadius: root.cornerRadius
        fillColor: root.d > 0 ? root.borderColor : root.color
    }

    // Layer 2: Inner Shape (Overlay)
    // Inset by borderWidth on non-screen edges, flush on screen edges.
    // Filled with opaque root.color (Theme.bgc, alpha 1.0).
    // Drawn on top of the underlay, leaving a precise 4px border band of the underlay exposed.
    ScoopContour {
        id: innerShape
        visible: root.d > 0
        x: root.innerX
        y: root.innerY
        width: root.innerWidth
        height: root.innerHeight
        position: root.position
        radius: root.radius
        cornerRadius: root.cornerRadius
        fillColor: root.color
    }
}
