import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: navRoot
    Theme { id: theme }
    property var appRoot: null
    property int selectedDeviceId: 0

    // Waypoint management
    property bool hasPendingWaypoint: false
    property point selectedWaypoint: Qt.point(NaN, NaN)

    // Core state (backend‑driven)
    property var activeTasks: [false, false, false, false, false, false]
    property var robotCoords: [null, null, null, null, null, null]

    // Popup state
    property var selectedRobots: []
    property bool showAssignPopup: false

    // Zoom
    property real mapScale: 1.0
    readonly property real minScale: 0.5
    readonly property real maxScale: 3.0

    radius: 16
    color: appRoot ? appRoot.surface : theme.bg1
    border.color: appRoot ? appRoot.borderColor : theme.glassStroke

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 20; spacing: 15

        // --- TOP BAR (no active‑tasks badge) ---
        RowLayout {
            Layout.fillWidth: true; spacing: 15
            Rectangle {
                id: backBtn
                width: 40; height: 40; radius: 10
                color: backMouse.containsMouse ? "#1D3A50" : "transparent"
                border.color: backMouse.containsMouse ? appRoot.primary : theme.glassStroke
                scale: backMouse.containsMouse ? 1.1 : 1.0
                Behavior on scale { NumberAnimation { duration: 150 } }
                Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 22; color: backMouse.containsMouse ? appRoot.primary : "white" }
                MouseArea { id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: appRoot.currentScreen = "main" }
            }
            Text { text: "Task Allocation"; font.pixelSize: 20; font.bold: true; color: theme.textPrimary }
            Item { Layout.fillWidth: true }
        }

        // --- MAP AREA WITH ZOOM ---
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; color: "#0E1C2A"; radius: 12; clip: true
            border.color: hasPendingWaypoint ? appRoot.primary : appRoot.borderColor

            // Zoom controls
            Column {
                anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 10
                spacing: 5; z: 10
                Rectangle {
                    width: 30; height: 30; radius: 6; color: "#153145"; border.color: appRoot.primary
                    Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 18 }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mapScale = Math.min(maxScale, mapScale + 0.2)
                    }
                }
                Rectangle {
                    width: 30; height: 30; radius: 6; color: "#153145"; border.color: appRoot.primary
                    Text { anchors.centerIn: parent; text: "−"; color: "white"; font.pixelSize: 18 }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mapScale = Math.max(minScale, mapScale - 0.2)
                    }
                }
            }

            Flickable {
                id: mapFlickable
                anchors.fill: parent
                contentWidth: mapImage.width * mapScale
                contentHeight: mapImage.height * mapScale
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Mouse wheel zoom handler
                WheelHandler {
                    onWheel: (event) => {
                                 var zoomFactor = 1.0 + event.angleDelta.y / 1200.0
                                 var newScale = mapScale * zoomFactor
                                 mapScale = Math.max(minScale, Math.min(maxScale, newScale))
                             }
                }

                Item {
                    id: mapImage
                    width: 1000
                    height: 1000
                    transform: Scale { origin.x: 0; origin.y: 0; xScale: mapScale; yScale: mapScale }

                    // Pending waypoint marker
                    Rectangle {
                        width: 14; height: 14; radius: 7; color: appRoot.primary; border.color: "white"
                        visible: !isNaN(selectedWaypoint.x)
                        x: selectedWaypoint.x - 7
                        y: selectedWaypoint.y - 7
                    }

                    // Markers for active robot tasks
                    Repeater {
                        model: 6
                        Rectangle {
                            visible: activeTasks[index]
                            x: robotCoords[index] ? robotCoords[index].x - 6 : 0
                            y: robotCoords[index] ? robotCoords[index].y - 6 : 0
                            width: 12; height: 12; radius: 6; color: appRoot.danger
                            border.color: "white"
                            Text {
                                text: (index+1)
                                anchors.bottom: parent.top
                                color: "white"; font.pixelSize: 9; font.bold: true
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: hasPendingWaypoint ? Qt.CrossCursor : Qt.ArrowCursor
                    onClicked: (mouse) => {
                                   if (hasPendingWaypoint) {
                                       // Convert click to map‑image coordinates accounting for zoom and pan
                                       var mapX = (mouse.x + mapFlickable.contentX) / mapScale
                                       var mapY = (mouse.y + mapFlickable.contentY) / mapScale
                                       selectedWaypoint = Qt.point(mapX, mapY)
                                   }
                               }
                }

                // Pinch zoom
                PinchArea {
                    anchors.fill: parent
                    enabled: true
                    onPinchUpdated: (pinch) => {
                                        var newScale = mapScale * pinch.scale
                                        mapScale = Math.max(minScale, Math.min(maxScale, newScale))
                                    }
                }
            }

            // --- ASSIGNMENT POPUP (single‑robot selection) ---
            // --- ASSIGNMENT POPUP (single‑robot selection) ---
            Rectangle {
                id: assignPopupRect
                visible: showAssignPopup
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 15
                width: 240; height: 350; color: "#0E0C25"; radius: 12; border.color: appRoot.primary; border.width: 1
                z: 10

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "SELECT A ROBOT"; color: appRoot.primary; font.bold: true; font.pixelSize: 12 }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "✕"; color: "white"; font.pixelSize: 18
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    showAssignPopup = false;
                                    assignPopupRect.visible = false;
                                    selectedRobots = [];
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        ListView {
                            anchors.fill: parent
                            model: 6
                            spacing: 5
                            delegate: Rectangle {
                                width: parent.width; height: 38; radius: 6
                                color: activeTasks[index] ? "#2a1515" : "#153145"
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 8
                                    RadioButton {
                                        enabled: !activeTasks[index]
                                        checked: selectedRobots.includes(index)
                                        onCheckedChanged: {
                                            if (checked) selectedRobots = [index]
                                            else selectedRobots = []
                                        }
                                    }
                                    Text { text: "Robot 0" + (index+1); color: "white"; Layout.fillWidth: true; font.pixelSize: 11 }
                                    Rectangle { width: 8; height: 8; radius: 4; color: activeTasks[index] ? appRoot.danger : appRoot.success }
                                }
                            }
                        }
                    }

                    Button {
                        Layout.fillWidth: true; Layout.preferredHeight: 40
                        enabled: selectedRobots.length > 0
                        scale: hovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150 } }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        contentItem: Text {
                            text: "DEPLOY TASK"
                            color: parent.enabled ? "#31E0FF" : "#5C7A8F"
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            color: parent.enabled
                                   ? (parent.hovered ? Qt.rgba(49/255, 224/255, 255/255, 0.24) : Qt.rgba(49/255, 224/255, 255/255, 0.12))
                                   : Qt.rgba(92/255, 122/255, 143/255, 0.16)
                            radius: 8
                            border.color: parent.enabled ? "#31E0FF" : "#5C7A8F"
                            border.width: 1
                        }

                        onClicked: {
                            console.log("Deploy clicked, selectedRobots:", selectedRobots);
                            if (selectedRobots.length === 0) return;

                            var rId = selectedRobots[0];
                            console.log("Assigning to robot", rId+1, "at", selectedWaypoint);

                            // Update local state (copy arrays to trigger change)
                            var newTasks = activeTasks.slice();
                            newTasks[rId] = true;
                            activeTasks = newTasks;

                            var newCoords = robotCoords.slice();
                            newCoords[rId] = selectedWaypoint;
                            robotCoords = newCoords;

                            // Send to backend
                            if (typeof mapBridge !== 'undefined') {
                                mapBridge.sendTask(rId + 1, { "x": selectedWaypoint.x, "y": selectedWaypoint.y });
                            }

                            // Clear pending waypoint
                            selectedWaypoint = Qt.point(NaN, NaN);
                            hasPendingWaypoint = false;
                            selectedRobots = [];

                            // Close popup (both property and direct visibility)
                            console.log("Setting showAssignPopup = false");
                            showAssignPopup = false;
                            assignPopupRect.visible = false;
                        }
                    }
                }
            }
        }

        // --- BOTTOM BAR ---
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 90; radius: 12
            color: appRoot.surfaceLight; border.color: appRoot.borderColor

            RowLayout {
                anchors.fill: parent; anchors.margins: 15; spacing: 20

                // 1. ADD / CANCEL button
                NavToolButton {
                    visible: !activeTasks[selectedDeviceId]
                    text: hasPendingWaypoint ? "CANCEL" : "✚ ADD TASK"
                    btnColor: hasPendingWaypoint ? appRoot.danger : "transparent"
                    borderColor: hasPendingWaypoint ? appRoot.danger : appRoot.primary
                    onClicked: {
                        if (hasPendingWaypoint) {
                            // Cancel: clear point
                            selectedWaypoint = Qt.point(NaN, NaN)
                            hasPendingWaypoint = false
                        } else {
                            // Enter pending mode
                            hasPendingWaypoint = true
                            showAssignPopup = false
                        }
                    }
                }

                // 2. ACTIVE TASK INFO & MODIFY/DELETE
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 65; color: "#0E0C25"; radius: 8; border.color: "#A2A5CF"

                    RowLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 10

                        // Improved ComboBox
                        Rectangle {
                            Layout.preferredWidth: 110; Layout.preferredHeight: 32
                            color: "#153145"; radius: 6; border.color: appRoot.borderColor; border.width: 1
                            ComboBox {
                                id: robotSelector
                                anchors.fill: parent; anchors.margins: 2
                                model: ["Robot 1", "Robot 2", "Robot 3", "Robot 4", "Robot 5", "Robot 6"]
                                currentIndex: selectedDeviceId
                                onCurrentIndexChanged: selectedDeviceId = currentIndex

                                background: Rectangle { color: "transparent" }
                                contentItem: Text {
                                    leftPadding: 8
                                    text: robotSelector.currentText
                                    color: "white"; font.pixelSize: 12
                                    verticalAlignment: Text.AlignVCenter
                                }
                                indicator: Text {
                                    x: robotSelector.width - width - 8
                                    y: (robotSelector.height - height) / 2
                                    text: "▼"; color: appRoot.primary; font.pixelSize: 10
                                }
                                delegate: ItemDelegate {
                                    width: robotSelector.width
                                    contentItem: Text {
                                        text: modelData
                                        color: robotSelector.highlightedIndex === index ? "white" : "#ccc"
                                        font.pixelSize: 12; leftPadding: 8
                                    }
                                    background: Rectangle {
                                        color: robotSelector.highlightedIndex === index ? appRoot.primary : "#153145"
                                    }
                                }
                                popup: Popup {
                                    y: robotSelector.height
                                    width: robotSelector.width; height: 180; padding: 1
                                    background: Rectangle { color: "#0E0C25"; border.color: appRoot.borderColor }
                                    contentItem: ListView {
                                        clip: true
                                        model: robotSelector.delegateModel
                                        currentIndex: robotSelector.highlightedIndex
                                    }
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            Text { text: "STATUS FOR ROBOT 0" + (selectedDeviceId+1); font.pixelSize: 9; color: appRoot.textSecondary; font.bold: true }
                            Text {
                                text: activeTasks[selectedDeviceId] ?
                                          "TARGET X:" + robotCoords[selectedDeviceId].x.toFixed(0) + " Y:" + robotCoords[selectedDeviceId].y.toFixed(0) :
                                          "IDLE - NO ACTIVE TASK"
                                color: activeTasks[selectedDeviceId] ? "white" : appRoot.textSecondary
                                font.pixelSize: 13; font.bold: true
                            }
                        }

                        // MODIFY & DELETE (only if task exists)
                        RowLayout {
                            visible: activeTasks[selectedDeviceId]
                            spacing: 8

                            NavToolButton {
                                text: "✎ MODIFY"; implicitWidth: 80; implicitHeight: 35
                                onClicked: appRoot.showConfirmationDialog("Modify", "Relocate this task?",
                                                                          function() {
                                                                              hasPendingWaypoint = true   // allow new point to be picked
                                                                          }, "warning")
                            }

                            NavToolButton {
                                text: "🗑 DELETE"; implicitWidth: 80; implicitHeight: 35
                                textColor: appRoot.danger; borderColor: appRoot.danger
                                onClicked: appRoot.showConfirmationDialog("Delete", "Cancel this task?",
                                                                          function() {
                                                                              let temp = activeTasks
                                                                              temp[selectedDeviceId] = false
                                                                              activeTasks = temp
                                                                              let tempCoords = robotCoords
                                                                              tempCoords[selectedDeviceId] = null
                                                                              robotCoords = tempCoords
                                                                          }, "danger")
                            }
                        }
                    }
                }

                // 3. ASSIGN TO ROBOTS BUTTON
                Button {
                    id: mainSendBtn
                    enabled: !isNaN(selectedWaypoint.x) && hasPendingWaypoint
                    scale: hovered && enabled ? 1.05 : 1.0
                    Behavior on scale { NumberAnimation { duration: 150 } }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    Layout.preferredHeight: 50; Layout.preferredWidth: 180
                    contentItem: Text {
                        text: "ASSIGN TO ROBOTS"
                        font.bold: true
                        color: mainSendBtn.enabled ? "#31E0FF" : "#5C7A8F"
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: mainSendBtn.enabled
                               ? (mainSendBtn.hovered ? Qt.rgba(49/255, 224/255, 255/255, 0.24) : Qt.rgba(49/255, 224/255, 255/255, 0.12))
                               : Qt.rgba(26/255, 42/255, 58/255, 0.5)
                        radius: 8
                        border.color: mainSendBtn.enabled ? "#31E0FF" : "#5C7A8F"
                        border.width: 1
                    }
                    onClicked: showAssignPopup = true
                }
            }
        }
    }

    // Custom button component
    component NavToolButton : Button {
        property color btnColor: "transparent"
        property color borderColor: "#A2A5CF"
        property color textColor: "white"
        scale: hovered ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 150 } }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        id: control
        implicitHeight: 45; implicitWidth: 130
        contentItem: Text {
            text: control.text
            color: control.enabled ? control.textColor : "#666"
            font.bold: true; font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: control.hovered ? Qt.rgba(49/255, 224/255, 255/255, 0.24)
                                   : (control.btnColor !== "transparent" ? control.btnColor : Qt.rgba(49/255, 224/255, 255/255, 0.10))
            radius: 8
            border.color: control.hovered ? "#31E0FF" : control.borderColor
            border.width: 1
        }
    }
}
