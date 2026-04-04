import QtQuick 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: header
    property string title: ""
    property string subtitle: ""
    property color accent: "#31E0FF"

    radius: 10
    color: "#142838"
    border.color: "#2E546D"
    border.width: 1
    implicitHeight: 56

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10
        Rectangle {
            width: 4
            height: 28
            radius: 2
            color: header.accent
        }
        ColumnLayout {
            spacing: 1
            Text {
                text: header.title
                color: "#EAF6FF"
                font.pixelSize: 14
                font.bold: true
            }
            Text {
                visible: subtitle !== ""
                text: header.subtitle
                color: "#8FB0C7"
                font.pixelSize: 10
            }
        }
        Item { Layout.fillWidth: true }
    }
}
