import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

BasePage {
    id: teleOpRoot
    Theme { id: theme }
    appRoot: parent.appRoot ? parent.appRoot : (typeof root !== 'undefined' ? root : null)
    
    // Focus handling: allows keyboard controls to work
    focus: true

    property color borderColorTel: appRoot ? appRoot.borderColor : theme.glassStroke
    property color accentColorTel: appRoot ? appRoot.primary : theme.neon
    property color greenColorTel: appRoot ? appRoot.success : theme.neon
    property color redColorTel: appRoot ? appRoot.danger : theme.danger
    property int selectedDeviceId: 0
    property bool isEmergency: typeof mapBridge !== 'undefined' && mapBridge && mapBridge.emergencyActive
    property bool isOffline: typeof mapBridge === 'undefined' || !mapBridge || !mapBridge.isConnected

    property real currentLinVel: 0.0
    property real currentAngVel: 0.0

    title: isEmergency ? "🚨 EMERGENCY MODE - TeleOp Active" : "🕹️ Remote Control - TeleOp"
    showBack: true

    Component.onCompleted: {
        teleOpRoot.forceActiveFocus()
    }

    Timer {
        id: commandTimer
        interval: 500
        repeat: true
        running: false
        onTriggered: {
            if(mapBridge && !isOffline) mapBridge.teleOpMove(selectedDeviceId, teleOpRoot.currentLinVel, teleOpRoot.currentAngVel);
        }
    }

    // Timer to catch camera disconnection
    Timer {
        id: cameraActivityTimer
        interval: 3000
        repeat: false
        onTriggered: {
            teleOpRoot.deviceActive = false;
            depthCameraImage.source = "";
        }
    }

    property bool deviceActive: false

    // Force active focus on click background so keyboard controls always work but TextFields are accessible
    MouseArea { anchors.fill: parent
        z: -1
        onClicked: {
            teleOpRoot.forceActiveFocus()
        }
    }

    content: [
        // ================= MAIN CONTAINER =================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"
            
            ColumnLayout {
                anchors.fill: parent
                spacing: 16
                
                // ================= DEVICE INFO =================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 8
                    color: "#132838"
                    border.color: borderColorTel

                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12
                        Text {
                            text: "Selected Robot: <b>" + selectedDeviceId + "</b>"
                            color: "white"; font.pixelSize: 16; textFormat: Text.StyledText
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 100; height: 32; radius: 6
                            color: isOffline ? redColorTel : greenColorTel
                            Text {
                                anchors.centerIn: parent
                                text: isOffline ? "OFFLINE" : (isEmergency ? "HALTED" : "ONLINE")
                                color: "#f8fafc"; font.bold: true; font.pixelSize: 11
                            }
                        }
                    }
                }

                // ================= MAIN CONTENT =================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 20

            // Left side: Camera View
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: "#132838"
                border.color: borderColorTel
                border.width: 1
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        color: Qt.darker((appRoot ? appRoot.surfaceLight : "#153145"), 1.2)
                        border.color: borderColorTel
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            Text {
                                text: "📷 DEPTH SENSOR FEED"
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: isOffline ? "DISCONNECTED" : "LIVE STREAMING"
                                color: isOffline ? redColorTel : greenColorTel
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        
                        Image {
                            id: depthCameraImage
                            anchors.fill: parent
                            anchors.margins: 0
                            fillMode: Image.PreserveAspectCrop
                            source: ""
                            visible: source !== ""
                            cache: false
                        }

                        Text {
                            anchors.centerIn: parent
                            text: isOffline ? "⚠ No Connection to Depth Camera" : (cameraActivityTimer.running ? "Awaiting Depth Stream..." : "⚠ Camera Disconnected or No Response")
                            color: "#A2A5CF"
                            font.pixelSize: 14
                            visible: depthCameraImage.source == ""
                        }
                    }
                }
            }

            // Right side: Controls
            Rectangle {
                Layout.preferredWidth: 280
                Layout.alignment: Qt.AlignTop
                implicitHeight: rightCol.implicitHeight + 24
                radius: 12
                color: appRoot ? appRoot.surfaceLight : "#153145"
                border.color: borderColorTel
                border.width: 1

                ColumnLayout {
                    id: rightCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 14

                    // Joystick Control Block
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            Text {
                                text: "JOYSTICK CONTROL"
                                color: "white"
                                font.pixelSize: 12
                                font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Rectangle {
                                id: joyContainer
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                                color: "transparent"

                                Rectangle {
                                    id: joyOuter
                                    width: Math.min(160, Math.min(joyContainer.width, joyContainer.height))
                                    height: width
                                    radius: width / 2; 
                                    color: "#0E0C25"
                                    border.color: "#A2A5CF"
                                    border.width: 2
                                    anchors.centerIn: parent

                                    Rectangle {
                                        id: joystickHandle
                                        width: joyOuter.width * 0.3
                                        height: width
                                        radius: width / 2; 
                                        color: isOffline ? "#A2A5CF" : accentColorTel
                                        x: (joyOuter.width - width) / 2
                                        y: (joyOuter.height - height) / 2
                                    }

                                    // Timer for continuous command sending while holding
                                    Timer {
                                        id: commandTimer_joystick
                                        interval: 50          // 20 Hz – adjust to your needs
                                        repeat: true
                                        onTriggered: {
                                            if (!teleOpRoot.isOffline && teleOpRoot.mapBridge) {
                                                teleOpRoot.mapBridge.teleOpMove(teleOpRoot.selectedDeviceId,
                                                                          teleOpRoot.currentLinVel,
                                                                          teleOpRoot.currentAngVel);
                                            }
                                        }
                                    }

                                    // Mouse area covering the whole joystick
                                    MouseArea {
                                        anchors.fill: parent
                                        preventStealing: true

                                        function updatePosition(mouse) {
                                            if (teleOpRoot.isOffline) return; // prevent movement when offline

                                            var maxRadius = (joyOuter.width / 2) - (joystickHandle.width / 2);
                                            var cx = joyOuter.width / 2;
                                            var cy = joyOuter.height / 2;
                                            var dx = mouse.x - cx;
                                            var dy = mouse.y - cy;
                                            var dist = Math.sqrt(dx*dx + dy*dy);

                                            if (dist > maxRadius) {
                                                dx = (dx / dist) * maxRadius;
                                                dy = (dy / dist) * maxRadius;
                                            }

                                            joystickHandle.x = cx + dx - (joystickHandle.width / 2);
                                            joystickHandle.y = cy + dy - (joystickHandle.height / 2);

                                            var normX = dx / maxRadius;
                                            var normY = dy / maxRadius;

                                            teleOpRoot.currentLinVel = -normY * 1.0;
                                            teleOpRoot.currentAngVel = -normX * 1.0;

                                            if (!teleOpRoot.isOffline && teleOpRoot.mapBridge) {
                                                teleOpRoot.mapBridge.teleOpMove(teleOpRoot.selectedDeviceId,
                                                                                teleOpRoot.currentLinVel,
                                                                                teleOpRoot.currentAngVel);
                                            }
                                        }

                                        onPressed: (mouse) => {
                                            teleOpRoot.forceActiveFocus();
                                            updatePosition(mouse);
                                            if (!teleOpRoot.isOffline) commandTimer_joystick.start();   // use the correct timer
                                        }

                                        onPositionChanged: (mouse) => {
                                            updatePosition(mouse);
                                        }

                                        onReleased: (mouse) => {
                                            commandTimer_joystick.stop();                               // stop the correct timer
                                            joystickHandle.x = (joyOuter.width - joystickHandle.width) / 2;
                                            joystickHandle.y = (joyOuter.height - joystickHandle.height) / 2;
                                            teleOpRoot.currentLinVel = 0;
                                            teleOpRoot.currentAngVel = 0;
                                            if (!teleOpRoot.isOffline && teleOpRoot.mapBridge) {
                                                teleOpRoot.mapBridge.teleOpMove(teleOpRoot.selectedDeviceId, 0, 0);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Keyboard Instructions
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        radius: 8
                        color: "#0E0C25"
                        border.color: "#A2A5CF"
                        border.width: 1
                        
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 2
                            Text {
                                text: "KEYBOARD COMMANDS (AWD/Arrows)"
                                color: "white"; font.pixelSize: 10; font.bold: true
                                Layout.alignment: Qt.AlignHCenter
                            }
                            RowLayout {
                                spacing: 10
                                Layout.alignment: Qt.AlignHCenter
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "W / ⬆ : Forward"; color: appRoot ? appRoot.textSecondary : "#A2A5CF"; font.pixelSize: 10; font.bold: true }
                                    Text { text: "S / ⬇ : Reverse"; color: appRoot ? appRoot.textSecondary : "#A2A5CF"; font.pixelSize: 10; font.bold: true }
                                }
                                ColumnLayout {
                                    spacing: 2
                                    Text { text: "A / ⬅ : Rotate Left"; color: appRoot ? appRoot.textSecondary : "#A2A5CF"; font.pixelSize: 10; font.bold: true }
                                    Text { text: "D / ➡ : Rotate Right"; color: appRoot ? appRoot.textSecondary : "#A2A5CF"; font.pixelSize: 10; font.bold: true }
                                }
                            }
                        }
                    }

                    // // Sensor Toggles
                    // Rectangle {
                    //     Layout.fillWidth: true
                    //     Layout.preferredHeight: 50
                    //     radius: 8
                    //     color: "#0E0C25"
                    //     border.color: "#A2A5CF"
                    //     border.width: 1
                        
                    //     RowLayout {
                    //         anchors.fill: parent
                    //         anchors.margins: 4
                    //         spacing: 4
                            
                    //         Button { Layout.fillWidth: true
                    //             Layout.fillHeight: true
                    //             scale: hovered ? 1.05 : 1.0
                    //             Behavior on scale { NumberAnimation { duration: 150 } }
                    //             HoverHandler { cursorShape: Qt.PointingHandCursor }
                    //             property bool isActive: true
                    //             onClicked: {
                    //                 isActive = !isActive
                    //                 if(mapBridge) mapBridge.updateSensorValue(selectedDeviceId, "2d_lidar", isActive ? 1.0 : 0.0)
                    //             }
                    //             background: Rectangle { radius: 6; color: parent.isActive ? greenColorTel : "#A2A5CF" }
                    //             contentItem: Text { text: "2D Lidar"; color: "white"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; wrapMode: Text.WordWrap }
                    //         }
                    //         Button { Layout.fillWidth: true
                    //             Layout.fillHeight: true
                    //             scale: hovered ? 1.05 : 1.0
                    //             Behavior on scale { NumberAnimation { duration: 150 } }
                    //             HoverHandler { cursorShape: Qt.PointingHandCursor }
                    //             property bool isActive: true
                    //             onClicked: {
                    //                 isActive = !isActive
                    //                 if(mapBridge) mapBridge.updateSensorValue(selectedDeviceId, "3d_lidar", isActive ? 1.0 : 0.0)
                    //             }
                    //             background: Rectangle { radius: 6; color: parent.isActive ? greenColorTel : "#A2A5CF" }
                    //             contentItem: Text { text: "3D Lidar"; color: "white"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; wrapMode: Text.WordWrap }
                    //         }
                    //         Button { Layout.fillWidth: true
                    //             Layout.fillHeight: true
                    //             scale: hovered ? 1.05 : 1.0
                    //             Behavior on scale { NumberAnimation { duration: 150 } }
                    //             HoverHandler { cursorShape: Qt.PointingHandCursor }
                    //             property bool isActive: true
                    //             onClicked: {
                    //                 isActive = !isActive
                    //                 if(mapBridge) mapBridge.updateSensorValue(selectedDeviceId, "depth_camera", isActive ? 1.0 : 0.0)
                    //             }
                    //             background: Rectangle { radius: 6; color: parent.isActive ? greenColorTel : "#A2A5CF" }
                    //             contentItem: Text { text: "Depth/RGB"; color: "white"; font.pixelSize: 10; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; wrapMode: Text.WordWrap }
                    //         }
                    //     }
                    // }

                    // Individual Robot Stop Button
                    Button { Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        scale: hovered ? 1.02 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150 } }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        property bool isStoppedLocally: false
                        onClicked: {
                            isStoppedLocally = !isStoppedLocally;
                            if (isStoppedLocally) {
                                if(mapBridge) mapBridge.stopRobot(selectedDeviceId);
                            } else {
                                if(mapBridge) mapBridge.resumeRobot(selectedDeviceId);
                            }
                        }
                        background: Rectangle {
                            color: parent.hovered
                                   ? Qt.rgba(49/255, 224/255, 255/255, 0.24)
                                   : Qt.rgba(49/255, 224/255, 255/255, 0.12)
                            radius: 8
                            border.color: parent.isStoppedLocally ? "#7BFF4F" : "#FF4D6D"
                            border.width: 1
                        }
                        contentItem: Text {
                            text: parent.isStoppedLocally ? "RESUME ROBOT " + selectedDeviceId : "STOP ROBOT " + selectedDeviceId
                            color: parent.isStoppedLocally ? "#7BFF4F" : "#FF9AAE"; font.bold: true; font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            } // Closes Right-side Rectangle
        } // Closes Main RowLayout
        } // Closes ColumnLayout
        } // Closes Container Rectangle
    ] // Closes content list

    Connections {
        target: typeof mapBridge !== 'undefined' ? mapBridge : null
        ignoreUnknownSignals: true
        // Color: /ugv_0N/camera/<pos>/image_raw
        // Depth: /ugv_0N/camera/<pos>/depth/image_raw
        function onImageReceived(topic, base64) {
            var t = topic ? topic.toLowerCase() : "";
            var idPad = selectedDeviceId < 10 ? "ugv_0" + selectedDeviceId : "ugv_" + selectedDeviceId;
            if (t.indexOf("/" + idPad + "/") === -1) return;
            // Must be a camera image_raw or depth/image_raw topic
            if (t.indexOf("/image_raw") === -1) return;

            if (!base64 || base64.length === 0) return;
            var mime = base64.startsWith("/9j/") ? "image/jpeg"
                     : base64.startsWith("iVB")  ? "image/png"
                     : "";
            if (mime === "") return;
            
            teleOpRoot.deviceActive = true;
            cameraActivityTimer.restart();
            depthCameraImage.source = "data:" + mime + ";base64," + base64;
        }
    }

    // Keyboard Control Logic
    Keys.onPressed: (event) => {
        if (isOffline) return;
        event.accepted = true;
        if (event.isAutoRepeat) return;

        var handled = false;
        if (event.key === Qt.Key_Up || event.key === Qt.Key_W) {
            teleOpRoot.currentLinVel = 1.0;
            teleOpRoot.currentAngVel = 0;
            handled = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
            teleOpRoot.currentLinVel = -1.0;
            teleOpRoot.currentAngVel = 0;
            handled = true;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_A) {
            teleOpRoot.currentLinVel = 0;
            teleOpRoot.currentAngVel = 1.0;
            handled = true;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) {
            teleOpRoot.currentLinVel = 0;
            teleOpRoot.currentAngVel = -1.0;
            handled = true;
        } else if (event.key === Qt.Key_Space) {
            isEmergency ? mapBridge.emergencyResume() : mapBridge.emergencyStop();
        } else {
            event.accepted = false;
        }

        if (handled && mapBridge) {
            mapBridge.teleOpMove(selectedDeviceId, teleOpRoot.currentLinVel, teleOpRoot.currentAngVel);
            commandTimer.start();
        }
    }

    Keys.onReleased: (event) => {
        if (!event.isAutoRepeat) {
            teleOpRoot.currentLinVel = 0.0;
            teleOpRoot.currentAngVel = 0.0;
            commandTimer.stop();
            if (mapBridge) mapBridge.teleOpMove(selectedDeviceId, 0, 0);
        }
    }
}
