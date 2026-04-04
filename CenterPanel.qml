import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import "."

Rectangle {
    id: cpRoot
    Theme { id: theme }
    property color borderColor: "#2E546D"
    property color blueColor: "#8FB0C7"
    property color accentColor: "#31E0FF"

    radius: 8
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#152B3D" }
        GradientStop { position: 1.0; color: "#0E1C2A" }
    }
    border.color: borderColor
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true

    property bool forgingOpen: false
    property bool flockingOpen: false
    property bool isConnected: mapBridge ? mapBridge.isConnected : false
    property bool isEmergency: !isConnected || (mapBridge && mapBridge.confidence < 0.4)

    property var plannedPath: []
    property var plannedPathsByRobot: ({})
    property var robotPositions: ({})
    property var targetPoints: []
    property real mapScale: 20.0
    property real rotationAngle: 0
    property real minScale: 5.0
    property real maxScale: 80.0

    // Map data properties
    property var mapData: null
    property real mapResolution: 0.05  // meters per pixel
    property real mapOriginX: 0
    property real mapOriginY: 0
    property string mapImageSource: ""
    property int overlayRobotId: 0
    readonly property var robotPalette: ["#10b981", "#3b82f6", "#f59e0b", "#ef4444", "#a855f7", "#14b8a6", "#f97316", "#eab308"]

    // ── 2D Laser-scan state ────────────────────────────────────────────────────
    // List of robot IDs that have sent at least one /scan message (drives ComboBox)
    property var scanRobotIds: []
    // Selected robot ID for 2D scan display (0 = "All" / unfiltered overlay)
    property int selectedScanRobotId: 0
    // Per-robot scan point cache  { robotId: [x0,y0,z0, x1,y1,z1, ...] }
    property var scanPointsByRobot: ({})

    function worldToScreen(wx, wy, centerX, centerY) {
        return Qt.point(
            centerX + (wx - cpRoot.mapOriginX) * cpRoot.mapScale,
            centerY - (wy - cpRoot.mapOriginY) * cpRoot.mapScale
        )
    }

    function normalizePoint(pt) {
        if (!pt || pt.x === undefined || pt.y === undefined) return null
        return { x: Number(pt.x), y: Number(pt.y) }
    }

    function normalizeRobotId(value) {
        var id = Number(value)
        if (!id || id < 0) return 0
        return id
    }

    function colorForRobot(robotId) {
        return cpRoot.robotPalette[normalizeRobotId(robotId) % cpRoot.robotPalette.length]
    }

    function parsePointsArray(list) {
        var out = []
        if (!list || !list.length) return out
        for (var i = 0; i < list.length; ++i) {
            var p = normalizePoint(list[i])
            if (p) out.push(p)
        }
        return out
    }

    function extractPointFromMessage(msg) {
        if (!msg) return null
        if (msg.x !== undefined && msg.y !== undefined) return normalizePoint(msg)
        if (msg.position && msg.position.x !== undefined && msg.position.y !== undefined) return normalizePoint(msg.position)
        if (msg.pose && msg.pose.position) return normalizePoint(msg.pose.position)
        if (msg.pose && msg.pose.pose && msg.pose.pose.position) return normalizePoint(msg.pose.pose.position)
        return null
    }

    function extractPathFromMessage(msg) {
        if (!msg) return []
        if (msg.path && msg.path.length) return parsePointsArray(msg.path)
        if (msg.points && msg.points.length) return parsePointsArray(msg.points)
        if (msg.poses && msg.poses.length) {
            var out = []
            for (var i = 0; i < msg.poses.length; ++i) {
                var p = extractPointFromMessage(msg.poses[i])
                if (p) out.push(p)
            }
            return out
        }
        return []
    }

    function extractRobotId(msg, fallbackId) {
        if (!msg) return normalizeRobotId(fallbackId)
        if (msg.robot_id !== undefined) return normalizeRobotId(msg.robot_id)
        if (msg.device_id !== undefined) return normalizeRobotId(msg.device_id)
        if (msg.id !== undefined) return normalizeRobotId(msg.id)
        return normalizeRobotId(fallbackId)
    }

    function applyRobotPositionsFromMessage(msg) {
        if (!msg) return false
        var changed = false
        var updated = Object.assign({}, cpRoot.robotPositions)
        if (msg.robot_positions && msg.robot_positions.length) {
            for (var i = 0; i < msg.robot_positions.length; ++i) {
                var entry = msg.robot_positions[i]
                var rp = extractPointFromMessage(entry)
                if (!rp) continue
                var rid = extractRobotId(entry, i + 1)
                updated[rid] = rp
                changed = true
            }
        } else if (msg.robots && msg.robots.length) {
            for (var j = 0; j < msg.robots.length; ++j) {
                var robotEntry = msg.robots[j]
                var rr = extractPointFromMessage(robotEntry)
                if (!rr) continue
                var rid2 = extractRobotId(robotEntry, j + 1)
                updated[rid2] = rr
                changed = true
            }
        } else {
            var one = extractPointFromMessage(msg)
            if (one) {
                var oneId = extractRobotId(msg, cpRoot.overlayRobotId)
                updated[oneId] = one
                changed = true
            }
        }
        if (changed) cpRoot.robotPositions = updated
        return changed
    }

    function applyTargetsFromMessage(msg) {
        if (!msg) return false
        var points = []
        if (msg.targets && msg.targets.length) {
            for (var i = 0; i < msg.targets.length; ++i) {
                var t = extractPointFromMessage(msg.targets[i])
                if (t) points.push(t)
            }
        } else if (msg.target_points && msg.target_points.length) {
            points = parsePointsArray(msg.target_points)
        } else if (msg.target) {
            var oneTarget = extractPointFromMessage(msg.target)
            if (oneTarget) points.push(oneTarget)
        } else {
            var fallback = extractPointFromMessage(msg)
            if (fallback) points.push(fallback)
        }
        if (points.length > 0) {
            cpRoot.targetPoints = points
            return true
        }
        return false
    }

    function applyPathsFromMessage(msg) {
        if (!msg) return false
        var changed = false
        var pathsByRobot = Object.assign({}, cpRoot.plannedPathsByRobot)
        if (msg.paths && msg.paths.length) {
            for (var i = 0; i < msg.paths.length; ++i) {
                var pathEntry = msg.paths[i]
                var rid = extractRobotId(pathEntry, i + 1)
                var pp = extractPathFromMessage(pathEntry)
                if (pp.length > 0) {
                    pathsByRobot[rid] = pp
                    changed = true
                }
            }
        } else if (msg.paths_by_robot) {
            for (var key in msg.paths_by_robot) {
                var rp = extractPathFromMessage(msg.paths_by_robot[key])
                if (rp.length > 0) {
                    pathsByRobot[normalizeRobotId(key)] = rp
                    changed = true
                }
            }
        } else {
            var single = extractPathFromMessage(msg)
            if (single.length > 0) {
                var sid = extractRobotId(msg, cpRoot.overlayRobotId)
                pathsByRobot[sid] = single
                cpRoot.plannedPath = single
                changed = true
            }
        }
        if (changed) cpRoot.plannedPathsByRobot = pathsByRobot
        return changed
    }

    MouseArea { anchors.fill: parent
        onClicked: {
            cpRoot.forgingOpen = false
            cpRoot.flockingOpen = false
        }
    }

    Image {
        id: mapImage2D
        source: cpRoot.mapImageSource
        anchors.centerIn: parent
        visible: cpRoot.mapImageSource !== ""
        fillMode: Image.PreserveAspectFit
        z: 0
        cache: false

        scale: cpRoot.mapScale / 20.0
        rotation: cpRoot.rotationAngle * 180 / Math.PI
    }

    Canvas {
        id: mapCanvas
        anchors.fill: parent
        anchors.margins: 2
        renderTarget: Canvas.FramebufferObject
        z: 1

        property real dragStartAngle: 0
        property real dragStartRotation: 0

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var centerX = width / 2;
            var centerY = height / 2;

            ctx.save();
            ctx.translate(centerX, centerY);
            ctx.rotate(cpRoot.rotationAngle);
            ctx.translate(-centerX, -centerY);

            var gridStep = Math.max(20, 40 - (cpRoot.mapScale / 2));
            ctx.strokeStyle = "#1E465D"; ctx.lineWidth = 1;
            for (var i = -width; i < width * 2; i += gridStep) {
                ctx.beginPath(); ctx.moveTo(i, 0); ctx.lineTo(i, height); ctx.stroke();
            }
            for (var j = -height; j < height * 2; j += gridStep) {
                ctx.beginPath(); ctx.moveTo(0, j); ctx.lineTo(width, j); ctx.stroke();
            }

            // The pointcloud plotting was moved to individual DeviceCameraBlocks.
            // Center map now only plots High-Level paths and grid locations.

            var anyMultiPath = false
            for (var robotKey in cpRoot.plannedPathsByRobot) {
                var robotPath = cpRoot.plannedPathsByRobot[robotKey]
                if (!robotPath || robotPath.length < 2) continue
                anyMultiPath = true
                ctx.strokeStyle = cpRoot.colorForRobot(robotKey)
                ctx.lineWidth = 2
                ctx.beginPath()
                for (var pk = 0; pk < robotPath.length; ++pk) {
                    var n = robotPath[pk]
                    var p = cpRoot.worldToScreen(n.x, n.y, centerX, centerY)
                    if (pk === 0) ctx.moveTo(p.x, p.y)
                    else ctx.lineTo(p.x, p.y)
                }
                ctx.stroke()
            }

            if (!anyMultiPath && plannedPath.length > 1) {
                ctx.strokeStyle = "#10b981"; ctx.lineWidth = 2
                ctx.beginPath();
                for (var k = 0; k < plannedPath.length; k++) {
                    var node = plannedPath[k];
                    var sp = cpRoot.worldToScreen(node.x, node.y, centerX, centerY)
                    if (k === 0) ctx.moveTo(sp.x, sp.y);
                    else ctx.lineTo(sp.x, sp.y);
                }
                ctx.stroke();
            }

            // ── Draw 2D laser-scan for selected robot ──────────────────────────
            {
                var scanIdsToShow = []
                if (cpRoot.selectedScanRobotId === 0) {
                    // "All" — draw every robot's scan
                    for (var rid in cpRoot.scanPointsByRobot)
                        scanIdsToShow.push(parseInt(rid))
                } else {
                    scanIdsToShow.push(cpRoot.selectedScanRobotId)
                }

                for (var si = 0; si < scanIdsToShow.length; ++si) {
                    var scanId  = scanIdsToShow[si]
                    var scanPts = cpRoot.scanPointsByRobot[scanId]
                    if (!scanPts || scanPts.length < 3) continue

                    ctx.fillStyle = cpRoot.colorForRobot(scanId)
                    for (var pi = 0; pi + 2 < scanPts.length; pi += 3) {
                        var sx = scanPts[pi]
                        var sy = scanPts[pi + 1]
                        var sp2 = cpRoot.worldToScreen(sx, sy, centerX, centerY)
                        ctx.fillRect(sp2.x - 1, sp2.y - 1, 2, 2)
                    }
                }
            }

            // Draw 2D occupancy grid map
            if (cpRoot.mapData && cpRoot.mapData.data && cpRoot.mapData.width && cpRoot.mapData.height) {
                var mapWidth = cpRoot.mapData.width;
                var mapHeight = cpRoot.mapData.height;
                var data = cpRoot.mapData.data;
                var pixelSize = Math.max(1, cpRoot.mapScale * cpRoot.mapResolution);

                for (var y = 0; y < mapHeight; y++) {
                    for (var x = 0; x < mapWidth; x++) {
                        var index = y * mapWidth + x;
                        var occupancy = data[index];

                        if (occupancy >= 0) { // Only draw known cells
                            var worldX = cpRoot.mapOriginX + x * cpRoot.mapResolution
                            var worldY = cpRoot.mapOriginY + y * cpRoot.mapResolution
                            var cell = cpRoot.worldToScreen(worldX, worldY, centerX, centerY)
                            var screenX = cell.x
                            var screenY = cell.y

                            if (occupancy > 50) {
                                // Occupied - black
                                ctx.fillStyle = "#000000";
                            } else if (occupancy > 0) {
                                // Unknown - gray
                                ctx.fillStyle = "#808080";
                            } else {
                                // Free - white
                                ctx.fillStyle = "#FFFFFF";
                            }

                            ctx.fillRect(screenX, screenY, pixelSize, pixelSize);
                        }
                    }
                }
            }

            // Draw target points
            for (var t = 0; t < cpRoot.targetPoints.length; ++t) {
                var target = cpRoot.targetPoints[t]
                var tp = cpRoot.worldToScreen(target.x, target.y, centerX, centerY)
                ctx.beginPath()
                ctx.fillStyle = "#f59e0b"
                ctx.arc(tp.x, tp.y, 5, 0, Math.PI * 2)
                ctx.fill()
                ctx.strokeStyle = "#ffffff"
                ctx.lineWidth = 1
                ctx.stroke()
            }

            // Draw robot positions
            for (var robotId in cpRoot.robotPositions) {
                var rp = cpRoot.robotPositions[robotId]
                if (!rp) continue
                var pos = cpRoot.worldToScreen(rp.x, rp.y, centerX, centerY)
                ctx.beginPath()
                ctx.fillStyle = cpRoot.colorForRobot(robotId)
                ctx.arc(pos.x, pos.y, 6, 0, Math.PI * 2)
                ctx.fill()
                ctx.strokeStyle = "#ffffff"
                ctx.lineWidth = 1
                ctx.stroke()
                ctx.fillStyle = "#ffffff"
                ctx.font = "bold 10px sans-serif"
                ctx.fillText("R" + robotId, pos.x + 8, pos.y - 8)
            }

            ctx.restore();
        }

        MouseArea { anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property real lastX: 0
            property real lastY: 0
            onPressed: {
                lastX = mouse.x; lastY = mouse.y
                mapCanvas.dragStartRotation = cpRoot.rotationAngle
            }
            onPositionChanged: {
                if (pressedButtons & Qt.LeftButton) {
                    var dx = mouse.x - lastX
                    cpRoot.rotationAngle += dx * 0.01
                    mapCanvas.requestPaint()
                }
                lastX = mouse.x; lastY = mouse.y
            }
            onWheel: {
                var delta = wheel.angleDelta.y > 0 ? 1.15 : 1/1.15
                cpRoot.mapScale = Math.min(cpRoot.maxScale, Math.max(cpRoot.minScale, cpRoot.mapScale * delta))
                mapCanvas.requestPaint()
            }
        }
    }

    // ── Robot selector ComboBox (top-left) ───────────────────────────────────
    Rectangle {
        id: scanRobotSelector
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 12
        width: 190; height: 36; radius: 8
        color: "#153145"; border.color: "#2E546D"; border.width: 1
        z: 100

        Row {
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6; spacing: 6

            Text {
                text: "2D Scan:"
                color: "#8FB0C7"; font.pixelSize: 11; font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            ComboBox {
                id: scanRobotCombo
                width: parent.width - 62; height: parent.height - 4
                anchors.verticalCenter: parent.verticalCenter

                // Model: "All" entry + one per discovered robot
                model: {
                    var list = ["All"]
                    for (var i = 0; i < cpRoot.scanRobotIds.length; ++i)
                        list.push("Robot " + cpRoot.scanRobotIds[i])
                    return list
                }

                onCurrentIndexChanged: {
                    if (currentIndex <= 0) {
                        cpRoot.selectedScanRobotId = 0
                    } else {
                        cpRoot.selectedScanRobotId = cpRoot.scanRobotIds[currentIndex - 1]
                    }
                    mapCanvas.requestPaint()
                }

                background: Rectangle {
                    color: "transparent"
                    border.color: "transparent"
                }

                contentItem: Text {
                    leftPadding: 4
                    text: scanRobotCombo.displayText
                    color: "#31E0FF"; font.pixelSize: 12; font.bold: true
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Text {
                    x: scanRobotCombo.width - width - 4
                    y: (scanRobotCombo.height - height) / 2
                    text: "▼"; color: "#31E0FF"; font.pixelSize: 9
                }

                popup: Popup {
                    y: scanRobotCombo.height + 2
                    width: scanRobotCombo.width + 30
                    padding: 0

                    background: Rectangle { color: "#153145"; border.color: "#2E546D"; border.width: 1; radius: 6 }

                    contentItem: ListView {
                        implicitHeight: contentHeight
                        model: scanRobotCombo.delegateModel
                        clip: true
                    }
                }

                delegate: ItemDelegate {
                    width: scanRobotCombo.popup.width
                    contentItem: Text {
                        text: modelData
                        color: scanRobotCombo.currentIndex === index ? "#31E0FF" : "#8FB0C7"
                        font.pixelSize: 12; font.bold: scanRobotCombo.currentIndex === index
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10
                    }
                    background: Rectangle {
                        color: hovered ? Qt.rgba(49/255,224/255,255/255,0.12) : "transparent"
                    }
                }
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
        spacing: 8
        z: 100

        Rectangle {
            width: 36; height: 36; radius: 6; color: "#153145"; border.color: "#2E546D"
            Text { anchors.centerIn: parent; text: "+"; color: "#31E0FF"; font.pixelSize: 20; font.bold: true }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    cpRoot.mapScale = Math.min(cpRoot.maxScale, cpRoot.mapScale * 1.2)
                    mapCanvas.requestPaint()
                }
            }
        }
        Rectangle {
            width: 36; height: 36; radius: 6; color: "#153145"; border.color: "#2E546D"
            Text { anchors.centerIn: parent; text: "−"; color: "#31E0FF"; font.pixelSize: 20; font.bold: true }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    cpRoot.mapScale = Math.max(cpRoot.minScale, cpRoot.mapScale / 1.2)
                    mapCanvas.requestPaint()
                }
            }
        }
        Rectangle {
            width: 36; height: 36; radius: 6; color: "#153145"; border.color: "#2E546D"
            Text { anchors.centerIn: parent; text: "↻"; color: "#31E0FF"; font.pixelSize: 18 }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    cpRoot.rotationAngle += 0.25 * Math.PI
                    mapCanvas.requestPaint()
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: isEmergency ? "⚠ CONNECTION LOST" : (!isConnected ? "● DISCONNECTED" : "")
        color: "#ff0055"
        font.pixelSize: isEmergency ? 42 : 50
        font.bold: true
        font.letterSpacing: 2.0
        visible: isEmergency || !isConnected
        opacity: (cpRoot.forgingOpen || cpRoot.flockingOpen) ? 0.1 : 0.8
    }

    RowLayout {
        anchors { right: parent.right; top: parent.top; margins: 12 }
        spacing: 10
        z: 100

        Rectangle {
            Layout.preferredWidth: Math.max(150, forgingTxt.implicitWidth + 30); Layout.preferredHeight: 34; radius: 8
            color: Qt.rgba(49/255, 224/255, 255/255, 0.12); border.color: "#31E0FF"
            scale: forgingHover.containsMouse ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 150 } }
            Text { id: forgingTxt; anchors.centerIn: parent; text: "⛭ FORAGING"; color: "#31E0FF"; font.bold: true; font.letterSpacing: 1.0 }
            MouseArea { id: forgingHover; anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: { foragingPopupObj.open(); }                
            }
        }

        Rectangle {
            Layout.preferredWidth: Math.max(170, taskTxt.implicitWidth + 30); Layout.preferredHeight: 34; radius: 8
            color: Qt.rgba(49/255, 224/255, 255/255, 0.12)
            border.color: "#31E0FF"
            scale: taskHoverArea.containsMouse ? 1.05 : 1.0
            Behavior on scale { NumberAnimation { duration: 150 } }

            Text { id: taskTxt; anchors.centerIn: parent; text: "🧭 TASK ALLOCATION"; color: "#31E0FF"; font.bold: true; font.letterSpacing: 1.0; font.pixelSize: 13 }
            
            MouseArea { id: taskHoverArea
                anchors.fill: parent
                hoverEnabled: true;
                cursorShape: Qt.PointingHandCursor
                
                onClicked: {
                    if (typeof root !== 'undefined') {
                        root.currentScreen = "nav"
                    }
                }

            }
        }
    }

    Connections {
        target: mapBridge ? mapBridge : null

        // ── New robot discovered via /scan topic → add to ComboBox ────────────
        function onRobotDiscovered(deviceId) {
            var ids = cpRoot.scanRobotIds.slice()
            if (ids.indexOf(deviceId) === -1) {
                ids.push(deviceId)
                ids.sort(function(a, b) { return a - b })
                cpRoot.scanRobotIds = ids
            }
        }

        // ── Per-robot 2D laser-scan data ──────────────────────────────────────
        function onLaserScanReceived(deviceId, points) {
            var cache = Object.assign({}, cpRoot.scanPointsByRobot)
            cache[deviceId] = points
            cpRoot.scanPointsByRobot = cache
            // Repaint only if this robot is the selected one or "All" is selected
            if (cpRoot.selectedScanRobotId === 0 || cpRoot.selectedScanRobotId === deviceId)
                mapCanvas.requestPaint()
        }

        function onMapDataReceived(data) {
            if (!data) return
            var topic = (data.topic ? String(data.topic).toLowerCase() : "")
            var needsRepaint = false

            // Check if data is specifically 2D map topic
            if (topic.indexOf("map") !== -1 || data.topic === undefined) {
                // Topic string comparison prevents clearing when 3D lidar comes in
                if (data.data && data.width && data.height) {
                    cpRoot.mapData = data;
                    cpRoot.mapResolution = data.resolution || 0.05;
                    cpRoot.mapOriginX = data.origin ? data.origin.x || 0 : 0;
                    cpRoot.mapOriginY = data.origin ? data.origin.y || 0 : 0;
                    needsRepaint = true
                }
            }

            // Path planning updates
            if (topic.indexOf("path") !== -1 || topic.indexOf("plan") !== -1 || data.path || data.poses || data.points) {
                if (cpRoot.applyPathsFromMessage(data)) needsRepaint = true
            }

            // Target updates
            if (topic.indexOf("target") !== -1 || topic.indexOf("goal") !== -1 || data.target || data.targets || data.target_points) {
                if (cpRoot.applyTargetsFromMessage(data)) needsRepaint = true
            }

            // Robot position updates
            if (topic.indexOf("pose") !== -1 || topic.indexOf("odom") !== -1 || topic.indexOf("robot_position") !== -1 || data.robot_id !== undefined || data.robot_positions || data.robots) {
                if (cpRoot.applyRobotPositionsFromMessage(data)) needsRepaint = true
            }

            if (needsRepaint) mapCanvas.requestPaint()
        }

        function onImageReceived(topic, base64) {
            var lowerTopic = topic ? topic.toLowerCase() : "";
            if (lowerTopic.indexOf("map") !== -1) {
                if (base64 && base64.startsWith("/9j/")) {
                    cpRoot.mapImageSource = "data:image/jpeg;base64," + base64;
                } else if (base64 && base64.startsWith("iVB")) {
                    cpRoot.mapImageSource = "data:image/png;base64," + base64;
                } else {
                    cpRoot.mapImageSource = "data:image/png;base64," + base64;
                }
            }
        }
    }
    
    ForagingPopup {
        id: foragingPopupObj
    }
    
    Component.onCompleted: {
        mapCanvas.requestPaint()
        // Request map data on startup
        if (mapBridge && mapBridge.isConnected) {
            mapBridge.requestMapData(0); // Request general map data
        }
    }
}
