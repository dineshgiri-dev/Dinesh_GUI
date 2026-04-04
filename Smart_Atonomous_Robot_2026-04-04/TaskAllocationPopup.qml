import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import "."

Rectangle {
    id: taskPopupRoot
    Theme { id: theme }
    anchors.fill: parent
    color: "#88000000"
    z: 1000

    // ── Colour tokens ─────────────────────────────────────────────────────
    property color borderC  : root ? root.borderColor   : theme.glassStroke
    property color blue     : root ? root.primary       : theme.neon
    property color greenC   : root ? root.success       : theme.neon
    property color accentC  : root ? root.primaryLight  : theme.cyan
    property color dangerC  : root ? root.danger        : "#ef4444"
    property color bg       : root ? root.surface       : theme.bg1
    property color bgLight  : root ? root.surfaceLight  : theme.glass0
    property color textC    : root ? root.textPrimary   : theme.textPrimary
    property color textSec  : root ? root.textSecondary : theme.textSecondary

    // ── State ─────────────────────────────────────────────────────────────
    property var  existingTasks: []   // [{robot_id, task_name, x, y, status}]
    property var  ackStatus:     ({}) // {robotId: {success, message}}
    property bool addMode:       false
    property bool modifyMode:    false
    property int  modifyIndex:   -1

    // ── Helpers ───────────────────────────────────────────────────────────
    function statusColor(s) {
        if (!s) return textSec
        var l = s.toLowerCase()
        if (l === "completed" || l === "done")          return greenC
        if (l === "in_progress" || l === "active")      return accentC
        if (l === "failed"     || l === "rejected")     return dangerC
        return textSec
    }

    function applyExistingTasks(data) {
        var tasks = []
        if (data.tasks && data.tasks.length) {
            for (var i = 0; i < data.tasks.length; i++) {
                var t = data.tasks[i]
                tasks.push({
                    robot_id:  t.robot_id  || t.robotId  || 0,
                    task_name: t.task_name || t.taskName || ("Task " + (i + 1)),
                    x:         t.x  !== undefined ? t.x  : (t.target_x || 0),
                    y:         t.y  !== undefined ? t.y  : (t.target_y || 0),
                    status:    t.status || "Pending"
                })
            }
        }
        existingTasks = tasks
    }

    function resetForm() {
        addMode      = false
        modifyMode   = false
        modifyIndex  = -1
        taskNameInput.text         = ""
        xInput.text                = ""
        yInput.text                = ""
        robotSelector.currentIndex = 0
    }

    // ── Live data ─────────────────────────────────────────────────────────
    Connections {
        target: (typeof mapBridge !== 'undefined' && mapBridge) ? mapBridge : null

        function onMapDataReceived(data) {
            if (data && data.topic === "existing_tasks")
                taskPopupRoot.applyExistingTasks(data)
        }

        function onTaskAckReceived(robotId, taskName, success, message) {
            var m = Object.assign({}, taskPopupRoot.ackStatus)
            m[robotId] = { success: success, message: message }
            taskPopupRoot.ackStatus = m
            // Update task row status
            var tasks = taskPopupRoot.existingTasks.slice()
            for (var i = 0; i < tasks.length; i++) {
                if (tasks[i].robot_id === robotId && tasks[i].task_name === taskName)
                    tasks[i] = Object.assign({}, tasks[i], { status: success ? "Assigned" : "Failed" })
            }
            taskPopupRoot.existingTasks = tasks
            ackTimer.restart()
        }
    }

    Timer { id: ackTimer; interval: 4000; onTriggered: taskPopupRoot.ackStatus = ({}) }

    // ── Overlay dismiss (below card) ──────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: {
            taskPopupRoot.resetForm()
            if (root) root.taskAllocationPopupVisible = false
        }
    }

    // ── Modal card ────────────────────────────────────────────────────────
    Rectangle {
        z: 1
        anchors.centerIn: parent
        width:  Math.min(680, taskPopupRoot.width  - 48)
        height: Math.min(580, taskPopupRoot.height - 48)
        radius: 16
        color:  bg
        border.color: blue
        border.width: 1.5

        // Swallow clicks so overlay doesn't close the card
        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 12

            // ── Header ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 38; height: 38; radius: 10
                    color: Qt.rgba(blue.r, blue.g, blue.b, 0.15)
                    Text { anchors.centerIn: parent; text: "🧭"; font.pixelSize: 20 }
                }

                ColumnLayout {
                    spacing: 1
                    Text {
                        text: "TASK ALLOCATION"
                        color: textC; font.pixelSize: 16; font.bold: true; font.letterSpacing: 1
                    }
                    Text {
                        text: "Existing tasks auto-load. One waypoint per robot."
                        color: textSec; font.pixelSize: 11
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 32; height: 32; radius: 8
                    color: xHov.containsMouse ? "#cc2020" : Qt.rgba(1,1,1,0.07)
                    border.color: borderC; border.width: 1
                    Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 15; font.bold: true }
                    MouseArea {
                        id: xHov; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { taskPopupRoot.resetForm(); if (root) root.taskAllocationPopupVisible = false }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: borderC; opacity: 0.4 }

            // ── ACK banner ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 34; radius: 8
                visible: Object.keys(taskPopupRoot.ackStatus).length > 0
                color: {
                    var k = Object.keys(taskPopupRoot.ackStatus)
                    return k.length && taskPopupRoot.ackStatus[k[0]].success
                           ? Qt.rgba(greenC.r, greenC.g, greenC.b, 0.15)
                           : Qt.rgba(dangerC.r, dangerC.g, dangerC.b, 0.15)
                }
                border.color: {
                    var k = Object.keys(taskPopupRoot.ackStatus)
                    return k.length && taskPopupRoot.ackStatus[k[0]].success ? greenC : dangerC
                }
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    font.pixelSize: 12; font.bold: true
                    color: {
                        var k = Object.keys(taskPopupRoot.ackStatus)
                        return k.length && taskPopupRoot.ackStatus[k[0]].success ? greenC : dangerC
                    }
                    text: {
                        var k = Object.keys(taskPopupRoot.ackStatus)
                        if (!k.length) return ""
                        var a = taskPopupRoot.ackStatus[k[0]]
                        return a.success
                            ? "✔  Task acknowledged — Robot " + k[0]
                            : "✘  Rejected — Robot " + k[0] + (a.message ? ": " + a.message : "")
                    }
                }
            }

            // ── Add / Modify form (no clip — required for ComboBox popup) ─
            Rectangle {
                Layout.fillWidth: true
                // Only visible when addMode; no clip so ComboBox dropdown is not cut off
                visible: taskPopupRoot.addMode
                height:  taskPopupRoot.addMode ? formCol.implicitHeight + 24 : 0
                radius: 10
                color:  bgLight
                border.color: taskPopupRoot.modifyMode ? accentC : blue
                border.width: 1

                ColumnLayout {
                    id: formCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10

                    // Form title
                    Text {
                        text: taskPopupRoot.modifyMode ? "✏  Modify Task" : "➕  New Task"
                        color: taskPopupRoot.modifyMode ? accentC : blue
                        font.bold: true; font.pixelSize: 13
                    }

                    GridLayout {
                        columns: 2
                        columnSpacing: 14; rowSpacing: 8
                        Layout.fillWidth: true

                        // Robot
                        Text { text: "Robot"; color: textSec; font.pixelSize: 12 }
                        ComboBox {
                            id: robotSelector
                            Layout.fillWidth: true
                            model: {
                                var ids = []
                                for (var i = 1; i <= 6; i++) ids.push("Robot " + i)
                                return ids
                            }
                            background: Rectangle {
                                implicitHeight: 34; radius: 8
                                color: bg; border.color: borderC; border.width: 1
                            }
                            contentItem: Text {
                                leftPadding: 10
                                text: robotSelector.displayText
                                color: textC; font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        // Task name
                        Text { text: "Task Name"; color: textSec; font.pixelSize: 12 }
                        Rectangle {
                            Layout.fillWidth: true; height: 34; radius: 8
                            color: bg; border.color: borderC; border.width: 1
                            TextInput {
                                id: taskNameInput
                                anchors { fill: parent; margins: 8 }
                                color: textC; font.pixelSize: 13
                                Text {
                                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                    text: "e.g. Exploration"
                                    color: Qt.rgba(textSec.r, textSec.g, textSec.b, 0.45)
                                    font.pixelSize: 13
                                    visible: !taskNameInput.text.length && !taskNameInput.activeFocus
                                }
                            }
                        }

                        // X
                        Text { text: "Target X"; color: textSec; font.pixelSize: 12 }
                        Rectangle {
                            Layout.fillWidth: true; height: 34; radius: 8
                            color: bg; border.color: borderC; border.width: 1
                            TextInput {
                                id: xInput
                                anchors { fill: parent; margins: 8 }
                                color: textC; font.pixelSize: 13
                                validator: DoubleValidator {}
                                Text {
                                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                    text: "0.0"
                                    color: Qt.rgba(textSec.r, textSec.g, textSec.b, 0.45)
                                    font.pixelSize: 13
                                    visible: !xInput.text.length && !xInput.activeFocus
                                }
                            }
                        }

                        // Y
                        Text { text: "Target Y"; color: textSec; font.pixelSize: 12 }
                        Rectangle {
                            Layout.fillWidth: true; height: 34; radius: 8
                            color: bg; border.color: borderC; border.width: 1
                            TextInput {
                                id: yInput
                                anchors { fill: parent; margins: 8 }
                                color: textC; font.pixelSize: 13
                                validator: DoubleValidator {}
                                Text {
                                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                    text: "0.0"
                                    color: Qt.rgba(textSec.r, textSec.g, textSec.b, 0.45)
                                    font.pixelSize: 13
                                    visible: !yInput.text.length && !yInput.activeFocus
                                }
                            }
                        }
                    }

                    // Action row inside form
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10

                        Item { Layout.fillWidth: true }

                        // Discard
                        Rectangle {
                            width: 110; height: 34; radius: 8
                            color: discardHov.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                            border.color: borderC; border.width: 1
                            Text { anchors.centerIn: parent; text: "Discard"; color: textSec; font.pixelSize: 13 }
                            MouseArea {
                                id: discardHov; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: taskPopupRoot.resetForm()
                            }
                        }

                        // Assign / Deploy
                        Rectangle {
                            width: 160; height: 34; radius: 8
                            color: submitHov.containsMouse ? Qt.lighter(blue, 1.18) : blue
                            Behavior on color { ColorAnimation { duration: 110 } }
                            Text {
                                anchors.centerIn: parent
                                text: taskPopupRoot.modifyMode ? "🚀 Deploy Task" : "✔ Assign To Robot"
                                color: "black"; font.pixelSize: 13; font.bold: true
                            }
                            MouseArea {
                                id: submitHov; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var rid   = robotSelector.currentIndex + 1
                                    var tname = taskNameInput.text.trim() || ("Task for Robot " + rid)
                                    var tx    = parseFloat(xInput.text) || 0.0
                                    var ty    = parseFloat(yInput.text) || 0.0

                                    if (typeof mapBridge !== 'undefined' && mapBridge)
                                        mapBridge.assignTaskToRobot(rid, tx, ty, tname)

                                    var tasks = taskPopupRoot.existingTasks.slice()
                                    if (taskPopupRoot.modifyMode
                                        && taskPopupRoot.modifyIndex >= 0
                                        && taskPopupRoot.modifyIndex < tasks.length) {
                                        tasks[taskPopupRoot.modifyIndex] =
                                            { robot_id: rid, task_name: tname, x: tx, y: ty, status: "Pending ACK" }
                                    } else {
                                        var found = false
                                        for (var i = 0; i < tasks.length; i++) {
                                            if (tasks[i].robot_id === rid) {
                                                tasks[i] = { robot_id: rid, task_name: tname, x: tx, y: ty, status: "Pending ACK" }
                                                found = true; break
                                            }
                                        }
                                        if (!found)
                                            tasks.push({ robot_id: rid, task_name: tname, x: tx, y: ty, status: "Pending ACK" })
                                    }
                                    taskPopupRoot.existingTasks = tasks
                                    taskPopupRoot.resetForm()
                                }
                            }
                        }
                    }
                }
            }

            // ── Task list ──────────────────────────────────────────────────
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Column {
                    width: parent.width
                    spacing: 8

                    Item {
                        width: parent.width; height: 70
                        visible: taskPopupRoot.existingTasks.length === 0
                        Text {
                            anchors.centerIn: parent
                            text: "No tasks yet — click  ＋ Add Task  to assign a waypoint."
                            color: textSec; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Repeater {
                        model: taskPopupRoot.existingTasks
                        delegate: Rectangle {
                            width: parent ? parent.width - 2 : 0
                            height: 56; radius: 10
                            color: bgLight
                            border.color: {
                                var ack = taskPopupRoot.ackStatus[modelData.robot_id]
                                return ack ? (ack.success ? greenC : dangerC) : borderC
                            }
                            border.width: 1

                            RowLayout {
                                anchors { fill: parent; margins: 12 }
                                spacing: 10

                                Rectangle {
                                    width: 34; height: 34; radius: 8
                                    color: Qt.rgba(blue.r, blue.g, blue.b, 0.15)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "R" + modelData.robot_id
                                        color: blue; font.bold: true; font.pixelSize: 13
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    Text {
                                        text: modelData.task_name
                                        color: textC; font.bold: true; font.pixelSize: 13
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "X: " + (modelData.x || 0).toFixed(2) +
                                              "   Y: " + (modelData.y || 0).toFixed(2)
                                        color: textSec; font.pixelSize: 11
                                    }
                                }

                                Rectangle {
                                    height: 22
                                    width: chipTxt.implicitWidth + 18
                                    radius: 11
                                    color: Qt.rgba(statusColor(modelData.status).r,
                                                   statusColor(modelData.status).g,
                                                   statusColor(modelData.status).b, 0.18)
                                    border.color: statusColor(modelData.status)
                                    border.width: 1
                                    Text {
                                        id: chipTxt
                                        anchors.centerIn: parent
                                        text: modelData.status || "Pending"
                                        color: statusColor(modelData.status)
                                        font.pixelSize: 10; font.bold: true
                                    }
                                }

                                Rectangle {
                                    height: 26; width: 66; radius: 7
                                    color: modHov.containsMouse
                                           ? Qt.rgba(accentC.r, accentC.g, accentC.b, 0.25)
                                           : Qt.rgba(accentC.r, accentC.g, accentC.b, 0.10)
                                    border.color: accentC; border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✏ Modify"
                                        color: accentC; font.pixelSize: 10; font.bold: true
                                    }
                                    MouseArea {
                                        id: modHov; anchors.fill: parent
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var t = taskPopupRoot.existingTasks[index]
                                            robotSelector.currentIndex  = Math.max(0, (t.robot_id || 1) - 1)
                                            taskNameInput.text          = t.task_name || ""
                                            xInput.text                 = String(t.x || 0)
                                            yInput.text                 = String(t.y || 0)
                                            taskPopupRoot.modifyIndex   = index
                                            taskPopupRoot.modifyMode    = true
                                            taskPopupRoot.addMode       = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: borderC; opacity: 0.4 }

            // ── Bottom bar ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 10

                Rectangle {
                    Layout.preferredWidth: 120; Layout.preferredHeight: 38; radius: 9
                    color: taskPopupRoot.addMode
                           ? Qt.rgba(dangerC.r, dangerC.g, dangerC.b, 0.15)
                           : Qt.rgba(blue.r, blue.g, blue.b, 0.15)
                    border.color: taskPopupRoot.addMode ? dangerC : blue; border.width: 1
                    scale: addHov.containsMouse ? 1.04 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: taskPopupRoot.addMode ? "✕ Cancel" : "+ Add Task"
                        color: taskPopupRoot.addMode ? dangerC : blue
                        font.pixelSize: 13; font.bold: true
                    }
                    MouseArea {
                        id: addHov; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (taskPopupRoot.addMode) {
                                taskPopupRoot.resetForm()
                            } else {
                                taskPopupRoot.resetForm()
                                taskPopupRoot.addMode = true
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 100; Layout.preferredHeight: 38; radius: 9
                    color: doneHov.containsMouse ? Qt.rgba(1,1,1,0.09) : "transparent"
                    border.color: borderC; border.width: 1
                    Text { anchors.centerIn: parent; text: "Done"; color: textC; font.pixelSize: 13; font.bold: true }
                    MouseArea {
                        id: doneHov; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { taskPopupRoot.resetForm(); if (root) root.taskAllocationPopupVisible = false }
                    }
                }
            }
        }
    }
}
