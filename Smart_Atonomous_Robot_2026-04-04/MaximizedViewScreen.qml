import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."

BasePage {
    id: maximizedRoot
    Theme { id: theme }

    // ================= PROPERTIES =================
    appRoot: parent.appRoot ? parent.appRoot : (typeof root !== 'undefined' ? root : null)
    property int deviceId: appRoot ? appRoot.currentDeviceId : 0
    property string viewMode: "camera"
    // Camera positions: 0=FR, 1=FL, 2=RR, 3=RL, 4=Depth
    property int selectedCamera: 0
    property bool hasCameraImage: false
    property bool deviceConnected: false
    property var camAvailable: [false, false, false, false, false]
    property var camSources:   ["",    "",    "",    "",    ""   ]

    // Track per-tab stale state (true = last frame > 3 s ago)
    property var camStale: [false, false, false, false, false]

    // Camera meta: key, short label, full label
    readonly property var camKeys:   ["fr",          "fl",         "rr",         "rl",        "depth"    ]
    readonly property var camShort:  ["FR",          "FL",         "RR",         "RL",        "Depth"    ]
    readonly property var camLabels: ["Front Right View", "Front Left View", "Rear Right View", "Rear Left View", "Depth View"]

    // Topic format (single-namespace):
    //   Color 0=FR 1=FL 2=RR 3=RL : /ugv_0N/camera/<pos>/image_raw
    //   Depth 4                    : /ugv_0N/camera/<pos>/depth/image_raw
    //                                /ugv_0N/camera/depth/image_raw
    // Returns 0-4 if topic matches, else -1.
    function parseCamIndex(topic) {
        var t = topic ? topic.toLowerCase() : "";
        var idPad = deviceId < 10 ? "ugv_0" + deviceId : "ugv_" + deviceId;
        if (t.indexOf("/" + idPad + "/") === -1) return -1;

        // Depth: any /depth/image_raw → tab 4
        if (t.indexOf("/depth/image_raw") !== -1) return 4;

        // Color cameras: /camera/<pos>/image_raw → tabs 0-3
        if (t.indexOf("/camera/fr/image_raw") !== -1) return 0;
        if (t.indexOf("/camera/fl/image_raw") !== -1) return 1;
        if (t.indexOf("/camera/rr/image_raw") !== -1) return 2;
        if (t.indexOf("/camera/rl/image_raw") !== -1) return 3;
        return -1;
    }
    property var mapBoundsMin: ({x: -50, y: -50})
    property var mapBoundsMax: ({x: 50, y: 50})

    // Property to store pending camera switch
    property int pendingCameraIndex: -1

    // Property to track map availability
    property bool mapAvailable: false

    // Property to store map data
    property var mapData: null

    property color accent: appRoot ? appRoot.primary : theme.neon
    property color bgDark: appRoot ? appRoot.surfaceLight : theme.glass0
    property color bgDarker: appRoot ? appRoot.surface : theme.bg1
    property color textColor: appRoot ? appRoot.textPrimary : theme.textPrimary
    property color accentLight: appRoot ? appRoot.primaryLight : theme.cyan
    property color offlineRed: appRoot ? appRoot.danger : theme.danger
    property color onlineGreen: appRoot ? appRoot.success : theme.neon
    property color warningYellow: appRoot ? appRoot.warning : theme.warning
    property color objectColor: "#ff0000"  // Red color for point cloud
    property color robotColor: appRoot ? appRoot.primaryLight : "#60a5fa"
    property color targetColor: appRoot ? appRoot.warning : "#f59e0b"

    title: "Robot " + deviceId + " - " + (viewMode === "camera" ? "Camera View" : "3D Map View")
    showBack: true

    // Track robot online/offline and per-tab stale feed
    Connections {
        target: (typeof mapBridge !== 'undefined') ? mapBridge : null
        ignoreUnknownSignals: true

        function onRobotStatusUpdated(id, active, battery) {
            if (Number(id) === Number(maximizedRoot.deviceId))
                maximizedRoot.deviceConnected = true;
        }
        function onIsConnectedChanged() {
            if (typeof mapBridge !== 'undefined' && mapBridge && !mapBridge.isConnected) {
                maximizedRoot.deviceConnected  = false;
                maximizedRoot.hasCameraImage   = false;
                maximizedRoot.camAvailable     = [false, false, false, false, false];
                maximizedRoot.camSources       = ["", "", "", "", ""];
                maximizedRoot.camStale         = [false, false, false, false, false];
                maximizedRoot.camLastFrameMs   = [0, 0, 0, 0, 0];
            }
        }
    }

    // Per-tab last-frame timestamps (ms since epoch); 0 = never received
    property var camLastFrameMs: [0, 0, 0, 0, 0]

    // Poll every second; mark a tab stale when no frame for > 3 s
    Timer {
        id: stalePoller
        interval: 1000; repeat: true; running: true
        onTriggered: {
            var now = Date.now();
            var s = maximizedRoot.camStale.slice();
            var sources = maximizedRoot.camSources.slice();
            var avails = maximizedRoot.camAvailable.slice();
            var changed = false;
            for (var i = 0; i < 5; i++) {
                if (maximizedRoot.camLastFrameMs[i] > 0) {
                    var isStale = (now - maximizedRoot.camLastFrameMs[i]) > 3000;
                    if (isStale && avails[i]) {
                        avails[i] = false;
                        s[i] = true;
                        sources[i] = "";
                        changed = true;
                        if (maximizedRoot.selectedCamera === i) {
                            cameraImage.source = "";
                            maximizedRoot.hasCameraImage = false;
                        }
                    } else if (isStale) {
                        s[i] = true;
                    } else {
                        s[i] = false;
                    }
                }
            }
            if (changed) {
                maximizedRoot.camSources = sources;
                maximizedRoot.camAvailable = avails;
            }
            maximizedRoot.camStale = s;
        }
    }

    // Set size to 65% of parent
    width: parent ? parent.width * 0.65 : 832
    height: parent ? parent.height * 0.65 : 468
    anchors.centerIn: parent

    headerContent: [
        // Mode Toggle Buttons (Camera/Map)
        RowLayout {
            spacing: 6

            Button { id: cameraBtn
                text: "Camera"
                checkable: true
                checked: maximizedRoot.viewMode === "camera"
                scale: hovered ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 150 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }

                background: Rectangle {
                    color: cameraBtn.checked ? "#7BFF4F"/*Qt.rgba(49/255, 224/255, 255/255, 0.20)*/
                                             : (cameraBtn.hovered ? Qt.rgba(49/255, 224/255, 255/255, 0.24) : Qt.rgba(49/255, 224/255, 255/255, 0.10))
                    radius: 8
                    border.color: "#31E0FF"
                    border.width: 1
                }

                contentItem: Text {
                    text: "Camera"
                    color: cameraBtn.checked ?"black":"#31E0FF"
                    font.bold: cameraBtn.checked
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 12
                    rightPadding: 12
                    topPadding: 6
                    bottomPadding: 6
                }

                onClicked: {
                    maximizedRoot.viewMode = "camera"
                }
            }

            Button { id: mapBtn
                text: "3D Map"
                checkable: true
                checked: maximizedRoot.viewMode === "map"
                scale: hovered ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 150 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }

                background: Rectangle {
                    color: mapBtn.checked ? "#7BFF4F"/*Qt.rgba(49/255, 224/255, 255/255, 0.20)*/
                                          : (mapBtn.hovered ? Qt.rgba(49/255, 224/255, 255/255, 0.24) : Qt.rgba(49/255, 224/255, 255/255, 0.10))
                    radius: 8
                    border.color: "#31E0FF"
                    border.width: 1
                }

                contentItem: Text {
                    text: "3D Map"
                    color: mapBtn.checked ? "black":"#31E0FF"
                    font.bold: mapBtn.checked
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 12
                    rightPadding: 12
                    topPadding: 6
                    bottomPadding: 6
                }

                onClicked: {
                    maximizedRoot.viewMode = "map"
                }
            }
        }
    ]

    content: [

        // Camera Selection Row - ONLY VISIBLE IN CAMERA MODE
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 45
            spacing: 8
            visible: viewMode === "camera"  // Hide when in map mode

            Text {
                text: "Camera:";
                color: textColor;
                font.pixelSize: 13
                font.bold: true
            }

            // Camera tab buttons: FR / FL / RR / RL
            Repeater {
                model: maximizedRoot.camShort   // ["FR","FL","RR","RL"]

                Rectangle {
                    id: cameraRadio
                    width: 120
                    height: 32
                    radius: 5
                    color: maximizedRoot.selectedCamera === index
                         ? accent
                         : (cameraRadioMouse.containsMouse ? Qt.lighter(bgDark, 1.2) : bgDark)
                    border.color: maximizedRoot.selectedCamera === index ? accentLight : "#1a3a45"
                    border.width: maximizedRoot.selectedCamera === index ? 2 : 1

                    // Live-feed dot
                    Rectangle {
                        width: 7; height: 7; radius: 3.5
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        color: maximizedRoot.camAvailable[index] ? onlineGreen : offlineRed
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: maximizedRoot.camLabels[index]  // "Front Right" etc.
                            color: maximizedRoot.selectedCamera === index ? "black" : textColor
                            font.bold: maximizedRoot.selectedCamera === index
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData   // "FR" / "FL" / "RR" / "RL"
                            color: maximizedRoot.selectedCamera === index ? Qt.rgba(0,0,0,0.6) : Qt.rgba(1,1,1,0.45)
                            font.pixelSize: 8
                        }
                    }

                    MouseArea {
                        id: cameraRadioMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            maximizedRoot.selectedCamera = index;
                            maximizedRoot.hasCameraImage = maximizedRoot.camAvailable[index];
                            cameraImage.source = maximizedRoot.camSources[index];
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Robot + feed status
            RowLayout {
                spacing: 8

                // Robot online/offline dot
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: maximizedRoot.deviceConnected ? onlineGreen : offlineRed
                    SequentialAnimation on opacity {
                        running: !maximizedRoot.deviceConnected; loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 700 }
                        NumberAnimation { to: 1.0; duration: 700 }
                    }
                }
                Text {
                    text: maximizedRoot.deviceConnected ? "Robot Online" : "Robot Offline"
                    color: maximizedRoot.deviceConnected ? onlineGreen : offlineRed
                    font.pixelSize: 11; font.bold: true
                }

                // Separator
                Rectangle { width: 1; height: 16; color: "#2a3a4a" }

                // Feed live/stale dot
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: hasCameraImage
                           ? (camStale[selectedCamera] ? warningYellow : onlineGreen)
                           : warningYellow
                }
                Text {
                    text: hasCameraImage
                          ? (camStale[selectedCamera] ? "Stale" : "Live")
                          : "No Feed"
                    color: hasCameraImage
                           ? (camStale[selectedCamera] ? warningYellow : onlineGreen)
                           : warningYellow
                    font.pixelSize: 11; font.bold: true
                }
            }
        },

        // Main Content Area
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            radius: 8
            color: bgDarker
            border.color: "#1a3a45"
            border.width: 2
            clip: true

            // Camera view
            Rectangle {
                anchors.fill: parent
                visible: maximizedRoot.viewMode === "camera"
                color: "#0b1114"

                // Camera feed — single Image for all tabs (FR / FL / RR / RL / Depth)
                Image {
                    id: cameraImage
                    anchors.fill: parent
                    anchors.margins: 6
                    fillMode: Image.PreserveAspectFit
                    source: ""
                    visible: source !== ""
                    cache: false
                    onSourceChanged: { if (source !== "") maximizedRoot.hasCameraImage = true }
                }

                // ── Offline / waiting placeholder ─────────────────────
                Item {
                    anchors.fill: parent
                    visible: !maximizedRoot.hasCameraImage

                    // Pulsing circle icon
                    Rectangle {
                        id: maxStatusCircle
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -24
                        width: 64; height: 64; radius: 32
                        color: !maximizedRoot.deviceConnected
                               ? Qt.rgba(1, 0.18, 0.18, 0.14)
                               : Qt.rgba(1, 0.80, 0.0,  0.12)
                        border.color: !maximizedRoot.deviceConnected ? "#ff4444" : "#ffcc00"
                        border.width: 2

                        SequentialAnimation on opacity {
                            running: true; loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 1000; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: !maximizedRoot.deviceConnected ? "✕" : "⏳"
                            font.pixelSize: 26
                            color: !maximizedRoot.deviceConnected ? "#ff5555" : "#ffcc00"
                        }
                    }

                    // Primary status text
                    Text {
                        anchors.top: maxStatusCircle.bottom
                        anchors.topMargin: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !maximizedRoot.deviceConnected
                              ? "ROBOT " + deviceId + " OFFLINE"
                              : (maximizedRoot.camStale[selectedCamera]
                                 ? maximizedRoot.camLabels[selectedCamera].toUpperCase() + " DISCONNECTED / NO RESPONSE"
                                 : "WAITING FOR " + maximizedRoot.camLabels[selectedCamera].toUpperCase() + " FEED")
                        color: !maximizedRoot.deviceConnected ? "#ff5555" : (maximizedRoot.camStale[selectedCamera] ? "#ffcc00" : "#A2A5CF")
                        font.pixelSize: 14; font.bold: true; font.letterSpacing: 1.4
                    }

                    // Sub-hint: expected topic
                    Text {
                        anchors.top: maxStatusCircle.bottom
                        anchors.topMargin: 36
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            var ns = "/ugv_0" + deviceId;
                            var key = maximizedRoot.camKeys[selectedCamera];
                            return key === "depth"
                                ? ns + "/camera/<pos>/depth/image_raw"
                                : ns + "/camera/" + key + "/image_raw";
                        }
                        color: "#3a6a8a"
                        font.pixelSize: 10
                    }
                }

                // ── Stale-feed banner (feed was live but went silent) ──
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left; anchors.right: parent.right
                    height: 26
                    visible: maximizedRoot.hasCameraImage
                             && maximizedRoot.camStale[maximizedRoot.selectedCamera]
                    color: Qt.rgba(1.0, 0.70, 0.0, 0.22)
                    z: 10

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "⚠"; font.pixelSize: 12; color: "#ffcc00" }
                        Text {
                            text: "Feed stale — no new frames for " +
                                  maximizedRoot.camLabels[maximizedRoot.selectedCamera]
                            font.pixelSize: 10; font.bold: true; color: "#ffcc00"
                        }
                    }
                }

                // Connections: route incoming frames to the Image
                Connections {
                    target: (typeof mapBridge !== 'undefined') ? mapBridge : null

                    function onImageReceived(topic, base64) {
                        var idx = maximizedRoot.parseCamIndex(topic);
                        console.log("📷 [MaxView Robot-" + maximizedRoot.deviceId
                                    + "] imageReceived topic=" + topic
                                    + " idx=" + idx + " dataLen=" + (base64 ? base64.length : 0));
                        if (idx === -1) return;
                        if (!base64 || base64.length === 0) return;

                        // Detect JPEG / PNG; fall back to jpeg for raw pixel data
                        var mime = base64.startsWith("/9j/") ? "image/jpeg"
                                 : base64.startsWith("iVB")  ? "image/png"
                                 : "image/jpeg";

                        var dataUri = "data:" + mime + ";base64," + base64;

                        var sources = maximizedRoot.camSources.slice();
                        sources[idx] = dataUri;
                        maximizedRoot.camSources = sources;

                        var avail = maximizedRoot.camAvailable.slice();
                        avail[idx] = true;
                        maximizedRoot.camAvailable = avail;

                        // Refresh stale timestamp for this tab
                        var ts = maximizedRoot.camLastFrameMs.slice();
                        ts[idx] = Date.now();
                        maximizedRoot.camLastFrameMs = ts;
                        var s = maximizedRoot.camStale.slice();
                        s[idx] = false;
                        maximizedRoot.camStale = s;

                        if (idx === maximizedRoot.selectedCamera) {
                            cameraImage.source = dataUri;
                            maximizedRoot.hasCameraImage = true;
                        }
                    }
                }

                // Spinner while waiting for first frame
                BusyIndicator {
                    anchors.centerIn: parent
                    running: !maximizedRoot.hasCameraImage
                             && (typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected)
                    visible: running
                }

                // ── Camera info overlay (bottom-right) ───────────────────────
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 160
                    height: 45
                    radius: 5
                    color: "#1a1f2e"
                    border.color: accent

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 6

                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Robot " + deviceId;
                                color: accentLight;
                                font.bold: true;
                                font.pixelSize: 11
                            }
                            Text {
                                text: maximizedRoot.camLabels[selectedCamera];
                                color: textColor;
                                font.pixelSize: 10
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: hasCameraImage
                                   ? (camStale[selectedCamera] ? warningYellow : onlineGreen)
                                   : offlineRed
                        }
                    }
                }
            }

            Rectangle {
                id: mapViewRect
                anchors.fill: parent
                visible: maximizedRoot.viewMode === "map"
                color: bgDarker
                
                property var currentPoints: []
                property real mapScale: 30.0
                property real pitch: Math.PI / 10
                property real yaw: -Math.PI / 8
                property real minScale: 5.0
                property real maxScale: 150.0
                
                Connections {
                    target: (typeof mapBridge !== 'undefined') ? mapBridge : null
                    function onMapDataReceived(data) {
                        if (data && data.topic === "velodyne_points") {
                            var ptCount = data.points ? data.points.length / 3 : 0;
                            console.log("📡 [MaxView] velodyne_points received:"
                                        + " device_id=" + data.device_id
                                        + " points=" + ptCount
                                        + " thisRobotId=" + maximizedRoot.deviceId);
                            // Show data when:
                            //  • device_id is missing / 0 (broadcast/unparsed)
                            //  • this view has no specific robot selected (deviceId == 0)
                            //  • IDs match exactly
                            var devId = (data.device_id !== undefined) ? data.device_id : 0;
                            if (Number(devId) === 0
                                    || Number(maximizedRoot.deviceId) === 0
                                    || Number(devId) === Number(maximizedRoot.deviceId)) {
                                maximizedRoot.mapAvailable = true;
                                mapViewRect.currentPoints = data.points ? data.points : [];
                                d3MapCanvas.requestPaint();
                            }
                        }
                    }
                }

                // Inner Rectangle specially dedicated to viewing the 3D map
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    radius: 8
                    color: "#262626" // RViz-like dark gray background
                    border.color: "#3b3b3b" // subtle inner border
                    border.width: 1
                    clip: true

                    Canvas {
                        id: d3MapCanvas
                        anchors.fill: parent
                        anchors.margins: 2
                        visible: true // Always show the grid framework even if offline
                        renderTarget: Canvas.FramebufferObject
                        z: 1

                        property real dragStartPitch: 0
                        property real dragStartYaw: 0
                        property bool isDragging: false

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var centerX = width / 2;
                            var centerY = height / 2;
                            
                            var distance = 50; // Camera distance from origin in world units
                            var fov = mapViewRect.mapScale * distance;

                            var cy = Math.cos(mapViewRect.yaw);
                            var sy = Math.sin(mapViewRect.yaw);
                            var cp = Math.cos(mapViewRect.pitch);
                            var sp = Math.sin(mapViewRect.pitch);

                            function project3D(x, y, z) {
                                // 1. Rotate around Z (yaw)
                                var x1 = x * cy - y * sy;
                                var y1 = x * sy + y * cy;
                                
                                // 2. Rotate around Y (pitch)
                                var z2 = z * cp - x1 * sp;
                                var x2 = z * sp + x1 * cp;
                                
                                // 3. Perspective depth
                                var depth = x2 + distance;
                                if (depth <= 0.1) depth = 0.1; // Protect against behind-camera flips
                                
                                return {
                                    sx: centerX + (-y1 / depth) * fov,
                                    sy: centerY + (-z2 / depth) * fov,
                                    depth: depth
                                };
                            }

                            // Draw 3D Grid (RViz style concentric radial rings + crosshairs)
                            ctx.strokeStyle = "#404040"; 
                            ctx.lineWidth = 1;

                            // 1. Draw concentric circles (1m, 2m, 3m... intervals depending on scaling)
                            var numRings = 10;
                            var ringSpacing = 10; // e.g. 10 units apart

                            for (var r = 1; r <= numRings; r++) {
                                var radius = r * ringSpacing;
                                ctx.beginPath();
                                // We approximate the circle via line segments to project it smoothly
                                var segments = 64; 
                                for (var s = 0; s <= segments; s++) {
                                    var angle = (s / segments) * Math.PI * 2;
                                    var cx = Math.cos(angle) * radius;
                                    var cy_val = Math.sin(angle) * radius; // y in ROS frame
                                    
                                    var pt = project3D(cx, cy_val, 0);

                                    // Don't draw points behind the camera plane
                                    if (pt.depth <= 0.1) continue;

                                    if (s === 0) {
                                        ctx.moveTo(pt.sx, pt.sy);
                                    } else {
                                        ctx.lineTo(pt.sx, pt.sy);
                                    }
                                }
                                ctx.stroke();
                            }

                            // 2. Draw Crosshairs slicing the concentric circles
                            ctx.strokeStyle = "#555555";
                            ctx.beginPath();
                            var maxGridDist = numRings * ringSpacing;
                            
                            // X-axis line (through center)
                            var pX1 = project3D(-maxGridDist, 0, 0);
                            var pX2 = project3D(maxGridDist, 0, 0);
                            if (pX1.depth > 0.1 && pX2.depth > 0.1) {
                                ctx.moveTo(pX1.sx, pX1.sy); ctx.lineTo(pX2.sx, pX2.sy);
                            }

                            // Y-axis line
                            var pY1 = project3D(0, -maxGridDist, 0);
                            var pY2 = project3D(0, maxGridDist, 0);
                            if (pY1.depth > 0.1 && pY2.depth > 0.1) {
                                ctx.moveTo(pY1.sx, pY1.sy); ctx.lineTo(pY2.sx, pY2.sy);
                            }
                            ctx.stroke();

                            // Draw Origin Axes
                            function drawLine3D(x1, y1, z1, x2, y2, z2, color, width) {
                                var pr1 = project3D(x1, y1, z1);
                                var pr2 = project3D(x2, y2, z2);
                                ctx.beginPath();
                                ctx.moveTo(pr1.sx, pr1.sy);
                                ctx.lineTo(pr2.sx, pr2.sy);
                                ctx.strokeStyle = color;
                                ctx.lineWidth = width || 1;
                                ctx.stroke();
                            }

                            drawLine3D(0,0,0, 10,0,0, "#ff0000", 3); // X Axis (Forward/Red)
                            drawLine3D(0,0,0, 0,10,0, "#00ff00", 3); // Y Axis (Left/Green)
                            drawLine3D(0,0,0, 0,0,10, "#00aaff", 3); // Z Axis (Up/Blue)

                            if (mapViewRect.currentPoints.length > 0) {
                                ctx.fillStyle = "#ff0000"; // Hot Red Pointcloud color mimicking Reference UI
                                
                                // Dynamic LOD (Level of Detail) - Render 3x faster while dragging
                                var skip = d3MapCanvas.isDragging ? 9 : 3;

                                // Extract reference to avoid lookup overhead
                                var pts = mapViewRect.currentPoints;
                                var len = pts.length - 2;

                                // Handle flat array format (x, y, z sequence)
                                for (var p = 0; p < len; p += skip) {
                                    var x = pts[p];
                                    var y = pts[p+1];
                                    var z = pts[p+2];

                                    if (x === undefined || y === undefined || z === undefined) continue;

                                    // Inline project3D for absolute maximum loop performance
                                    var x1 = x * cy - y * sy;
                                    var y1 = x * sy + y * cy;
                                    
                                    var z2 = z * cp - x1 * sp;
                                    var x2 = z * sp + x1 * cp;
                                    
                                    var depth = x2 + distance;
                                    if (depth <= 0.1) continue; 
                                    
                                    var px = centerX + (-y1 / depth) * fov;
                                    var py = centerY + (-z2 / depth) * fov;

                                    // Dynamic perspective sizing for pointcloud 
                                    var pointSize = Math.max(0.5, (distance / depth) * 1.5);
                                    
                                    // Much faster than accumulating a huge path geometry and then filling
                                    ctx.fillRect(px, py, pointSize, pointSize);
                                }
                            }
                        }

                        MouseArea { anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            property real lastX: 0
                            property real lastY: 0
                            onPressed: {
                                lastX = mouse.x; lastY = mouse.y
                                d3MapCanvas.dragStartPitch = mapViewRect.pitch
                                d3MapCanvas.dragStartYaw = mapViewRect.yaw
                                d3MapCanvas.isDragging = true
                            }
                            onReleased: {
                                d3MapCanvas.isDragging = false
                                d3MapCanvas.requestPaint() // Re-render at high quality once released
                            }
                            onPositionChanged: {
                                if (pressedButtons & Qt.LeftButton) {
                                    var dx = mouse.x - lastX, dy = mouse.y - lastY
                                    
                                    var newYaw = d3MapCanvas.dragStartYaw - dx * 0.01;
                                    var newPitch = d3MapCanvas.dragStartPitch + dy * 0.01;

                                    // Bound the Drag rotation heavily so the map isn't infinitely spinning backwards
                                    mapViewRect.yaw = Math.max(-Math.PI / 1.5, Math.min(Math.PI / 1.5, newYaw));
                                    mapViewRect.pitch = Math.max(0.1, Math.min(Math.PI / 2.5, newPitch));

                                    d3MapCanvas.requestPaint()
                                }
                            }
                            onWheel: {
                                var delta = wheel.angleDelta.y > 0 ? 1.15 : 1/1.15
                                mapViewRect.mapScale = Math.min(mapViewRect.maxScale, Math.max(mapViewRect.minScale, mapViewRect.mapScale * delta))
                                d3MapCanvas.requestPaint()
                            }
                        }
                    }

                    // Toolbar overlay for zoom/rotate buttons
                    Column {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        spacing: 8
                        z: 50

                        Rectangle {
                            width: 36; height: 36; radius: 6; color: "#153145"; border.color: "#2E546D"
                            Text { anchors.centerIn: parent; text: "+"; color: "#31E0FF"; font.pixelSize: 20; font.bold: true }
                            MouseArea { anchors.fill: parent
                                onClicked: { mapViewRect.mapScale = Math.min(mapViewRect.maxScale, mapViewRect.mapScale * 1.2); d3MapCanvas.requestPaint() }
                            }
                        }
                        Rectangle {
                            width: 36; height: 36; radius: 6; color: "#153145"; border.color: "#2E546D"
                            Text { anchors.centerIn: parent; text: "−"; color: "#31E0FF"; font.pixelSize: 20; font.bold: true }
                            MouseArea { anchors.fill: parent
                                onClicked: { mapViewRect.mapScale = Math.max(mapViewRect.minScale, mapViewRect.mapScale / 1.2); d3MapCanvas.requestPaint() }
                            }
                        }
                        Rectangle {
                            width: 36; height: 36; radius: 6; color: "#153145"; border.color: "#2E546D"
                            Text { anchors.centerIn: parent; text: "↻"; color: "#31E0FF"; font.pixelSize: 18 }
                            MouseArea { anchors.fill: parent
                                onClicked: { mapViewRect.yaw += 0.25 * Math.PI; d3MapCanvas.requestPaint() }
                            }
                        }
                    }

                    // Stylish Offline Overlay (Center)
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.6
                        height: 150
                        color: Qt.rgba(26/255, 31/255, 46/255, 0.85) // Semi-transparent overlay
                        radius: 8
                        border.color: accentLight
                        visible: !maximizedRoot.mapAvailable
                        z: 10

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                text: "🗺️"
                                font.pixelSize: 42
                                color: accent
                                opacity: 0.8
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: "Waiting for 3D Velodyne Points..."
                                font.pixelSize: 16
                                font.bold: true
                                color: textColor
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: "Map stream has not initialized yet for Robot " + deviceId
                                font.pixelSize: 12
                                color: "#9aa8b0"
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // Map Legend with Icons for Objects, Robots, Targets
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 12
                        width: 170
                        height: 130
                        radius: 6
                        color: "#1a1f2e"
                        border.color: accent

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            z: 50 // Keep on top of canvas

                            Text {
                                text: "Map Legend"
                                color: accentLight
                                font.bold: true
                                font.pixelSize: 13
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: "#153145"
                            }

                            // Robots - UGV icon (unmanned ground vehicle)
                            RowLayout {
                                spacing: 10
                                Text {
                                    text: "⛟";  // UGV/rover icon
                                    color: robotColor;
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                                Text { text: "Robots"; color: textColor; font.pixelSize: 12 }
                            }

                            // Targets - Human icon
                            RowLayout {
                                spacing: 10
                                Text {
                                    text: "👤";  // Human icon
                                    color: targetColor;
                                    font.pixelSize: 18
                                }
                                Text { text: "Human Targets"; color: textColor; font.pixelSize: 12 }
                            }
                        }
                    } // End Map Legend

                // Temporary Debug Box for diagnosing PointCloud parsing
                // Rectangle {
                //     anchors.bottom: parent.bottom
                //     anchors.left: parent.left
                //     anchors.margins: 10
                //     width: 320
                //     height: 140
                //     color: Qt.rgba(0,0,0,0.85)
                //     border.color: "#7C3AED"
                //     radius: 4
                //     z: 50
                    
                //     ScrollView {
                //         anchors.fill: parent
                //         anchors.margins: 8
                //         clip: true
                //         Text {
                //             text: "Parser Debug Log:\n" + ((typeof mapBridge !== 'undefined' && mapBridge) ? mapBridge.debugLogData : "No bridge")
                //             color: "#10b981"
                //             font.pixelSize: 10
                //             wrapMode: Text.WrapAnywhere
                //         }
                //     }
                // }

                // Map status overlay
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 10
                        width: 140
                        height: 40
                        radius: 5
                        color: "#1a1f2e"
                        border.color: offlineRed

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: offlineRed
                            }

                            Text {
                                text: maximizedRoot.mapAvailable ? "Map Online" : "Map Offline"
                                color: maximizedRoot.mapAvailable ? onlineGreen : offlineRed
                                font.bold: true
                                font.pixelSize: 11
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: maximizedRoot.mapAvailable ? "✅" : "⚠️"
                                font.pixelSize: 12
                            }
                        }
                    } // End Map status overlay

                } // End inner map rectangle
            } // End mapViewRect
        } // End Main Content Area
    ]
}
