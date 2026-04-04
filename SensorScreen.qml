import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: sensorScreen
    Theme { id: theme }
    color: appRoot ? appRoot.surface : theme.bg1

    property var  appRoot: null
    property int  selectedDeviceId: 0

    // ── Live sensor values keyed by sensor_name (populated from sensorUpdated signal) ──
    property var sensorValues: ({})

    // ── Derived booleans / colours (read from sensorValues, written by onSensorUpdated) ──
    property bool robotCommStatus:   false
    property bool state3DLidar:      false
    property bool state2DLidar:      false
    property bool stateDepthCamera:  false
    property real batteryLevel:      0.0
    property string colorMotorHealth:     "#ef4444"
    property string colorProcessorHealth: "#ef4444"
    property string colorPowerBoard:      "#ef4444"
    property string colorDepthCamera:     "#ef4444"
    property string colorGPS:             "#ef4444"
    property string colorOdom:            "#ef4444"

    // ── Pending switch states (editable by user, sent on UPDATE SENSORS) ──
    property bool pending3DLidar:     state3DLidar
    property bool pending2DLidar:     state2DLidar
    property bool pendingDepthCamera: stateDepthCamera

    // ── Acknowledgement toast ──
    property string ackMessage: ""
    property bool   ackSuccess: true
    property bool   ackVisible: false

    // ── Helpers ──
    function statusText(commOk, color) {
        if (!commOk) return "Inactive"
        if (color === "#22c55e") return "Active"
        if (color === "#eab308") return "Warning"
        return "Critical"
    }

    function resolveColor(commOk, color) {
        return commOk ? color : "#ef4444"
    }

    // Request current sensor snapshot whenever this page becomes active
    function refreshSensors() {
        if (typeof mapBridge !== 'undefined' && selectedDeviceId > 0)
            mapBridge.requestSensorState(selectedDeviceId)
    }

    Component.onCompleted: refreshSensors()

    onSelectedDeviceIdChanged: refreshSensors()

    // ── Ack toast auto-hide timer ──
    Timer {
        id: ackTimer
        interval: 3500
        repeat: false
        onTriggered: ackVisible = false
    }

    // ── Backend → QML wiring ──
    Connections {
        target: (typeof mapBridge !== 'undefined') ? mapBridge : null

        // Sensor values pushed by the backend (sensor_topic / get_sensor_state result)
        function onSensorUpdated(id, sensorName, value) {
            if (Number(id) !== Number(selectedDeviceId)) return

            // Store raw value for the dynamic sensor list
            var cache = sensorValues
            cache[sensorName] = value
            sensorValues = cache

            // Map to named properties
            var name = sensorName.toLowerCase()
            if (name === "3d_lidar" || name === "3d lidar") {
                state3DLidar      = (value === 1)
                pending3DLidar    = (value === 1)
            } else if (name === "2d_lidar" || name === "2d lidar") {
                state2DLidar      = (value === 1)
                pending2DLidar    = (value === 1)
            } else if (name === "depth_camera" || name === "depth camera") {
                stateDepthCamera  = (value === 1)
                pendingDepthCamera = (value === 1)
            } else if (name === "battery_level" || name === "battery level") {
                batteryLevel      = value
            } else {
                var col = value === 1 ? "#22c55e" : (value === 2 ? "#eab308" : "#ef4444")
                if      (name === "motor_health"      || name === "motor health")      colorMotorHealth     = col
                else if (name === "processor_health"  || name === "processor health")  colorProcessorHealth = col
                else if (name === "power_board"       || name === "power distribution board") colorPowerBoard = col
                else if (name === "depth_camera_health" || name === "depth camera health") colorDepthCamera = col
                else if (name === "gps_module"        || name === "gps module")        colorGPS             = col
                else if (name === "odometry"          || name === "odom")              colorOdom            = col
            }
        }

        // Sensor-state acknowledgement from backend
        function onSensorStateAckReceived(id, success, message) {
            if (Number(id) !== Number(selectedDeviceId)) return
            ackSuccess = success
            ackMessage = message
            ackVisible = true
            ackTimer.restart()
        }

        // Battery / comm status from robot heartbeats
        function onRobotStatusUpdated(id, active, battery) {
            if (Number(id) !== Number(selectedDeviceId)) return
            batteryLevel    = battery
            robotCommStatus = active
        }
    }

    // ═══════════════════════════ UI ═══════════════════════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 25
        spacing: 20

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                width: 40; height: 40; radius: 10
                color: backMouse.containsMouse ? "#1D3A50" : "transparent"
                border.color: backMouse.containsMouse ? (appRoot ? appRoot.primary : "#31E0FF") : theme.glassStroke
                scale: backMouse.containsMouse ? 1.1 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }
                Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 22; color: backMouse.containsMouse ? (appRoot ? appRoot.primary : "#31E0FF") : "white" }
                MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: appRoot.currentScreen = "main" }
            }

            Text {
                text: "Sensor Dashboard — Device " + selectedDeviceId
                font.pixelSize: 22; font.bold: true
                color: appRoot ? appRoot.textPrimary : theme.textPrimary
            }

            Item { Layout.fillWidth: true }

            // Manual refresh button
            Rectangle {
                width: 36; height: 36; radius: 8
                color: refreshMouse.containsMouse ? Qt.rgba(49/255, 224/255, 255/255, 0.15) : "transparent"
                border.color: refreshMouse.containsMouse ? "#31E0FF" : theme.glassStroke
                border.width: 1
                Text { anchors.centerIn: parent; text: "⟳"; font.pixelSize: 18; color: refreshMouse.containsMouse ? "#31E0FF" : "#aaa" }
                MouseArea { id: refreshMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: refreshSensors() }
            }
        }

        // ── Ack toast ──
        Rectangle {
            Layout.fillWidth: true
            height: 44; radius: 8
            visible: ackVisible
            color: ackSuccess ? Qt.rgba(34/255, 197/255, 94/255, 0.15) : Qt.rgba(239/255, 68/255, 68/255, 0.15)
            border.color: ackSuccess ? "#22c55e" : "#ef4444"
            border.width: 1

            RowLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 10
                Text {
                    text: ackSuccess ? "✔" : "✖"
                    color: ackSuccess ? "#22c55e" : "#ef4444"
                    font.pixelSize: 16; font.bold: true
                }
                Text {
                    text: ackMessage
                    color: ackSuccess ? "#22c55e" : "#ef4444"
                    font.pixelSize: 13; font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text {
                    text: "✕"; color: "#aaa"; font.pixelSize: 14
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ackVisible = false }
                }
            }
        }

        // ── Scrollable content ──
        ScrollView {
            id: scrollView
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: scrollView.availableWidth; spacing: 12

                // ═══ COMMUNICATION ═══
                Text { text: "Communication"; font.bold: true; font.pixelSize: 18; color: appRoot ? appRoot.textPrimary : "#f8fafc"; Layout.topMargin: 4 }

                Rectangle {
                    Layout.fillWidth: true; height: 55; radius: 8
                    color: appRoot ? appRoot.surfaceLight : "#153145"
                    border.color: appRoot ? appRoot.borderColor : "#A2A5CF"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        Text { text: "Robot Comm Status"; Layout.fillWidth: true; font.bold: true; font.pixelSize: 16; color: appRoot ? appRoot.textPrimary : "#f8fafc" }
                        Rectangle { width: 14; height: 14; radius: 7; color: robotCommStatus ? "#22c55e" : "#ef4444"; Layout.rightMargin: 8 }
                        Text { text: robotCommStatus ? "Online" : "Offline"; color: robotCommStatus ? "#22c55e" : "#ef4444"; font.bold: true; font.pixelSize: 16 }
                    }
                }

                // ═══ BATTERY ═══
                Text { text: "Power"; font.bold: true; font.pixelSize: 18; color: appRoot ? appRoot.textPrimary : "#f8fafc"; Layout.topMargin: 8 }

                Rectangle {
                    Layout.fillWidth: true; height: 55; radius: 8
                    color: appRoot ? appRoot.surfaceLight : "#153145"
                    border.color: appRoot ? appRoot.borderColor : "#A2A5CF"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        Text { text: "Battery Level"; Layout.fillWidth: true; font.bold: true; font.pixelSize: 16; color: appRoot ? appRoot.textPrimary : "#f8fafc" }
                        ProgressBar {
                            id: batProgress
                            value: batteryLevel / 100.0; Layout.preferredWidth: 150
                            background: Rectangle { color: appRoot ? appRoot.surface : "#0E0C25"; radius: 4; border.color: appRoot ? appRoot.borderColor : "#A2A5CF"; implicitHeight: 8 }
                            contentItem: Item {
                                implicitWidth: 150; implicitHeight: 8
                                Rectangle { width: batProgress.visualPosition * parent.width; height: parent.height; radius: 4; color: batteryLevel > 20 ? "#22c55e" : "#ef4444" }
                            }
                        }
                        Text { text: batteryLevel.toFixed(0) + "%"; font.bold: true; font.pixelSize: 16; color: appRoot ? appRoot.textPrimary : "#f8fafc"; Layout.leftMargin: 8 }
                    }
                }

                // ═══ HEALTH INDICATORS ═══
                Text { text: "Health"; font.bold: true; font.pixelSize: 18; color: appRoot ? appRoot.textPrimary : "#f8fafc"; Layout.topMargin: 8 }

                Repeater {
                    model: [
                        { label: "Motor Health",          color: colorMotorHealth      },
                        { label: "Processor Health",      color: colorProcessorHealth  },
                        { label: "Depth Camera Health",   color: colorDepthCamera      },
                        { label: "GPS Module",            color: colorGPS              },
                        { label: "Odometry",              color: colorOdom             }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true; height: 55; radius: 8
                        color: appRoot ? appRoot.surfaceLight : "#153145"
                        border.color: appRoot ? appRoot.borderColor : "#A2A5CF"

                        property string resolvedColor: resolveColor(robotCommStatus, modelData.color)

                        RowLayout {
                            anchors.fill: parent; anchors.margins: 15
                            Text { text: modelData.label; Layout.fillWidth: true; font.bold: true; font.pixelSize: 16; color: appRoot ? appRoot.textPrimary : "#f8fafc" }
                            Text {
                                text: statusText(robotCommStatus, modelData.color)
                                color: resolvedColor; font.bold: true; font.pixelSize: 14; Layout.rightMargin: 12
                            }
                            Rectangle {
                                width: 24; height: 24; radius: 12; color: resolvedColor
                                border.color: Qt.darker(resolvedColor, 1.2); border.width: 1
                                Rectangle { anchors.centerIn: parent; width: parent.width + 8; height: parent.height + 8; radius: width / 2; color: resolvedColor; opacity: 0.25 }
                            }
                        }
                    }
                }

                // ═══ SENSOR CONTROLS ═══
                Text { text: "Sensor Controls"; font.bold: true; font.pixelSize: 18; color: appRoot ? appRoot.textPrimary : "#f8fafc"; Layout.topMargin: 8 }

                // 3D Lidar
                Rectangle {
                    Layout.fillWidth: true; height: 55; radius: 8
                    color: appRoot ? appRoot.surfaceLight : "#153145"
                    border.color: appRoot ? appRoot.borderColor : "#A2A5CF"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        Text { text: "3D Lidar"; Layout.fillWidth: true; font.bold: true; font.pixelSize: 16; color: appRoot ? appRoot.textPrimary : "#f8fafc" }
                        Text {
                            text: (robotCommStatus && pending3DLidar) ? "Active" : "Inactive"
                            color: (robotCommStatus && pending3DLidar) ? "#22c55e" : "#ef4444"
                            font.bold: true; font.pixelSize: 14; Layout.rightMargin: 12
                        }
                        Switch {
                            checked: pending3DLidar
                            enabled: robotCommStatus
                            onCheckedChanged: pending3DLidar = checked
                        }
                    }
                }

                // 2D Lidar
                Rectangle {
                    Layout.fillWidth: true; height: 55; radius: 8
                    color: appRoot ? appRoot.surfaceLight : "#153145"
                    border.color: appRoot ? appRoot.borderColor : "#A2A5CF"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        Text { text: "2D Lidar"; Layout.fillWidth: true; font.bold: true; font.pixelSize: 16; color: appRoot ? appRoot.textPrimary : "#f8fafc" }
                        Text {
                            text: (robotCommStatus && pending2DLidar) ? "Active" : "Inactive"
                            color: (robotCommStatus && pending2DLidar) ? "#22c55e" : "#ef4444"
                            font.bold: true; font.pixelSize: 14; Layout.rightMargin: 12
                        }
                        Switch {
                            checked: pending2DLidar
                            enabled: robotCommStatus
                            onCheckedChanged: pending2DLidar = checked
                        }
                    }
                }

                // Depth Camera
                Rectangle {
                    Layout.fillWidth: true; height: 55; radius: 8
                    color: appRoot ? appRoot.surfaceLight : "#153145"
                    border.color: appRoot ? appRoot.borderColor : "#A2A5CF"
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 15
                        Text { text: "Depth Camera"; Layout.fillWidth: true; font.bold: true; font.pixelSize: 16; color: appRoot ? appRoot.textPrimary : "#f8fafc" }
                        Text {
                            text: (robotCommStatus && pendingDepthCamera) ? "Active" : "Inactive"
                            color: (robotCommStatus && pendingDepthCamera) ? "#22c55e" : "#ef4444"
                            font.bold: true; font.pixelSize: 14; Layout.rightMargin: 12
                        }
                        Switch {
                            checked: pendingDepthCamera
                            enabled: robotCommStatus
                            onCheckedChanged: pendingDepthCamera = checked
                        }
                    }
                }

                // ═══ DYNAMIC SENSOR VALUES from sensor_topic ═══
                // Shows any extra sensor name/value pairs received from the backend
                Repeater {
                    model: {
                        var knownKeys = ["3d_lidar","3d lidar","2d_lidar","2d lidar","depth_camera","depth camera",
                                         "battery_level","battery level","motor_health","motor health",
                                         "processor_health","processor health","power_board","power distribution board",
                                         "depth_camera_health","depth camera health","gps_module","gps module",
                                         "odometry","odom"]
                        var extras = []
                        for (var k in sensorValues) {
                            if (knownKeys.indexOf(k.toLowerCase()) === -1)
                                extras.push({ name: k, value: sensorValues[k] })
                        }
                        return extras
                    }

                    delegate: Rectangle {
                        Layout.fillWidth: true; height: 55; radius: 8
                        color: appRoot ? appRoot.surfaceLight : "#153145"
                        border.color: appRoot ? appRoot.borderColor : "#A2A5CF"
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 15
                            Text { text: modelData.name; Layout.fillWidth: true; font.bold: true; font.pixelSize: 16; color: appRoot ? appRoot.textPrimary : "#f8fafc" }
                            Text {
                                text: String(modelData.value)
                                color: appRoot ? appRoot.textSecondary : "#94a3b8"
                                font.pixelSize: 14; font.bold: true
                            }
                        }
                    }
                }

                // ═══ UPDATE SENSORS button ═══
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: 8

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 220; Layout.preferredHeight: 55; radius: 8
                        property bool hov: sendMouse.containsMouse
                        color: !robotCommStatus
                               ? Qt.rgba(162/255, 165/255, 207/255, 0.10)
                               : (hov ? Qt.rgba(49/255, 224/255, 255/255, 0.24) : Qt.rgba(49/255, 224/255, 255/255, 0.12))
                        border.color: robotCommStatus ? "#31E0FF" : "#5C7A8F"; border.width: 1
                        opacity: robotCommStatus ? 1.0 : 0.5
                        scale: (robotCommStatus && hov) ? 1.03 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: "UPDATE SENSORS"
                            color: robotCommStatus ? "#31E0FF" : "#5C7A8F"
                            font.bold: true; font.pixelSize: 16
                        }

                        MouseArea {
                            id: sendMouse
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            enabled: robotCommStatus
                            onClicked: {
                                if (typeof mapBridge === 'undefined') return
                                var payload = {
                                    "3d_lidar":     pending3DLidar    ? 1 : 0,
                                    "2d_lidar":     pending2DLidar    ? 1 : 0,
                                    "depth_camera": pendingDepthCamera ? 1 : 0
                                }
                                mapBridge.sendSensorState(selectedDeviceId, payload)
                            }
                        }
                    }
                }

                Item { height: 16 }
            }
        }
    }
}
