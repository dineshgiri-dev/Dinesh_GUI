import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import "."

Rectangle {
    id: cameraBlockRoot
    Theme { id: theme }

    property int deviceId: 0
    // true only when the backend has sent an explicit robot_status/battery message for this robot
    property bool deviceConnected: false
    // true while camera frames are actively arriving (resets after 3 s silence)
    property bool deviceActive: false
    // Label of the camera currently being displayed, e.g. "FR", "FL", "RR", "RL"
    property string activeCameraLabel: ""
    property color borderColor: "#2E546D"
    property color accentColor: "#31E0FF"

    // Topic format (single-namespace):
    //   Color : /ugv_0N/camera/<pos>/image_raw      pos = fr|fl|rr|rl|rgb
    //   Depth : /ugv_0N/camera/<pos>/depth/image_raw
    //           /ugv_0N/camera/depth/image_raw       (general depth)
    function parseCameraPosition(topic) {
        var t = topic ? topic.toLowerCase() : "";
        var idPad = deviceId < 10 ? "ugv_0" + deviceId : "ugv_" + deviceId;
        if (t.indexOf("/" + idPad + "/") === -1) return "";

        // Depth: any topic with /depth/image_raw
        if (t.indexOf("/depth/image_raw") !== -1) return "depth";

        // Color: /camera/<pos>/image_raw (no depth segment)
        if (t.indexOf("/camera/fr/image_raw") !== -1) return "fr";
        if (t.indexOf("/camera/fl/image_raw") !== -1) return "fl";
        if (t.indexOf("/camera/rr/image_raw") !== -1) return "rr";
        if (t.indexOf("/camera/rl/image_raw") !== -1) return "rl";
        if (t.indexOf("/camera/rgb/image_raw") !== -1) return "rgb";
        return "";
    }

    // Short display label for a position key
    function posLabel(pos) {
        return ({ fr:"FR", fl:"FL", rr:"RR", rl:"RL", rgb:"RGB", depth:"Depth" })[pos]
               || pos.toUpperCase();
    }

    // Dynamic Font Scaling to match StatusBlock
    readonly property real fontScale: Math.max(0.8, Math.min(cameraBlockRoot.width / 300, 1.2))

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
        anchors.margins: 12 * fontScale
        spacing: 6 * fontScale

        // --- HEADER SECTION ---
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30 * fontScale
            spacing: 8 * fontScale

            Text {
                text: "Device-" + deviceId + (activeCameraLabel !== "" ? "  ·  " + activeCameraLabel.toUpperCase() : "")
                color: "#ffffff"
                font.pixelSize: Math.max(12, 16 * fontScale)
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // Status Badge — green when system is connected (same rule as DeviceStatusBlock)
            Rectangle {
                Layout.preferredWidth: Math.max(80 * fontScale, statusBadgeText.implicitWidth + 16 * fontScale)
                Layout.preferredHeight: 22 * fontScale
                radius: 11 * fontScale
                color: deviceConnected ? Qt.rgba(theme.neon.r, theme.neon.g, theme.neon.b, 0.12)
                                       : Qt.rgba(theme.danger.r, theme.danger.g, theme.danger.b, 0.12)
                border.color: deviceConnected ? theme.neon : theme.danger
                Text {
                    id: statusBadgeText
                    anchors.centerIn: parent
                    text: deviceConnected ? (deviceActive ? "● ACTIVE" : "● ONLINE") : "● OFFLINE"
                    color: deviceConnected ? theme.neon : theme.danger
                    font.pixelSize: Math.max(10, 10 * fontScale); font.bold: true; font.letterSpacing: 1.0
                }
            }
        }

        // --- FEED AREA ---
        Rectangle {
            id: container
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: "#0A1825"
            border.color: theme.glassStroke
            clip: true

            Image {
                id: deviceCameraImage
                anchors.fill: parent
                anchors.margins: 4
                fillMode: Image.PreserveAspectFit
                visible: source !== ""
                cache: false
            }

            // ── Offline / waiting placeholder ─────────────────────────
            Item {
                anchors.fill: parent
                visible: deviceCameraImage.source === ""

                // Pulsing offline icon circle
                Rectangle {
                    id: statusCircle
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -14 * fontScale
                    width: 48 * fontScale; height: 48 * fontScale; radius: 24 * fontScale
                    color: !deviceConnected
                           ? Qt.rgba(1, 0.18, 0.18, 0.16)
                           : Qt.rgba(1, 0.80, 0.0,  0.12)
                    border.color: !deviceConnected ? "#ff4444" : "#ffcc00"
                    border.width: 2

                    SequentialAnimation on opacity {
                        running: true; loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.00; duration: 900; easing.type: Easing.InOutSine }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: !deviceConnected ? "✕" : "⏳"
                        font.pixelSize: 20 * fontScale
                        color: !deviceConnected ? "#ff5555" : "#ffcc00"
                    }
                }

                // Status label
                Text {
                    anchors.top: statusCircle.bottom
                    anchors.topMargin: 8 * fontScale
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !deviceConnected ? "ROBOT OFFLINE" : (cameraActivityTimer.running ? "AWAITING FRAME..." : "CAMERA DISCONNECTED / NO RESPONSE")
                    color: !deviceConnected ? "#ff5555" : "#ffcc00"
                    font.pixelSize: 10 * fontScale; font.bold: true; font.letterSpacing: 1.2
                }

                // Topic hint
                Text {
                    anchors.top: statusCircle.bottom
                    anchors.topMargin: 26 * fontScale
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: deviceId > 0
                          ? "/ugv_0" + deviceId + "/camera/<pos>/image_raw"
                          : ""
                    color: "#3a6a8a"
                    font.pixelSize: 8 * fontScale
                }
            }

            // ── Stale-feed banner (feed was live but went silent) ─────
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left; anchors.right: parent.right
                height: 22 * fontScale
                visible: deviceCameraImage.source !== "" && deviceActive
                color: Qt.rgba(1.0, 0.7, 0.0, 0.22)
                radius: 4

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5 * fontScale
                    Text {
                        text: "⚠"
                        font.pixelSize: 10 * fontScale
                        color: "#ffcc00"
                    }
                    Text {
                        text: "Feed stale — no new frames"
                        font.pixelSize: 9 * fontScale; font.bold: true
                        color: "#ffcc00"
                    }
                }
            }

            // ── Maximize button ───────────────────────────────────────────
            Rectangle {
                id: maxBtn
                width: 28 * fontScale; height: 28 * fontScale; radius: 6
                color: maxHover.hovered ? theme.cyan : "#2E546D"
                anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.margins: 8 * fontScale
                scale: maxHover.hovered ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }

                Text { anchors.centerIn: parent; text: "⛶"; color: "white"; font.pixelSize: 12 * fontScale }

                HoverHandler { id: maxHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (typeof root !== 'undefined') {
                            root.currentDeviceId = deviceId
                            root.currentScreen = "maximized"
                        }
                    }
                }
            }
        }
    }

    // --- BACKEND CONNECTIVITY ---
    Connections {
        target: (typeof mapBridge !== 'undefined') ? mapBridge : null
        ignoreUnknownSignals: true

        // deviceConnected follows the same rule as DeviceStatusBlock
        function onRobotStatusUpdated(id, active, battery) {
            if (Number(id) === Number(cameraBlockRoot.deviceId)) {
                cameraBlockRoot.deviceConnected = true;
            }
        }

        // Clear everything when bridge drops
        function onIsConnectedChanged() {
            if (typeof mapBridge !== 'undefined' && mapBridge && !mapBridge.isConnected) {
                cameraBlockRoot.deviceConnected   = false;
                cameraBlockRoot.deviceActive      = false;
                cameraBlockRoot.activeCameraLabel = "";
                cameraActivityTimer.stop();
                deviceCameraImage.source = "";
            }
        }

        // Color: /ugv_0N/camera/<pos>/image_raw
        // Depth: /ugv_0N/camera/<pos>/depth/image_raw
        function onImageReceived(topic, base64) {
            var pos = cameraBlockRoot.parseCameraPosition(topic);
            console.log("📷 [Device-" + cameraBlockRoot.deviceId + "] imageReceived topic=" + topic
                        + " pos=" + pos + " dataLen=" + (base64 ? base64.length : 0));
            if (pos === "") return;
            if (!base64 || base64.length === 0) return;

            // Detect JPEG / PNG from magic bytes; fall back to jpeg for raw data
            var mime = base64.startsWith("/9j/") ? "image/jpeg"
                     : base64.startsWith("iVB")  ? "image/png"
                     : "image/jpeg"; // raw pixel data — attempt as jpeg, QML will show if valid

            var src = "data:" + mime + ";base64," + base64;
            deviceCameraImage.source = src;
            cameraBlockRoot.activeCameraLabel = cameraBlockRoot.posLabel(pos);
            cameraBlockRoot.deviceActive = true;
            cameraActivityTimer.restart();
        }
    }

    // Camera feed goes stale after 3 s without a new frame
    Timer {
        id: cameraActivityTimer
        interval: 3000
        repeat: false
        onTriggered: {
            cameraBlockRoot.deviceActive = false;
            deviceCameraImage.source = "";
        }
    }
}
