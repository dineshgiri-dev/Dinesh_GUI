import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt5Compat.GraphicalEffects

Item {
    id: loginPage
    anchors.fill: parent
    Theme { id: theme }

    // Properties mapped from main theme
    property color surface: theme.bg1
    property color surfaceLight: theme.glass0
    property color primary: theme.neon
    property color primaryLight: theme.cyan
    property color textPrimary: theme.textPrimary
    property color textSecondary: theme.textSecondary
    property color borderColor: theme.glassStroke
    property color danger: theme.danger
    property bool useCustomWindowButtons: true
    
    signal loginSuccessful()
    
    Rectangle {
        anchors.fill: parent
        color: surface

        gradient: Gradient {
            GradientStop { position: 0.0; color: theme.bg1 }
            GradientStop { position: 1.0; color: theme.bg0 }
        }

        Row {
            visible: loginPage.useCustomWindowButtons
            spacing: 8
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.rightMargin: 12

            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: minBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10)
                border.color: "#A2A5CF"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                MouseArea {
                    id: minBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (loginPage.Window.window) {
                            loginPage.Window.window.showMinimized()
                        }
                    }
                }
            }

            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: closeBtnMouse.containsMouse ? Qt.rgba(239/255, 68/255, 68/255, 0.9) : Qt.rgba(239/255, 68/255, 68/255, 0.75)
                border.color: "#ef4444"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                }
                MouseArea {
                    id: closeBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (loginPage.Window.window) {
                            loginPage.Window.window.close()
                        }
                    }
                }
            }
        }
        
        // Left Side Content
        Item {
            anchors.left: parent.left
            anchors.right: loginRectContainer.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                
                Rectangle {
                    width: 100
                    height: 100
                    radius: 25
                    color: theme.glass1
                    Layout.alignment: Qt.AlignHCenter
                    
                    Text {
                        anchors.centerIn: parent
                    text: "A"
                        font.pixelSize: 60
                    font.bold: true
                    color: theme.neon
                    }
                }
                
                Text {
                    text: "SMART AUTONOMOUS\nROBOT"
                    color: textPrimary
                    font.pixelSize: 32
                    font.bold: true
                    font.letterSpacing: 2.0
                    horizontalAlignment: Text.AlignHCenter
                    Layout.alignment: Qt.AlignHCenter
                }
                
                Text {
                    text: "Autonomous Operations Console"
                    color: theme.cyan
                    font.pixelSize: 18
                    font.letterSpacing: 1.5
                    Layout.alignment: Qt.AlignHCenter
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    spacing: 8


                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: "transparent"
                        border.color: "transparent"
                        border.width: 1

                        Image {
                            anchors.fill: parent
                            anchors.margins: 8
                            source: "qrc:/icons/DRDO.png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: "transparent"
                        border.color: "transparent"
                        border.width: 1

                        Image {
                            anchors.fill: parent
                            anchors.margins: 8
                            source: "qrc:/icons/Jeanuvs-logo.png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            }
                    }
                }
            }
        }
        
        // Right side center container
        Item {
            id: loginRectContainer
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.45
            
            // The rectangle on the right side center
            Rectangle {
                anchors.centerIn: parent
                width: 400
                height: 480
                radius: 16
                color: surfaceLight
                border.color: borderColor
                border.width: 1
                
                layer.enabled: true
                layer.effect: DropShadow {
                    transparentBorder: true
                    radius: 24
                    samples: 48
                    color: "#60000000"
                    verticalOffset: 8
                }
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 40
                    spacing: 24
                    
                    Text {
                        text: "Welcome Back"
                        color: textPrimary
                        font.pixelSize: 28
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 5
                    }
                    
                    Text {
                        text: "Please sign in to continue"
                        color: textSecondary
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 15
                    }
                    
                    Text {
                        id: errorMsg
                        text: "Invalid credentials"
                        color: danger
                        font.pixelSize: 12
                        visible: false
                        Layout.alignment: Qt.AlignHCenter
                    }
                    
                    // Username block
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        Text {
                            text: "USERNAME"
                            color: textSecondary
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            color: surface
                            radius: 8
                            border.color: usernameInput.activeFocus ? theme.cyan : borderColor
                            border.width: 1
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12
                                
                                Text {
                                    text: "👤"
                                    color: textSecondary
                                    font.pixelSize: 16
                                }
                                
                                TextField {
                                    id: usernameInput
                                    Layout.fillWidth: true
                                    color: textPrimary
                                    font.pixelSize: 14
                                    placeholderText: "Enter username"
                                    background: null
                                    
                                    onAccepted: passwordInput.forceActiveFocus()
                                }
                            }
                        }
                    }
                    
                    // Password block
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        Text {
                            text: "PASSWORD"
                            color: textSecondary
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            color: surface
                            radius: 8
                            border.color: passwordInput.activeFocus ? theme.cyan : borderColor
                            border.width: 1
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12
                                
                                Text {
                                    text: "🔒"
                                    color: textSecondary
                                    font.pixelSize: 16
                                }
                                
                                TextField {
                                    id: passwordInput
                                    Layout.fillWidth: true
                                    color: textPrimary
                                    font.pixelSize: 14
                                    placeholderText: "Enter password"
                                    background: null
                                    echoMode: TextInput.Password
                                    
                                    onAccepted: loginButtonMouseArea.clicked(null)
                                }

                                Text {
                                    text: passwordInput.echoMode === TextInput.Password ? "👁️" : "👁️‍🗨️"
                                    color: textSecondary
                                    font.pixelSize: 16
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (passwordInput.echoMode === TextInput.Password) {
                                                passwordInput.echoMode = TextInput.Normal
                                            } else {
                                                passwordInput.echoMode = TextInput.Password
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    Item { Layout.fillHeight: true }
                    
                    // Login button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 48
                        radius: 8
                        color: primary
                        scale: loginButtonMouseArea.containsMouse ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 150 } }
                        
                        Text {
                            anchors.centerIn: parent
                            text: "LOGIN"
                            color: "#071015"
                            font.bold: true
                            font.pixelSize: 14
                            font.letterSpacing: 1.5
                        }
                        
                        MouseArea { id: loginButtonMouseArea
                            anchors.fill: parent                            
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: parent.color = primaryLight
                            onExited: parent.color = primary
                            onClicked: {
                                if (usernameInput.text === "12" && passwordInput.text === "12") {
                                    errorMsg.visible = false
                                    loginSuccessful()
                                } else {
                                    errorMsg.visible = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
