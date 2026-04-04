import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: pill
    property string label: "OFFLINE"
    property bool active: false
    property color activeColor: "#7BFF4F"
    property color inactiveColor: "#FF4D6D"

    radius: 14
    implicitHeight: 28
    implicitWidth: row.implicitWidth + 18
    color: active ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.16)
                  : Qt.rgba(inactiveColor.r, inactiveColor.g, inactiveColor.b, 0.16)
    border.width: 1
    border.color: active ? activeColor : inactiveColor

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Rectangle {
            width: 7
            height: 7
            radius: 3.5
            color: active ? activeColor : inactiveColor
        }
        Text {
            text: pill.label
            color: active ? activeColor : inactiveColor
            font.bold: true
            font.pixelSize: 10
            font.letterSpacing: 0.8
        }
    }
}
