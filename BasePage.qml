import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root
    Theme { id: theme }
    property alias content: contentColumn.data
    property alias headerContent: headerRightSlot.data
    property string title: ""
    property bool showBack: false
    property var appRoot: null

    radius: 12
    color: appRoot ? appRoot.surface : theme.bg1
    border.color: appRoot ? appRoot.borderColor : theme.glassStroke
    border.width: 1

    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 16

        // ================= HEADER =================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            radius: 12
            color: Qt.rgba(theme.glass0.r, theme.glass0.g, theme.glass0.b, 0.8)
            border.color: root.border.color
            border.width: 1

            // Subtle gradient
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: theme.glass0 }
                GradientStop { position: 1.0; color: theme.bg2 }
            }

            // Optional DropShadow for depth
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 8
                samples: 16
                color: "#aa000000"
                verticalOffset: 2
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 16

                // High-End Premium Back Button
                Rectangle {
                    id: backBtn
                    width: 40; height: 40; radius: 10
                    color: backMouse.containsMouse ? "#1D3A50" : "transparent"
                    border.color: backMouse.containsMouse ? theme.neon : (appRoot ? appRoot.borderColor : theme.glassStroke)
                    scale: backMouse.containsMouse ? 1.1 : 1.0; Behavior on scale { NumberAnimation { duration: 150 } }
                    Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 22; color: backMouse.containsMouse ? theme.neon : theme.textPrimary }
                    MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: appRoot.currentScreen = "main" }
                }

                // Title
                Text {
                    text: root.title
                    color: theme.textPrimary
                    font.pixelSize: 20
                    font.bold: true
                    font.letterSpacing: 1.0
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                // Dynamic Header action slot (for screen-specific buttons)
                RowLayout {
                    id: headerRightSlot
                    spacing: 12
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                }
            }
        }

        // ================= MAIN CONTENT =================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                spacing: 12
            }
        }
    }
}
