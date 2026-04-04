import QtQuick 2.15
import Qt5Compat.GraphicalEffects

Rectangle {
    id: card
    property alias content: slot.data
    property color tintA: "#1B364C"
    property color tintB: "#102231"
    property color stroke: "#2E546D"
    property int cornerRadius: 12
    property bool elevated: true

    radius: cornerRadius
    border.color: stroke
    border.width: 1
    gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0.0; color: tintA }
        GradientStop { position: 1.0; color: tintB }
    }

    layer.enabled: elevated
    layer.effect: DropShadow {
        transparentBorder: true
        radius: 14
        samples: 24
        verticalOffset: 3
        color: "#50000000"
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
