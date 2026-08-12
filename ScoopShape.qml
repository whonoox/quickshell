import Quickshell
import QtQuick
import QtQuick.Shapes

Item{
    readonly property var scoopPosition: {
        "topLeft": 0,
        "topRight": 1,
        "bottomLeft": 2,
        "bottomRight": 3
    }
    
    required property int cornerPosition
    required property real size
    property color color: 'black'

    implicitWidth: size
    implicitHeight: size

    transform: Scale {
        origin.x: width / 2 
        origin.y: height / 2 
        xScale: cornerPosition === scoopPosition.bottomRight || cornerPosition === scoopPosition.topRight ? -1 : 1
        yScale: cornerPosition === scoopPosition.topLeft || cornerPosition === scoopPosition.topRight ? -1 : 1
    }

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: 0
            fillColor: color
            startX: 0; startY: 0
            PathArc { x: size; y: size; radiusX: size; radiusY: size}
            PathLine { x: size; y: 0 }
        }
    }
}