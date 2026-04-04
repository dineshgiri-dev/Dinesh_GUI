import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt5Compat.GraphicalEffects

Popup {
    id: simConfigPopup
    Theme { id: theme }
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape

    onOpened: {
        currentStep = 0
        refreshSimulationWorlds()
    }

    onClosed: {
        // Reset step so next open always starts at page 1
        currentStep = 0
    }

    property var appRoot: null
    property color primary: appRoot ? appRoot.primary : theme.neon
    property color surface: appRoot ? appRoot.surface : theme.bg1
    property color surfaceLight: appRoot ? appRoot.surfaceLight : theme.glass0
    property color textPrimary: appRoot ? appRoot.textPrimary : theme.textPrimary
    property color textSecondary: appRoot ? appRoot.textSecondary : theme.textSecondary
    property color borderColor: appRoot ? appRoot.borderColor : theme.glassStroke
    property color danger: appRoot ? appRoot.danger : theme.danger
    property color success: appRoot ? appRoot.success : theme.neon

    width: 700
    height: 600
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    property int currentStep: 0
    property string selectedWorld: worldComboBox.currentText

    // Persistent selection and robot initial positions (0-based index for robots 1-6)
    property var robotSelected: [true, true, true, true, true, true]
    property var robotPosX: [0, 0, 0, 0, 0, 0]
    property var robotPosY: [0, 0, 0, 0, 0, 0]

    // Derived list of 1-based robot IDs that are currently selected
    property var selectedRobotList: {
        var list = []
        for (var i = 0; i < 6; i++)
            if (robotSelected[i]) list.push(i + 1)
        return list
    }

    // Populated by merging Docker + local + WebSocket sources.
    property var worldFileList: []
    property bool worldsLoading: false

    // Tracks how many async queries are still in-flight so we only
    // clear the loading spinner once ALL sources have responded.
    property int _pendingWorldQueries: 0

    // Remember which world was selected so we can restore it after a refresh.
    property string _lastSelectedWorld: ""

    function normalizeWorldName(name) {
        var n = String(name).trim()
        if (n.length === 0)
            return ""
        if (n.indexOf("webots_") === 0)
            n = n.substring(7)
        if (n.length > 4 && n.substring(n.length - 4).toLowerCase() === ".wbt")
            n = n.substring(0, n.length - 4)
        return n
    }

    function refreshSimulationWorlds() {
        if (typeof mapBridge === "undefined")
            return

        // Save the current selection so we can restore it after the refresh.
        _lastSelectedWorld = worldComboBox.currentText ? String(worldComboBox.currentText).trim() : ""

        worldsLoading = true
        worldFileList = []
        worldComboBox.currentIndex = -1

        // queryDockerWebotsWorlds and queryLocalWebotsWorlds always emit
        // simulationWorldsReceived (even on failure/empty), so we track them.
        // requestSimulationWorlds is a WebSocket call that may never reply
        // (offline), so we don't count it in the pending total.
        _pendingWorldQueries = 2
        worldLoadTimeout.restart()
        mapBridge.queryDockerWebotsWorlds()
        mapBridge.queryLocalWebotsWorlds("")
        // Fire the WebSocket request as a best-effort bonus source.
        mapBridge.requestSimulationWorlds()
    }

    Connections {
        target: (typeof mapBridge !== 'undefined') ? mapBridge : null

        function onSimulationWorldsReceived(worlds) {
            // Decrement pending counter; loading ends when all sources are done.
            if (_pendingWorldQueries > 0)
                _pendingWorldQueries -= 1

            // Merge new worlds into the accumulated list (dedup).
            var merged = worldFileList ? worldFileList.slice() : []
            var seen = ({})
            for (var j = 0; j < merged.length; j++)
                seen[String(merged[j])] = true

            for (var i = 0; i < worlds.length; i++) {
                var wName = normalizeWorldName(worlds[i])
                if (wName.length === 0)
                    continue
                if (wName.toLowerCase().indexOf("env_") !== 0)
                    continue
                if (seen[wName] === true)
                    continue
                seen[wName] = true
                merged.push(wName)
            }

            merged.sort()
            worldFileList = merged.length > 0 ? merged : []

            // Restore previous selection if it still exists in the new list,
            // otherwise default to the first entry.
            if (merged.length > 0) {
                var restoreIdx = -1
                if (_lastSelectedWorld.length > 0) {
                    for (var k = 0; k < merged.length; k++) {
                        if (merged[k] === _lastSelectedWorld) {
                            restoreIdx = k
                            break
                        }
                    }
                }
                worldComboBox.currentIndex = (restoreIdx >= 0) ? restoreIdx : 0
            } else {
                worldComboBox.currentIndex = -1
            }

            // Only turn off the spinner once all queries have responded.
            if (_pendingWorldQueries <= 0)
                worldsLoading = false
        }
    }

    // Safety net: if Docker command hangs (rare), still clear the loading
    // spinner after 12 seconds so the UI doesn't stay stuck.
    Timer {
        id: worldLoadTimeout
        interval: 12000
        repeat: false
        onTriggered: {
            if (worldsLoading) {
                _pendingWorldQueries = 0
                worldsLoading = false
            }
        }
    }

    // QML does not reliably notify on array[index] = v; reassign a copy so TextInput bindings update.
    function setRobotPosXAt(i, x) {
        if (robotPosX[i] === x)
            return
        var a = robotPosX.slice()
        a[i] = x
        robotPosX = a
    }
    function setRobotPosYAt(i, y) {
        if (robotPosY[i] === y)
            return
        var a = robotPosY.slice()
        a[i] = y
        robotPosY = a
    }

    background: Rectangle {
        color: surface
        radius: 20
        border.color: primary
        border.width: 1
        layer.enabled: true
        layer.effect: DropShadow {
            transparentBorder: true
            radius: 24
            samples: 48
            color: "#60000000"
            verticalOffset: 8
        }
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        // ----- HEADER -----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                width: 40
                height: 40
                radius: 12
                color: Qt.rgba(primary.r, primary.g, primary.b, 0.15)
                Text {
                    anchors.centerIn: parent
                    text: "⚙"
                    color: primary
                    font.pixelSize: 24
                }
            }

            ColumnLayout {
                spacing: 2
                Text {
                    text: "SIMULATION CONFIGURATION"
                    color: textPrimary
                    font.pixelSize: 18
                    font.bold: true
                    font.letterSpacing: 1.0
                }
                    Text {
                        text: currentStep === 0 ? "Select world and robots." : "Configure X/Y positions for robots."
                    color: textSecondary
                    font.pixelSize: 12
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "Step " + (currentStep + 1) + "/2"
                color: textSecondary
                font.pixelSize: 12
                font.bold: true
            }

            Rectangle {
                id: rosConnectionBadge
                property bool isConnected: (typeof mapBridge !== 'undefined' && mapBridge) ? mapBridge.isConnected : false
                width: 130
                height: 28
                radius: 14
                color: isConnected ? Qt.rgba(success.r, success.g, success.b, 0.1) : Qt.rgba(danger.r, danger.g, danger.b, 0.1)
                border.color: isConnected ? success : danger
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: rosConnectionBadge.isConnected ? success : danger
                    }
                    Text {
                        text: rosConnectionBadge.isConnected ? "ONLINE" : "OFFLINE"
                        color: rosConnectionBadge.isConnected ? success : danger
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            // Close popup (replaces Cancel on step 1)
            Rectangle {
                Layout.leftMargin: 8
                width: 36
                height: 36
                radius: 10
                color: closeHit.containsMouse ? "#DB1A1A": Qt.rgba(0, 0, 0, 0.15)
                border.color: borderColor
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }

                MouseArea {
                    id: closeHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: simConfigPopup.close()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: borderColor
        }

        // ----- MAIN CONTENT AREA -----
        StackLayout {
            id: stackLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: currentStep

            // Page 0: World & Robot Selection
            Item {
                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: 24

                    // LEFT COLUMN: Environment
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 20

                        ColumnLayout {
                            spacing: 8
                            Layout.fillWidth: true

                            Text {
                                text: "Environment Selection (Webots)"
                                color: textPrimary
                                font.bold: true
                                font.pixelSize: 14
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                color: surfaceLight
                                radius: 8
                                border.color: borderColor
                                border.width: 1

                                ComboBox {
                                    id: worldComboBox
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    model: worldFileList
                                    enabled: !worldsLoading && worldFileList.length > 0

                                    background: Rectangle { color: "transparent" }

                                    contentItem: Text {
                                        leftPadding: 16
                                        rightPadding: 16
                                        text: worldsLoading
                                            ? "Loading from Docker..."
                                            : (worldFileList.length === 0
                                                ? "No worlds found — click Refresh"
                                                : worldComboBox.displayText)
                                        font.pixelSize: 14
                                        color: (worldsLoading || worldFileList.length === 0)
                                            ? textSecondary : textPrimary
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }

                                    delegate: ItemDelegate {
                                        width: worldComboBox.width
                                        contentItem: Text {
                                            text: modelData
                                            color: textPrimary
                                            font.pixelSize: 14
                                        }
                                        background: Rectangle {
                                            color: highlighted ? Qt.rgba(primary.r, primary.g, primary.b, 0.2) : surfaceLight
                                        }
                                    }

                                    indicator: Text {
                                        x: worldComboBox.width - width - 8
                                        y: (worldComboBox.height - height) / 2
                                        text: worldsLoading ? "⟳" : "▼"
                                        color: appRoot ? appRoot.primary : primary
                                        font.pixelSize: 10
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 12

                                Text {
                                    Layout.fillWidth: true
                                    text: "Worlds are loaded from Docker containers named env_<world>. Click Refresh to re-scan."
                                    color: textSecondary
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }

                                Text {
                                    text: "Refresh"
                                    color: theme.cyan
                                    font.pixelSize: 12
                                    font.bold: true
                                    Layout.alignment: Qt.AlignTop

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: refreshSimulationWorlds()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                Layout.topMargin: 8
                                radius: 8
                                color: Qt.rgba(danger.r, danger.g, danger.b, 0.15)
                                border.color: danger
                                border.width: 1
                                visible: !rosConnectionBadge.isConnected

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        text: "⚠"
                                        color: danger
                                        font.pixelSize: 16
                                    }
                                    Text {
                                        text: "Offline: Cannot transmit simulation data."
                                        color: danger
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // RIGHT COLUMN: Robot Selection (using persistent array)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 10

                        Text {
                            text: "Robot Target Selection"
                            color: textPrimary
                            font.bold: true
                            font.pixelSize: 14
                        }
                        Text {
                            text: "Select specific robots."
                            color: textSecondary
                            font.pixelSize: 11
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 270
                            color: surfaceLight
                            radius: 8
                            border.color: borderColor
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                CheckBox {
                                    id: selectAllCheck
                                    text: "Select All"
                                    checked: robotSelected.every(function(v) { return v === true })
                                    onToggled: {
                                        var arr = []
                                        for (var i = 0; i < 6; i++) arr.push(checked)
                                        robotSelected = arr
                                    }

                                    indicator: Rectangle {
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        x: selectAllCheck.leftPadding
                                        y: selectAllCheck.height / 2 - height / 2
                                        radius: 4
                                        border.color: selectAllCheck.checked ? primary : borderColor
                                        color: selectAllCheck.checked ? primary : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✔"
                                            color: "black"
                                            font.pixelSize: 12
                                            visible: selectAllCheck.checked
                                        }
                                    }

                                    contentItem: Text {
                                        text: selectAllCheck.text
                                        color: textPrimary
                                        font.bold: true
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: selectAllCheck.indicator.width + selectAllCheck.spacing
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: borderColor
                                }

                                Repeater {
                                    model: 6
                                    CheckBox {
                                        id: robotCheck
                                        text: "Robot " + (index + 1)
                                        checked: robotSelected[index] === true
                                        onToggled: {
                                            var arr = robotSelected.slice()
                                            arr[index] = checked
                                            robotSelected = arr
                                        }

                                        indicator: Rectangle {
                                            implicitWidth: 20
                                            implicitHeight: 20
                                            x: robotCheck.leftPadding
                                            y: robotCheck.height / 2 - height / 2
                                            radius: 4
                                            border.color: robotCheck.checked ? primary : borderColor
                                            color: robotCheck.checked ? Qt.rgba(primary.r, primary.g, primary.b, 0.2) : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "✔"
                                                color: primary
                                                font.pixelSize: 12
                                                visible: robotCheck.checked
                                            }
                                        }

                                        contentItem: Text {
                                            text: robotCheck.text
                                            color: robotCheck.checked ? textPrimary : textSecondary
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: robotCheck.indicator.width + robotCheck.spacing
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Page 1: Robot Initial Positions (X/Y) per selected robot
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 16

                    Text {
                        text: "Robot Initial Positions"
                        color: textPrimary
                        font.bold: true
                        font.pixelSize: 16
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: "World: <b>" + (worldComboBox.currentText || "—") + "</b>  |  "
                                  + selectedRobotList.length + " robot(s) selected: "
                                  + selectedRobotList.map(function(r){ return "R" + r }).join(", ")
                            color: textSecondary
                            font.pixelSize: 12
                            textFormat: Text.RichText
                            wrapMode: Text.WordWrap
                        }
                    }
                    Text {
                        text: "Enter the initial X / Y spawn position for each selected robot."
                        color: textSecondary
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 220
                        color: surfaceLight
                        radius: 8
                        border.color: borderColor
                        border.width: 1
                        clip: true

                        Flickable {
                            id: posFlick
                            anchors.fill: parent
                            anchors.margins: 6
                            flickableDirection: Flickable.VerticalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            contentHeight: posColumn.height

                            Column {
                                id: posColumn
                                width: posFlick.width
                                spacing: 8

                                // Model = selectedRobotList (e.g. [1,3,5])
                                // modelData = 1-based robot ID; robotIdx = 0-based array index
                                Repeater {
                                    model: selectedRobotList
                                    delegate: Rectangle {
                                        property int robotId:  modelData
                                        property int robotIdx: robotId - 1

                                        width: posColumn.width
                                        height: 60
                                        color: Qt.darker(surfaceLight, 1.08)
                                        radius: 8
                                        border.color: borderColor
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 12

                                            Text {
                                                text: "Robot " + robotId
                                                color: textPrimary
                                                font.bold: true
                                                font.pixelSize: 13
                                                verticalAlignment: Text.AlignVCenter
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: 88
                                                Layout.minimumWidth: 88
                                                Layout.maximumWidth: 88
                                            }

                                            RowLayout {
                                                spacing: 10
                                                Layout.alignment: Qt.AlignVCenter

                                                Text { text: "X"; color: textSecondary; font.pixelSize: 11
                                                       verticalAlignment: Text.AlignVCenter; Layout.alignment: Qt.AlignVCenter }

                                                Rectangle {
                                                    width: 98; height: 32; radius: 8
                                                    color: surface
                                                    border.color: borderColor; border.width: 1

                                                    TextInput {
                                                        anchors.fill: parent
                                                        anchors.margins: 4
                                                        text: String(robotPosX[robotIdx])
                                                        color: textPrimary
                                                        font.pixelSize: 12
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                        selectByMouse: true
                                                        onEditingFinished: {
                                                            var v = parseFloat(text)
                                                            if (!isNaN(v)) setRobotPosXAt(robotIdx, v)
                                                        }
                                                    }
                                                }

                                                Text { text: "Y"; color: textSecondary; font.pixelSize: 11
                                                       verticalAlignment: Text.AlignVCenter; Layout.alignment: Qt.AlignVCenter }

                                                Rectangle {
                                                    width: 98; height: 32; radius: 8
                                                    color: surface
                                                    border.color: borderColor; border.width: 1

                                                    TextInput {
                                                        anchors.fill: parent
                                                        anchors.margins: 4
                                                        text: String(robotPosY[robotIdx])
                                                        color: textPrimary
                                                        font.pixelSize: 12
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                        selectByMouse: true
                                                        onEditingFinished: {
                                                            var v = parseFloat(text)
                                                            if (!isNaN(v)) setRobotPosYAt(robotIdx, v)
                                                        }
                                                    }
                                                }
                                            }

                                            Item { Layout.fillWidth: true }
                                        }
                                    }
                                }

                                // So the last row’s border clears the flickable bottom when scrolled
                                Item {
                                    width: posColumn.width
                                    height: 18
                                }
                            }
                        }
                    }
                }
            }
        }

        // ----- BOTTOM BUTTONS -----
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: borderColor
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // Previous (step 2 only) — Cancel removed; use ✕ in header to close anytime
            Rectangle {
                visible: currentStep === 1
                Layout.preferredWidth: 120
                Layout.preferredHeight: 44
                radius: 12
                readonly property bool prevHovered: prevMouse.containsMouse
                color: visible ? (prevHovered ? Qt.rgba(textPrimary.r, textPrimary.g, textPrimary.b, 0.06) : "transparent") : "transparent"
                border.color: textSecondary
                border.width: visible ? 1 : 0
                scale: prevMouse.containsMouse ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "Previous"
                    color: textPrimary
                    font.pixelSize: 14
                    font.bold: true
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    enabled: currentStep === 1
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: currentStep = 0
                }
            }

            Item { Layout.fillWidth: true }

            // Next / Launch button
            Rectangle {
                Layout.preferredWidth: 240
                Layout.preferredHeight: 44
                radius: 12
                readonly property bool launchHovered: launchMouse.containsMouse
                color: launchHovered ? Qt.lighter(primary, 1.2) : primary
                Behavior on color { ColorAnimation { duration: 120 } }
                scale: launchMouse.containsMouse ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: currentStep === 0 ? "➡️" : "🚀"
                        font.pixelSize: 16
                        color: "black"
                    }
                    Text {
                        text: currentStep === 0 ? "NEXT" : "LAUNCH SIMULATION"
                        color: "black"
                        font.pixelSize: 14
                        font.bold: true
                        font.letterSpacing: 1.0
                    }
                }

                MouseArea {
                    id: launchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (currentStep === 0) {
                            // Guard: must have a world and at least one robot
                            if (selectedRobotList.length === 0) return
                            var preWorld = worldComboBox.currentText ? String(worldComboBox.currentText).trim() : ""
                            if (preWorld.length === 0) return
                            currentStep = 1
                        } else {
                            if (typeof mapBridge === 'undefined') return

                            // Build payload from selectedRobotList (already 1-based IDs)
                            var selectedRobots = selectedRobotList.slice()
                            var robotInitialX  = []
                            var robotInitialY  = []
                            for (var i = 0; i < selectedRobots.length; i++) {
                                var rid = selectedRobots[i] - 1  // 0-based index
                                robotInitialX.push(robotPosX[rid])
                                robotInitialY.push(robotPosY[rid])
                            }

                            var w = worldComboBox.currentText ? String(worldComboBox.currentText).trim() : ""
                            if (w.length === 0) return
                            console.log("Launching simulation: world=" + w
                                + " ugv=" + JSON.stringify(selectedRobots)
                                + " x=" + JSON.stringify(robotInitialX)
                                + " y=" + JSON.stringify(robotInitialY))

                            mapBridge.runWebotsSim({
                                world:            w,
                                simulation_world: w,
                                ugv:              selectedRobots,
                                ugv_initial_x:    robotInitialX,
                                ugv_initial_y:    robotInitialY
                            })

                            simConfigPopup.close()
                        }
                    }
                }
            }
        }
    } }
