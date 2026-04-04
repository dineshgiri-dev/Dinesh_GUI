import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

Rectangle {
    id: statusBlockRoot
    Theme { id: theme }

    property int deviceId: 0
    property bool isBridgeConnected: (typeof mapBridge !== 'undefined' && mapBridge) ? mapBridge.isConnected : false
    // Per-device: only true when we have received status for this deviceId (not just bridge connected)
    property bool deviceConnected: false
    property bool deviceActive: false
    property bool targetFound: false
    property int batteryLevel: 0
    property color borderColor: "#2E546D"
    property color accentColor: "#7BFF4F"
    // show a brief alert when connection is lost
    property bool showOfflineAlert: false
    // Reactive map of { robotId: bool } — updated by onRobotStatusUpdated for ALL robots.
    // Dot colors bind to this so they update immediately when any robot goes online/offline.
    property var swarmOnlineMap: ({})
    // Swarm indications from separate topic: list of { "id": int, "label": string, "active": bool }
    // Bind swarmIndications from topic to override; when empty, shows other robots (R1..R6) with connection from bridge
    property var swarmIndications: []
    // Effective list: topic data if provided, else default other-robot list with labels R1, R2, ...
    property var effectiveSwarmList: {
        var s = swarmIndications
        var did = deviceId
        if (s && s.length > 0) return s
        var list = []
        for (var i = 1; i <= 6; i++)
            if (i !== did) list.push({ id: i, label: "R" + i })
        return list
    }

    onIsBridgeConnectedChanged: {
        if (!isBridgeConnected) {
            // WebSocket dropped — mark everything offline immediately
            deviceConnected  = false;
            deviceActive     = false;
            showOfflineAlert = true;
            alertHideTimer.restart();
            // Clear swarm map so all dots go grey instantly
            swarmOnlineMap = ({});
        }
        // When bridge reconnects we stay offline until the backend sends
        // proper status messages for each device.
    }

    // Improved Font Scaling to prevent overlapping on small sizes
    readonly property real fontScale: Math.max(0.7, Math.min(statusBlockRoot.width / 300, 1.2))

    // Hover state for the whole status block
    property bool blockHovered: statusBlockHover.hovered

    radius: 12
    gradient: Gradient {
        GradientStop { position: 0.0; color: blockHovered ? "#1D3A50" : "#152B3D" }
        GradientStop { position: 1.0; color: blockHovered ? "#142838" : "#0F1F2D" }
    }
    border.color: blockHovered ? accentColor : borderColor
    border.width: 1
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true

    Behavior on border.color { ColorAnimation { duration: 100 } }

    HoverHandler {
        id: statusBlockHover
        margin: 0
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12 * fontScale + 1
        anchors.rightMargin: 12 * fontScale + 1
        anchors.topMargin: 12 * fontScale + 1
        anchors.bottomMargin: 12 * fontScale + 1
        spacing: 6 * fontScale

        // --- TOP SECTION ---
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30 * fontScale

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 8 * fontScale

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: "Device ID - " + deviceId
                    color: theme.textPrimary
                    font.family: "Inter, Roboto, sans-serif"
                    font.pixelSize: Math.max(12, 14 * fontScale)
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 12 * fontScale
                    height: 12 * fontScale
                    radius: 4 * fontScale
                    color: deviceConnected ? "#10b981" : "#ef4444"
                }

                Item { Layout.fillWidth: true }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Math.max(65 * fontScale, teleText.implicitWidth + 12 * fontScale)
                Layout.preferredHeight: 28 * fontScale; radius: 6
                color: teleHover.hovered && deviceConnected ? "#2F6E8A" : (deviceConnected ? "#1F4A63" : "#324452")
                Text { id: teleText; anchors.centerIn: parent; text: "🕹️ Tele-Op"; color: "white"; font.family: "Inter, Roboto, sans-serif"; font.pixelSize: 8 * fontScale; font.bold: true }
                HoverHandler {
                    id: teleHover
                    cursorShape: deviceActive ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: deviceConnected
                    hoverEnabled: true
                    cursorShape: deviceActive ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (typeof root !== 'undefined') {
                             root.currentDeviceId = statusBlockRoot.deviceId
                             root.currentScreen = "teleop"
                        }
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Math.max(60 * fontScale, stopText.implicitWidth + 12 * fontScale)
                Layout.preferredHeight: 28 * fontScale; radius: 14 * fontScale
                color: !deviceConnected ? Qt.rgba(100, 116, 139, 0.15) : (deviceActive ? Qt.rgba(239, 68, 68, 0.15) : Qt.rgba(16, 185, 129, 0.15))
                border.color: !deviceConnected ? "#A2A5CF" : (deviceActive ? "#ef4444" : "#10b981")
                border.width: 1
                opacity: deviceConnected ? 1.0 : 0.5

                Text {
                    id: stopText; anchors.centerIn: parent;
                    text: !deviceConnected ? "⛔ OFFLINE" : (deviceActive ? "⛔ STOP" : "✔ RESUME");
                    color: !deviceConnected ? "#A2A5CF" : (deviceActive ? "#ef4444" : "#10b981");
                    font.family: "Inter, Roboto, sans-serif"; font.pixelSize: 8 * fontScale; font.bold: true; font.letterSpacing: 0.5
                }

                HoverHandler {
                    id: stopHover
                    cursorShape: deviceActive ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: deviceActive ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true
                    enabled: deviceConnected

                    onEntered: { if (deviceConnected) parent.color = deviceActive ? Qt.rgba(239, 68, 68, 0.25) : Qt.rgba(16, 185, 129, 0.25) }
                    onExited: { if (deviceConnected) parent.color = deviceActive ? Qt.rgba(239, 68, 68, 0.15) : Qt.rgba(16, 185, 129, 0.15) }

                    onClicked: {
                        if (typeof root !== 'undefined') {
                            if (deviceActive) {
                                root.showConfirmationDialog(
                                    "Stop Device " + statusBlockRoot.deviceId,
                                    "WARNING: Are you sure you want to stop " + statusBlockRoot.deviceId + "?",
                                    function() {
                                        deviceActive = false;
                                        if (typeof mapBridge !== 'undefined') {
                                            mapBridge.stopRobot(statusBlockRoot.deviceId)
                                        }
                                    },
                                )
                            } else {
                                root.showConfirmationDialog(
                                    "Resume Device " + statusBlockRoot.deviceId,
                                    "Are you sure you want to resume normal operations for Device " + statusBlockRoot.deviceId + "?",
                                    function() {
                                        deviceActive = true;
                                        if (typeof mapBridge !== 'undefined') {
                                            mapBridge.resumeRobot(statusBlockRoot.deviceId)
                                        }
                                    },

                                )
                            }
                        } else if (typeof mapBridge !== 'undefined') {
                            if (deviceActive) {
                                deviceActive = false;
                                mapBridge.stopRobot(statusBlockRoot.deviceId)
                            } else {
                                deviceActive = true;
                                mapBridge.resumeRobot(statusBlockRoot.deviceId)
                            }
                        }
                    }
                }
            }
        }

        // --- MIDDLE SECTION: Column layout to keep content inside block ---
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: Math.max(0, statusBlockRoot.width - 24 * fontScale - 2)
            spacing: 8 * fontScale

            // Row 1: Swarm only (wraps if needed so it stays inside)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4 * fontScale
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6 * fontScale
                    Text { text: "🛰️"; font.pixelSize: 14 * fontScale }
                    Text { text: "Swarm"; color: "#A2A5CF"; font.family: "Inter, Roboto, sans-serif"; font.pixelSize: 9 * fontScale }
                    Item { Layout.fillWidth: true }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 4 * fontScale
                    Repeater {
                        model: statusBlockRoot.effectiveSwarmList
                        Row {
                            spacing: 4 * fontScale
                            Text {
                                text: (modelData && modelData.label !== undefined) ? modelData.label : ("R" + (modelData ? modelData.id : ""))
                                color: "#f8fafc"
                                font.family: "Inter, Roboto, sans-serif"
                                font.pixelSize: 9 * fontScale
                            }
                            Rectangle {
                                width: 8 * fontScale
                                height: 8 * fontScale
                                radius: 4 * fontScale
                                // Only show other robots as online if THIS device is also online
                                color: (statusBlockRoot.deviceConnected
                                        && modelData
                                        && statusBlockRoot.swarmOnlineMap[modelData.id] === true)
                                    ? theme.neon : theme.textMuted
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                        }
                    }
                }
            }

            // Row 2: Sensor Health and Sensors button on same line
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 8 * fontScale
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6 * fontScale
                    Text { text: "Sensor Health:"; color: "#A2A5CF"; font.family: "Inter, Roboto, sans-serif"; font.pixelSize: 10 * fontScale }
                    Rectangle { width: 8 * fontScale; height: 8 * fontScale; radius: 4 * fontScale; color: deviceConnected ? "#10b981" : "#ef4444" }
                    Text { text: deviceConnected ? "Nominal" : "Error"; color: deviceConnected ? "#10b981" : "#ef4444"; font.family: "Inter, Roboto, sans-serif"; font.pixelSize: 10 * fontScale; font.bold: true }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.preferredWidth: Math.max(95 * fontScale, sensorRow.implicitWidth + 24 * fontScale)
                    Layout.preferredHeight: 28 * fontScale
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    radius: 8
                    color: "#1D4E67"
                    border.color: "#31E0FF"
                    border.width: 1
                    opacity: deviceConnected ? 1.0 : 0.5
                    RowLayout {
                        id: sensorRow
                        anchors.centerIn: parent
                        spacing: 6 * fontScale
                        Text { text: "Sensors  ⭢"; font.family: "Inter, Roboto, sans-serif"; font.pixelSize: 11 * fontScale; font.bold: true; color: "#f8fafc" }
                    }
                    HoverHandler {
                        id: sensorHover
                        cursorShape: deviceActive ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: deviceActive
                        hoverEnabled: true
                        cursorShape: deviceActive ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (typeof root !== 'undefined') {
                                root.currentDeviceId = statusBlockRoot.deviceId
                                root.currentScreen = "sensor"
                            }
                        }
                    }
                }
            }
        }

        // Hides the offline alert banner after 3 s
        Timer {
            id: alertHideTimer
            interval: 3000
            repeat: false
            onTriggered: showOfflineAlert = false
        }

        // --- BOTTOM SECTION: System Battery & Status Chips ---
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom
            spacing: 6 * fontScale

            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "System Battery"; color: "#A2A5CF"; font.family: "Inter, Roboto, sans-serif"; font.pixelSize: 10 * fontScale }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: batteryLevel + "%"
                        color: "#f8fafc"
                        font.family: "Inter, Roboto, sans-serif"
                        font.bold: true
                        font.pixelSize: 10 * fontScale
                        horizontalAlignment: Text.AlignRight
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 6 * fontScale; radius: 3; color: "#0A091A"
                    Rectangle {
                        width: parent.width * (Math.min(batteryLevel, 100) / 100); height: parent.height; radius: 3
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: batteryLevel > 30 ? "#2D8E5E" : "#991b1b" }
                            GradientStop { position: 1.0; color: batteryLevel > 30 ? "#7BFF4F" : "#ef4444" }
                        }
                        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
                    }
                }
            }

            // Backend Status Chips - Placed at the absolute bottom
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 24 * fontScale; radius: 6
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: deviceConnected ? (deviceActive ? Qt.rgba(0, 230, 118, 0.15) : Qt.rgba(239, 68, 68, 0.15)) : Qt.rgba(162, 165, 207, 0.1) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    border.color: deviceConnected ? (deviceActive ? "#00e676" : "#ef4444") : "#A2A5CF"
                    border.width: 1

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: deviceConnected ? (deviceActive ? "#00e676" : "#ef4444") : "#A2A5CF"
                            SequentialAnimation on opacity {
                                running: deviceActive || (!deviceActive && deviceConnected)
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: deviceActive ? 800 : 1500 }
                                NumberAnimation { to: 1.0; duration: deviceActive ? 800 : 1500 }
                            }
                        }

                        Text {
                            text: !deviceConnected ? "SYSTEM OFFLINE" : (deviceActive ? "ACTIVE & READY" : "SYSTEM STOPPED")
                            color: deviceConnected ? (deviceActive ? "#00e676" : "#ef4444") : "#A2A5CF"
                            font.family: "Inter, Roboto, sans-serif"
                            font.pixelSize: 9 * fontScale
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                    }
                }
        }
    }

    Connections {
        target: (typeof mapBridge !== 'undefined') ? mapBridge : null

        function onRobotStatusUpdated(id, active, battery) {
            console.log("📡 robotStatusUpdated → id=" + id + " active=" + active
                        + " battery=" + battery + " (this block deviceId=" + statusBlockRoot.deviceId + ")")
            if (Number(id) === Number(statusBlockRoot.deviceId)) {
                statusBlockRoot.deviceActive    = active;
                statusBlockRoot.batteryLevel    = battery;
                statusBlockRoot.deviceConnected = true;
                if (statusBlockRoot.showOfflineAlert)
                    statusBlockRoot.showOfflineAlert = false;
            }
            // Always update the swarm map so other robots' dots reflect reality
            var map = statusBlockRoot.swarmOnlineMap;
            map[Number(id)] = active;
            statusBlockRoot.swarmOnlineMap = map; // reassign to trigger binding update
        }
    }

    // alert popup overlay
    Rectangle {
        id: offlinePopup
        anchors.fill: parent
        color: Qt.rgba(14, 12, 37, 0.75) // Dark tinted overlay matching theme (#0E0C25)
        radius: 12
        visible: opacity > 0
        opacity: showOfflineAlert ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.85
            height: 48 * fontScale
            radius: 8
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#ef4444" }
                GradientStop { position: 1.0; color: "#b91c1c" }
            }
            border.color: "#7f1d1d"
            border.width: 2

            RowLayout {
                anchors.fill: parent
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignCenter
                    Layout.fillWidth: true
                    text: "⚠ CONNECTION LOST"
                    color: "white"
                    font.family: "Inter, Roboto, sans-serif"
                    font.bold: true
                    font.pixelSize: 12 * fontScale
                    font.letterSpacing: 1.0
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
