import Quickshell
import QtQuick
import QtQuick.Shapes

Item{
    required property bool leftArc
    required property real size
    implicitWidth: size
    implicitHeight: size

    transform: Scale {
        origin.x: width / 2 
        xScale: leftArc ? 1 : -1
    }

    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: 0
            fillColor: "black"
            startX: 0; startY: 0
            PathArc { x: size; y: size; radiusX: size; radiusY: size}
            PathLine { x: size; y: 0 }
        }
    }
}