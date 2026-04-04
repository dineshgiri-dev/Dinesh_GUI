import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: foragingPopup
    Theme { id: theme }
    width: 600
    height: 520
    modal: true
    focus: true
    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property var patternPoints: []
    property string currentGuessedPattern: "None Drawn"
    property string errorMessage: ""
    property real minSampleDistance: 2.0
    property real simplifyTolerance: 2.5
    property bool isDrawing: false

    // ---------- Shape recognition (Circle, Square, Hexagon, Linear, Triangle) ----------
    function preprocessPoints(points) {
        // Remove points that are too close together.
        if (points.length < 2) return points;
        let filtered = [points[0]];
        for (let i = 1; i < points.length; i++) {
            let prev = filtered[filtered.length - 1];
            let curr = points[i];
            let dx = curr.x - prev.x;
            let dy = curr.y - prev.y;
            if (Math.sqrt(dx*dx + dy*dy) >= minSampleDistance) {
                filtered.push(curr);
            }
        }
        return simplifyPath(filtered, simplifyTolerance);
    }

    function distance(a, b) {
        let dx = a.x - b.x;
        let dy = a.y - b.y;
        return Math.sqrt(dx*dx + dy*dy);
    }

    function perpendicularDistance(point, lineStart, lineEnd) {
        let dx = lineEnd.x - lineStart.x;
        let dy = lineEnd.y - lineStart.y;
        if (dx === 0 && dy === 0) return distance(point, lineStart);
        let t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (dx*dx + dy*dy);
        let proj = {
            x: lineStart.x + t * dx,
            y: lineStart.y + t * dy
        };
        return distance(point, proj);
    }

    function simplifyPath(points, epsilon) {
        if (points.length <= 2) return points;
        let maxDist = 0;
        let index = 0;
        for (let i = 1; i < points.length - 1; i++) {
            let d = perpendicularDistance(points[i], points[0], points[points.length - 1]);
            if (d > maxDist) {
                index = i;
                maxDist = d;
            }
        }
        if (maxDist > epsilon) {
            let left = simplifyPath(points.slice(0, index + 1), epsilon);
            let right = simplifyPath(points.slice(index), epsilon);
            return left.slice(0, left.length - 1).concat(right);
        }
        return [points[0], points[points.length - 1]];
    }

    function appendPoint(px, py) {
        let pt = {x: px, y: py};
        if (patternPoints.length === 0) {
            patternPoints = [pt];
            return;
        }
        let last = patternPoints[patternPoints.length - 1];
        let segLen = distance(last, pt);
        if (segLen < minSampleDistance) return;
        // Interpolate intermediate points to avoid gaps on fast mouse movement.
        let steps = Math.max(1, Math.floor(segLen / minSampleDistance));
        let nextPoints = patternPoints.slice();
        for (let s = 1; s <= steps; s++) {
            let t = s / steps;
            nextPoints.push({
                x: last.x + (pt.x - last.x) * t,
                y: last.y + (pt.y - last.y) * t
            });
        }
        patternPoints = nextPoints;
    }

    function calculateAngle(p1, p2, p3) {
        // Angle at p2 in degrees
        let v1 = {x: p1.x - p2.x, y: p1.y - p2.y};
        let v2 = {x: p3.x - p2.x, y: p3.y - p2.y};
        let dot = v1.x * v2.x + v1.y * v2.y;
        let mag1 = Math.sqrt(v1.x*v1.x + v1.y*v1.y);
        let mag2 = Math.sqrt(v2.x*v2.x + v2.y*v2.y);
        if (mag1 === 0 || mag2 === 0) return 180;
        let cos = dot / (mag1 * mag2);
        cos = Math.max(-1, Math.min(1, cos));
        return Math.acos(cos) * 180 / Math.PI;
    }

    function detectCorners(points, angleThreshold = 140) {
        // Count sharp corners (angle < angleThreshold)
        if (points.length < 7) return 0;
        let cornerCount = 0;
        let stride = Math.max(1, Math.floor(points.length / 40));
        for (let i = stride; i < points.length - stride; i += stride) {
            let angle = calculateAngle(points[i - stride], points[i], points[i + stride]);
            if (angle < angleThreshold) cornerCount++;
        }
        return cornerCount;
    }

    function estimateVertexCount(points) {
        if (!points || points.length < 6) return 0;
        let tol = Math.max(2.2, simplifyTolerance + 0.8);
        let simplified = simplifyPath(points, tol);
        if (simplified.length > 2) {
            let first = simplified[0];
            let last = simplified[simplified.length - 1];
            if (distance(first, last) <= 10) {
                simplified = simplified.slice(0, simplified.length - 1);
            }
        }
        return simplified.length;
    }

    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    function scoreByDistance(value, target, tolerance) {
        return clamp01(1 - Math.abs(value - target) / tolerance);
    }

    function guessPattern() {
        if (patternPoints.length < 5) return "Unknown";

        let pts = preprocessPoints(patternPoints);
        if (pts.length < 5) return "Unknown";
        let startEndDist = distance(pts[0], pts[pts.length - 1]);

        // Bounding box
        let minX = 9999, maxX = -9999, minY = 9999, maxY = -9999;
        for (let p of pts) {
            if (p.x < minX) minX = p.x;
            if (p.x > maxX) maxX = p.x;
            if (p.y < minY) minY = p.y;
            if (p.y > maxY) maxY = p.y;
        }
        let width = maxX - minX;
        let height = maxY - minY;
        if (width < 8 || height < 8) return "Unknown";
        let aspectRatio = Math.max(width, height) / (Math.min(width, height) + 0.001);
        let bboxArea = width * height;

        // Area (shoelace) and perimeter
        let area = 0;
        let perimeter = 0;
        let n = pts.length;
        for (let i = 0; i < n; i++) {
            let j = (i + 1) % n;
            area += pts[i].x * pts[j].y - pts[j].x * pts[i].y;
            let dx = pts[j].x - pts[i].x;
            let dy = pts[j].y - pts[i].y;
            perimeter += Math.sqrt(dx*dx + dy*dy);
        }
        area = Math.abs(area) / 2;

        // Circularity
        let circularity = (4 * Math.PI * area) / (perimeter * perimeter);
        if (circularity > 1) circularity = 1;
        let fillRatio = (bboxArea > 0) ? (area / bboxArea) : 0;
        let closeEnough = startEndDist <= Math.max(14, Math.min(width, height) * 0.12);
        let effectiveCorners = detectCorners(pts, 145);

        // Open strokes are usually lines, unless heavily curved.
        if (!closeEnough && aspectRatio > 1.7 && fillRatio < 0.28) {
            return "Linear";
        }

        let vertexCount = estimateVertexCount(pts);
        let isSquareLike = closeEnough &&
                           aspectRatio <= 1.45 &&
                           fillRatio >= 0.48 &&
                           fillRatio <= 0.92 &&
                           ((vertexCount >= 4 && vertexCount <= 6) || (effectiveCorners >= 3 && effectiveCorners <= 6));
        if (isSquareLike) return "Square";

        // Strong direct rules first
        if (closeEnough && circularity > 0.62 && effectiveCorners <= 4 && aspectRatio < 1.55) return "Circle";
        if (closeEnough && effectiveCorners >= 3 && effectiveCorners <= 5 && circularity >= 0.28 && circularity <= 0.72) return "Triangle";
        if (closeEnough && effectiveCorners >= 5 && effectiveCorners <= 9 && circularity >= 0.28 && circularity <= 0.78) return "Hexagon";
        if ((!closeEnough && aspectRatio > 1.8 && fillRatio < 0.35) ||
            (aspectRatio > 2.2 && fillRatio < 0.22)) return "Linear";

        // Soft fallback scorer: avoids frequent "Unknown" on hand sketches.
        let circleScore =
                0.45 * scoreByDistance(circularity, 0.78, 0.42) +
                0.25 * scoreByDistance(aspectRatio, 1.0, 0.9) +
                0.20 * scoreByDistance(effectiveCorners, 2, 4) +
                0.10 * (closeEnough ? 1 : 0);

        let triangleScore =
                0.35 * scoreByDistance(effectiveCorners, 3, 2.5) +
                0.25 * scoreByDistance(circularity, 0.52, 0.34) +
                0.20 * scoreByDistance(fillRatio, 0.34, 0.24) +
                0.20 * (closeEnough ? 1 : 0);

        let squareScore =
                0.30 * scoreByDistance(vertexCount, 4, 2.0) +
                0.25 * scoreByDistance(aspectRatio, 1.0, 0.6) +
                0.20 * scoreByDistance(fillRatio, 0.70, 0.35) +
                0.15 * scoreByDistance(effectiveCorners, 4, 3.0) +
                0.10 * (closeEnough ? 1 : 0);

        let hexagonScore =
                0.35 * scoreByDistance(effectiveCorners, 6, 3.5) +
                0.25 * scoreByDistance(circularity, 0.64, 0.35) +
                0.20 * scoreByDistance(fillRatio, 0.58, 0.35) +
                0.20 * (closeEnough ? 1 : 0);

        let linearScore =
                0.45 * scoreByDistance(aspectRatio, 3.4, 2.4) +
                0.35 * scoreByDistance(fillRatio, 0.08, 0.22) +
                0.20 * (closeEnough ? 0 : 1);

        let bestName = "Unknown";
        let bestScore = 0.0;
        let candidates = [
            {name: "Circle", score: circleScore},
            {name: "Triangle", score: triangleScore},
            {name: "Square", score: squareScore},
            {name: "Hexagon", score: hexagonScore},
            {name: "Linear", score: linearScore}
        ];
        for (let i = 0; i < candidates.length; i++) {
            if (candidates[i].score > bestScore) {
                bestScore = candidates[i].score;
                bestName = candidates[i].name;
            }
        }
        return bestScore >= 0.38 ? bestName : "Unknown";
    }

    background: Rectangle {
        color: theme.bg1
        radius: 12
        border.color: theme.glassStroke
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        // Header with close button
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "⛭ Draw Foraging Target Region"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
            Button {
                text: "✕"
                scale: hovered ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                background: Rectangle {
                    radius: 16
                    color: parent.hovered ? Qt.rgba(255/255, 77/255, 109/255, 0.22) : Qt.rgba(49/255, 224/255, 255/255, 0.12)
                    border.color: parent.hovered ? "#FF4D6D" : "#31E0FF"
                    border.width: 1
                }
                contentItem: Text {
                    text: parent.text
                    color: parent.hovered ? "#FF9AAE" : "#31E0FF"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: foragingPopup.close()
            }
        }

        Text {
            text: "Sketch a region on the canvas below. Click CLEAR to start over."
            color: theme.textSecondary
            font.pixelSize: 12
            Layout.alignment: Qt.AlignHCenter
        }

        // Drawing canvas
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: theme.glass0
            border.color: theme.glassStroke
            border.width: 2
            clip: true

            Canvas {
                id: drawingCanvas
                anchors.fill: parent

                onPaint: {
                    let ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (patternPoints.length < 2) return;

                    ctx.beginPath();
                    ctx.lineWidth = 4;
                    ctx.strokeStyle = theme.neon;
                    ctx.moveTo(patternPoints[0].x, patternPoints[0].y);
                    for (let i = 1; i < patternPoints.length; i++) {
                        ctx.lineTo(patternPoints[i].x, patternPoints[i].y);
                    }
                    ctx.stroke();

                    // Light fill if closed
                    if (patternPoints.length > 2) {
                        ctx.fillStyle = Qt.rgba(59, 130, 246, 0.2);
                        ctx.fill();
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true

                    onPressed: (mouse) => {
                        errorMessage = "";
                        patternPoints = [];
                        isDrawing = true;
                        appendPoint(mouse.x, mouse.y);
                        drawingCanvas.requestPaint();
                    }

                    onPositionChanged: (mouse) => {
                        if (!isDrawing) return;
                        appendPoint(mouse.x, mouse.y);
                        drawingCanvas.requestPaint();
                    }

                    onReleased: (mouse) => {
                        if (!isDrawing) return;
                        isDrawing = false;
                        appendPoint(mouse.x, mouse.y);
                        // Close loop only when end is near start.
                        if (patternPoints.length > 2 &&
                            distance(patternPoints[0], patternPoints[patternPoints.length - 1]) <= 20) {
                            let closed = patternPoints.slice();
                            closed.push({x: patternPoints[0].x, y: patternPoints[0].y});
                            patternPoints = closed;
                        }
                        drawingCanvas.requestPaint();
                        currentGuessedPattern = guessPattern();
                    }
                }
            }
        }

        // Bottom row: clear button and guess display
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                text: "🧹 CLEAR CANVAS"
                scale: hovered ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                Layout.preferredHeight: 36
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? Qt.rgba(255/255, 77/255, 109/255, 0.22) : Qt.rgba(49/255, 224/255, 255/255, 0.12)
                    border.color: parent.hovered ? "#FF4D6D" : "#31E0FF"
                    border.width: 1
                }
                contentItem: Text {
                    text: parent.text
                    color: parent.hovered ? "#FF9AAE" : "#31E0FF"
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    patternPoints = [];
                    currentGuessedPattern = "None Drawn";
                    errorMessage = "";
                    drawingCanvas.requestPaint();
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "Guessed Pattern:"
                color: "#A2A5CF"
                font.pixelSize: 14
                font.bold: true
            }
            Text {
                text: currentGuessedPattern
                color: (currentGuessedPattern === "None Drawn" || currentGuessedPattern.startsWith("Unknown")) ? "#A2A5CF" : "#10b981"
                font.pixelSize: 16
                font.bold: true
            }
        }

        // Error message
        Text {
            text: errorMessage
            color: "#ef4444"
            font.pixelSize: 13
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
            visible: errorMessage !== ""
        }

        // Send button
        Button {
            Layout.fillWidth: true
            scale: hovered ? 1.05 : 1.0
            Behavior on scale { NumberAnimation { duration: 150 } }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            Layout.preferredHeight: 46
            background: Rectangle {
                radius: 8
                color: parent.hovered ? Qt.rgba(49/255, 224/255, 255/255, 0.24) : Qt.rgba(49/255, 224/255, 255/255, 0.12)
                border.color: "#31E0FF"
                border.width: 1
            }
            contentItem: Text {
                text: "SEND FORAGING PATTERN"
                color: "#31E0FF"
                font.bold: true
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                if (currentGuessedPattern === "None Drawn" || patternPoints.length < 3) {
                    errorMessage = "Please draw a pattern on the canvas first.";
                    return;
                }
                if (typeof mapBridge !== 'undefined' && mapBridge) {
                    mapBridge.sendForagingPattern(patternPoints);
                }
                foragingPopup.close();
            }
        }
    }
}
