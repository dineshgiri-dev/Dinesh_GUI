import QtQuick 2.15

Rectangle {
    Theme { id: theme }
    property string text: ""
    visible: false
    width: tooltipText.width + 16
    height: tooltipText.height + 8
    radius: 4
    color: "#12293A"
    border.color: theme.glassStroke
    border.width: 1
    z: 10000

    Text {
        id: tooltipText
        anchors.centerIn: parent
        text: parent.text
        color: theme.textPrimary
        font.pixelSize: 11
    }
}
