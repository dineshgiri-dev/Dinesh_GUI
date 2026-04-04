import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtQuick.Controls.Material 2.15
import Qt5Compat.GraphicalEffects

ApplicationWindow {
    id: root
    Theme { id: theme }
    visible: true
    width: 1280
    height: 720
    minimumWidth: 1024
    minimumHeight: 600
    property bool useCustomWindowButtons: true

    flags: Qt.Window
           | (root.useCustomWindowButtons ? Qt.FramelessWindowHint : Qt.WindowTitleHint)
           | (root.useCustomWindowButtons ? 0 : Qt.WindowSystemMenuHint)
           | (root.useCustomWindowButtons ? 0 : Qt.WindowCloseButtonHint)
           | (root.useCustomWindowButtons ? 0 : Qt.WindowMinimizeButtonHint)
           | (root.isLoggedIn && !root.useCustomWindowButtons ? Qt.WindowMaximizeButtonHint : 0)

    function applyWindowModeForAuthState() {
        if (root.isLoggedIn) {
            // After login: fill entire monitor.
            root.visibility = Window.Maximized
            Qt.callLater(function() { root.showMaximized() })
        } else {
            // Before login: centered normal window.
            root.visibility = Window.Windowed
            root.width = Math.min(Math.max(root.minimumWidth, root.width), root.Screen.width)
            root.height = Math.min(Math.max(root.minimumHeight, root.height), root.Screen.height)
            root.x = Math.round((root.Screen.width - root.width) / 2)
            root.y = Math.round((root.Screen.height - root.height) / 2)
        }
    }

    Component.onCompleted: {
        applyWindowModeForAuthState()
        if (typeof mapBridge !== 'undefined' && mapBridge) {
            root.isSimulationMode = mapBridge.simulationMode
            root.emergencyMode = mapBridge.emergencyActive
        }
    }
    onIsLoggedInChanged: applyWindowModeForAuthState()

    background: Rectangle {
        Image {
            anchors.fill: parent
            source: "/home/dinesh/.cursor/projects/home-dinesh-Downloads-QT-Projects-Versions-Smart-Atonomous-Robot-3d-done-Smart-Atonomous-Robot-latest-Smart-Atonomous-Robot/assets/image-40b8418f-1255-4de2-b61b-176eb63e61a7.png"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.16
        }
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.emergencyMode ? danger : (root.isSimulationMode ? "#29515A" : theme.bg1) }
            GradientStop { position: 1.0; color: theme.bg0 }
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Qt.rgba(theme.cyan.r, theme.cyan.g, theme.cyan.b, 0.18)
            border.width: 1
        }
    }

    // Unified visual system
    property color primary: theme.neon
    property color primaryDark: theme.neonSoft
    property color primaryLight: theme.cyan
    property color danger: theme.danger
    property color success: theme.neon
    property color warning: theme.warning
    property color surface: theme.bg1
    property color surfaceLight: theme.glass0
    property color textPrimary: theme.textPrimary
    property color textSecondary: theme.textSecondary
    property color borderColor: theme.glassStroke
    property int selectedDeviceId: 0
    property bool isLoggedIn: false

    // State Variables
    property string currentScreen: "main"
    property int currentDeviceId: 0
    property bool isSimulationMode: false

    // Confirmation dialog properties
    property string confirmationTitle: ""
    property string confirmationMessage: ""
    property var confirmationCallback: null
    property string confirmationType: "info"

    // Emergency state
    property bool emergencyMode: false

    // ================= MAIN LAYOUT =================
    ColumnLayout {
        visible: root.isLoggedIn
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // Top-right app window controls (separate row above header)
        RowLayout {
            visible: root.useCustomWindowButtons
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 8

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: minBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10)
                border.color: "#A2A5CF"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                MouseArea {
                    id: minBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showMinimized()
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
                color: closeBtnMouse.containsMouse ? Qt.rgba(239/255, 68/255, 68/255, 0.9) : Qt.rgba(239/255, 68/255, 68/255, 0.75)
                border.color: "#ef4444"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                }
                MouseArea {
                    id: closeBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        // ================= HEADER =================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            radius: 16
            border.color: borderColor
            border.width: 1

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.emergencyMode ? danger :(root.isSimulationMode ? "#2E5D67": "#163247") }
                GradientStop { position: 1.0; color: root.emergencyMode ? danger : "#102435" }
            }

            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 12
                samples: 24
                color: "#aa000000"
                verticalOffset: 4
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 16

                // Logo/Title Section
                RowLayout {
                    spacing: 12

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 10
                        color: "#0000FF"/*primary*/

                        Text {
                            anchors.centerIn: parent
                            text: "💠"
                            font.pixelSize: 24
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "SMART AUTONOMOUS ROBOT"
                            color: textPrimary
                            font.pixelSize: 18
                            font.bold: true
                            font.letterSpacing: 1.5
                        }
                        Text {
                            text: root.emergencyMode ? (root.isSimulationMode ? "⚠ SIMULATION E-STOP ENGAGED" : "⚠ EMERGENCY PROTOCOL ENGAGED") : (root.isSimulationMode ? "🎮 LIVE SIMULATION MODE" : "")
                            color: root.emergencyMode ? "white" : (root.isSimulationMode ? "white" : textSecondary)
                            font.pixelSize: 12
                            font.bold: root.emergencyMode || root.isSimulationMode
                            font.letterSpacing: 1.0
                        }
                    }
                }

                // Connection Status
                Rectangle {
                    Layout.preferredWidth: connectionRow.implicitWidth + 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: (typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected) ? Qt.rgba(0, 255, 157, 0.15) : Qt.rgba(255, 0, 102, 0.15)
                    border.color: (typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected) ? success : danger
                    border.width: 1

                    RowLayout {
                        id: connectionRow
                        anchors.centerIn: parent
                        spacing: 8

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: (typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected) ? success : danger

                            SequentialAnimation on opacity {
                                running: (typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected)
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.3; duration: 1000 }
                                NumberAnimation { from: 0.3; to: 1; duration: 1000 }
                            }
                        }

                        Text {
                            text: (typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected) ? "● CONNECTED" : "● OFFLINE"
                            color: (typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected) ? success : danger
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Emergency Stop / Resume Button
                Rectangle {
                    id: emergencyButton
                    Layout.preferredWidth: emergencyRow.implicitWidth + 40
                    Layout.preferredHeight: 40
                    radius: 20
                    color: root.emergencyMode ? /*Qt.rgba(16, 185, 129, 0.15)*/ success :  Qt.rgba(239, 68, 68, 0.15)
                    border.color: root.emergencyMode ? success : danger
                    border.width: 1
                    opacity: (root.currentScreen === "main" && typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected) ? 1.0 : 0.5
                    enabled: (root.currentScreen === "main" && typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected)

                    RowLayout {
                        id: emergencyRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: root.emergencyMode ? "✔" : "⛔"
                            font.pixelSize: 16
                            color: root.emergencyMode ? "white" : emergencyButton.border.color
                        }

                        Text {
                            text: root.emergencyMode ? "RESUME" : "E-Stop"
                            color: /*root.emergencyMode ? success :*/ "white"
                            font.pixelSize: 12
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                    }

                    MouseArea { anchors.fill: parent
                        
                        hoverEnabled: (root.currentScreen === "main" && typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected)
                        cursorShape: Qt.PointingHandCursor
                        // onEntered: parent.color = root.emergencyMode ? Qt.rgba(16, 185, 129, 0.25) : Qt.rgba(239, 68, 68, 0.25)
                        // onExited: parent.color = root.emergencyMode ? Qt.rgba(16, 185, 129, 0.15) : Qt.rgba(239, 68, 68, 0.15)
                        onClicked: {
                            if (root.currentScreen !== "main") return;
                            if (root.emergencyMode) {
                                showConfirmationDialog(
                                    "Resume Operations",
                                    "Are you sure you want to resume normal operations for all robots?",
                                    function() {
                                        root.emergencyMode = false
                                        if (typeof mapBridge !== 'undefined') {
                                            mapBridge.emergencyResume()
                                        }
                                    },
                                )
                            } else {
                                showConfirmationDialog(
                                    "Emergency Stop",
                                    "WARNING: This will stop ALL robots immediately. Are you sure?",
                                    function() {
                                        root.emergencyMode = true
                                        if (typeof mapBridge !== 'undefined') {
                                            mapBridge.emergencyStop()
                                        }
                                    },                                    
                                )
                            }
                        }
                    }
                }

                // Time Display
                Rectangle {
                    Layout.preferredWidth: dateTimeText.implicitWidth + 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: surfaceLight
                    border.color: borderColor
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        id: dateTimeText
                        font.pixelSize: 12
                        font.bold: true
                        color: "white"
                        text: Qt.formatDateTime(new Date(), "dd MMM yyyy • hh:mm:ss")
                    }
                }
            }
        }

        // ================= SCREEN SWITCHER =================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: Qt.rgba(theme.glass0.r, theme.glass0.g, theme.glass0.b, 0.45)
            border.color: borderColor
            border.width: 1
            clip: true

            // ── Persistent main dashboard ─────────────────────────────────────
            // Kept alive at all times — only hidden when a sub-screen is shown.
            // This prevents all 12 cards and their Connections from being
            // destroyed/recreated on every screen switch.
            GridLayout {
                id: mainDashboard
                visible: root.currentScreen === "main"
                anchors.fill: parent
                anchors.margins: 12
                columns: 5
                rows: 4
                rowSpacing: 12
                columnSpacing: 12

                // Row 1
                DeviceStatusBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 1; borderColor: root.borderColor; accentColor: root.primary
                }
                DeviceCameraBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 1; borderColor: root.borderColor; accentColor: root.primary
                }
                DeviceCameraBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 2; borderColor: root.borderColor; accentColor: root.primary
                }
                DeviceCameraBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 3; borderColor: root.borderColor; accentColor: root.primary
                }
                DeviceStatusBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 5; borderColor: root.borderColor; accentColor: root.primary
                }

                // Row 2
                DeviceStatusBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 2; borderColor: root.borderColor; accentColor: root.primary
                }
                CenterPanel {
                    Layout.rowSpan: 2; Layout.columnSpan: 3
                    Layout.fillWidth: true; Layout.fillHeight: true
                    borderColor: root.borderColor; accentColor: root.primary
                }
                DeviceStatusBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 6; borderColor: root.borderColor; accentColor: root.primary
                }

                // Row 3
                DeviceStatusBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 3; borderColor: root.borderColor; accentColor: root.primary
                }

                // Simulation Panel (rows 3-4, col 5)
                Rectangle {
                    Layout.rowSpan: 2; Layout.fillWidth: true; Layout.fillHeight: true
                    radius: 12; color: root.surfaceLight
                    border.color: root.borderColor; border.width: 1

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 16; spacing: 12

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.borderColor }

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 8
                            readonly property bool simBtnHovered: simulationhover.containsMouse
                            color: {
                                var disconnected = (typeof mapBridge === 'undefined' || !mapBridge || !mapBridge.isConnected)
                                var baseOff = Qt.rgba(49/255, 224/255, 255/255, 0.12)
                                if (disconnected) return baseOff
                                if (root.isSimulationMode) {
                                    var b = Qt.rgba(255/255, 77/255, 109/255, 0.22)
                                    return simBtnHovered ? Qt.lighter(danger, 1.15) : b
                                }
                                return simBtnHovered ? Qt.rgba(55/255, 232/255, 255/255, 0.2) : baseOff
                            }
                            border.color: (typeof mapBridge === 'undefined' || !mapBridge || !mapBridge.isConnected)
                                          ? "#6b7280" : (root.isSimulationMode ? danger : "#31E0FF")
                            border.width: 1
                            scale: simulationhover.containsMouse ? 1.05 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150 } }
                            opacity: (typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected) ? 1.0 : 0.5

                            Text {
                                anchors.fill: parent; anchors.margins: 4
                                text: root.isSimulationMode ? "🚪 EXIT SIMULATION MODE" : "🚀 LAUNCH WEBOTS SIMULATION"
                                color: root.isSimulationMode ? "white" : "#31E0FF"
                                font.bold: true; font.pixelSize: 11; font.letterSpacing: 0.5
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                id: simulationhover; anchors.fill: parent
                                enabled: true//typeof mapBridge !== 'undefined' && mapBridge && mapBridge.isConnected
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.isSimulationMode) {
                                        showConfirmationDialog(
                                            "Exit Simulation",
                                            "Are you sure you want to stop the simulation and return to standard mode?",
                                            function() {
                                                if (typeof mapBridge !== 'undefined') mapBridge.exitWebotsSim()
                                            }, "danger")
                                    } else {
                                        simulationConfigPopup.open()
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; Layout.preferredHeight: 72; spacing: 8
                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: 8; color: "transparent"; border.color: "transparent"; border.width: 1
                                Image {
                                    anchors.fill: parent; anchors.margins: 8
                                    source: "qrc:/icons/DRDO.png"
                                    fillMode: Image.PreserveAspectFit; smooth: true
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: 80
                                radius: 8; color: "transparent"; border.color: "transparent"; border.width: 1
                                Image {
                                    anchors.fill: parent; anchors.margins: 8
                                    source: "qrc:/icons/Jeanuvs-logo.png"
                                    fillMode: Image.PreserveAspectFit; smooth: true
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Row 4
                DeviceStatusBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 4; borderColor: root.borderColor; accentColor: root.primary
                }
                DeviceCameraBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 4; borderColor: root.borderColor; accentColor: root.primary
                }
                DeviceCameraBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 5; borderColor: root.borderColor; accentColor: root.primary
                }
                DeviceCameraBlock {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    deviceId: 6; borderColor: root.borderColor; accentColor: root.primary
                }
            } // end mainDashboard

            // ── Sub-screen Loader (only active for non-main screens) ──────────
            // Destroys the sub-screen as soon as the user returns to main,
            // freeing its canvas/timer resources immediately.
            Loader {
                id: screenLoader
                anchors.fill: parent
                anchors.margins: 1
                active: root.currentScreen !== "main"
                sourceComponent: {
                    if (root.currentScreen === "teleop")    return teleOpComponent
                    if (root.currentScreen === "sensor")    return sensorComponent
                    if (root.currentScreen === "nav")       return navComponent
                    if (root.currentScreen === "maximized") return maximizedComponent
                    return null
                }
            }

        }
    }

    // Screen components
    Component {
        id: teleOpComponent
        TeleOpScreen {
            appRoot: root
            selectedDeviceId: root.currentDeviceId
        }
    }

    Component {
        id: sensorComponent
        SensorScreen {
            appRoot: root
            selectedDeviceId: root.currentDeviceId
        }
    }

    Component {
        id: navComponent
        NavPageScreen {
            appRoot: root
            selectedDeviceId: root.currentDeviceId
        }
    }

    Component {
        id: maximizedComponent
        MaximizedViewScreen {
            appRoot: root
            deviceId: root.currentDeviceId
        }
    }

    // ================= SIMULATION CONFIG POPUP =================
    SimulationConfigPopup {
        id: simulationConfigPopup
        appRoot: root
    }

    // ================= MODERN CONFIRMATION DIALOG =================
    Popup {
        id: confirmationDialog
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape

        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 460
        height: 280

        background: Rectangle {
            color: root.surface
            radius: 24
            border.color: {
                if (root.confirmationType === "danger") return root.danger
                if (root.confirmationType === "warning") return root.warning
                return root.primary
            }
            border.width: 2

            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 16
                samples: 32
                color: "#40000000"
                horizontalOffset: 0
                verticalOffset: 4
            }
        }

        contentItem: ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            // Icon and Title Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Rectangle {
                    width: 48
                    height: 48
                    radius: 16
                    color: {
                        if (root.confirmationType === "danger") return Qt.rgba(239/255, 68/255, 68/255, 0.15)
                        if (root.confirmationType === "warning") return Qt.rgba(245/255, 158/255, 11/255, 0.15)
                        return Qt.rgba(45/255, 212/255, 191/255, 0.15)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (root.confirmationType === "danger") return "⚠️"
                            if (root.confirmationType === "warning") return "⚡"
                            return "ℹ️"
                        }
                        font.pixelSize: 24
                    }
                }

                Text {
                    text: root.confirmationTitle
                    font.pixelSize: 20
                    font.bold: true
                    color: root.textPrimary
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            // Message
            Text {
                text: root.confirmationMessage
                font.pixelSize: 14
                color: root.textSecondary
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                wrapMode: Text.WordWrap
                lineHeight: 1.4
            }

            Item { Layout.fillHeight: true }

            // Buttons Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Cancel Button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 12
                    color: "transparent"
                    border.color: root.borderColor
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: root.textSecondary
                        font.pixelSize: 14
                        font.bold: true
                    }

                    MouseArea { anchors.fill: parent
                        
                        hoverEnabled: true
                        onEntered: parent.color = Qt.rgba(255/255, 255/255, 255/255, 0.05)
                        onExited: parent.color = "transparent"
                        onClicked: {
                            confirmationDialog.close()
                            root.confirmationCallback = null
                        }
                    }
                }

                // Confirm Button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 12
                    color: {
                        if (root.confirmationType === "danger") return root.danger
                        if (root.confirmationType === "warning") return root.warning
                        return root.primary
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Confirm"
                        color: "black"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    MouseArea { anchors.fill: parent
                        
                        hoverEnabled: true
                        onEntered: parent.color = Qt.lighter(parent.color, 1.1)
                        onExited: parent.color = root.confirmationType === "danger" ? root.danger :
                                                   (root.confirmationType === "warning" ? root.warning : root.primary)
                        onClicked: {
                            var callback = root.confirmationCallback
                            root.confirmationCallback = null
                            confirmationDialog.close()

                            if (callback) {
                                closeTimer.callback = callback
                                closeTimer.start()
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 150
        repeat: false
        property var callback: null
        onTriggered: {
            if (callback) {
                callback()
                callback = null
            }
        }
    }

    // Function to show confirmation dialog
    function showConfirmationDialog(title, message, callback, type) {
        if (type === undefined) {
            type = "info"
        }
        root.confirmationTitle = title
        root.confirmationMessage = message
        root.confirmationCallback = callback
        root.confirmationType = type
        confirmationDialog.open()
    }

    // Timer for updating date/time
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            dateTimeText.text = Qt.formatDateTime(new Date(), "dd MMM yyyy • hh:mm:ss")
        }
    }

    Connections {
        target: typeof mapBridge !== 'undefined' ? mapBridge : null
        ignoreUnknownSignals: true
        function onSimulationModeChanged() {
            root.isSimulationMode = mapBridge.simulationMode
        }
        function onEmergencyActiveChanged() {
            root.emergencyMode = mapBridge.emergencyActive
        }
    }

    // ================= LOGIN PAGE =================
    LoginPage {
        anchors.fill: parent
        visible: !root.isLoggedIn
        onLoginSuccessful: {
            root.isLoggedIn = true
        }
    }
}
