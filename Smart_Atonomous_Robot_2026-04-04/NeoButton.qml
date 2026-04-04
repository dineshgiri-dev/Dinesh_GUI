import QtQuick 2.15
import QtQuick.Controls 2.15

Button {
    id: control
    property color baseColor: "#31E0FF"
    property color textColor: "#31E0FF"
    property color borderColor: "#31E0FF"
    property color disabledColor: "#2D3D49"

    implicitHeight: 42
    implicitWidth: 128
    hoverEnabled: true

    contentItem: Text {
        text: control.text
        color: control.enabled ? control.textColor : "#8CA1B1"
        font.bold: true
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 10
        border.width: 1
        border.color: control.enabled ? control.borderColor : "#486072"
        color: !control.enabled ? control.disabledColor
                               : (control.pressed ? Qt.rgba(49/255, 224/255, 255/255, 0.30)
                                                  : (control.hovered ? Qt.rgba(49/255, 224/255, 255/255, 0.24)
                                                                     : Qt.rgba(49/255, 224/255, 255/255, 0.12)))
    }
}
