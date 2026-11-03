import Quickshell
import QtQuick
import QtQuick.Shapes

Item{
    id: root
    readonly property var scoopPosition: {
        "topLeft": 0,
        "topRight": 1,
        "bottomLeft": 2,
        "bottomRight": 3
    }

    required property int cornerPosition
    property color bgColor: Theme.bgc
    // The screen corners follow the rounding; decorative uses (the
    // Bluetooth header glyph) pin a fixed size instead.
    property real size: Theme.rounding

    implicitWidth: size
    implicitHeight: size

    transform: Scale {
        origin.x: implicitWidth / 2 
        origin.y: implicitHeight / 2 
        xScale: cornerPosition === scoopPosition.bottomRight || cornerPosition === scoopPosition.topRight ? -1 : 1
        yScale: cornerPosition === scoopPosition.topLeft || cornerPosition === scoopPosition.topRight ? -1 : 1
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0
            fillColor: root.bgColor
            startX: 0; startY: 0
            PathArc { x: root.size; y: root.size; radiusX: root.size; radiusY: root.size }
            PathLine { x: root.size; y: 0 }
        }
    }
}