#ifndef MAPBRIDGE_H
#define MAPBRIDGE_H

#include <QObject>
#include <QWebSocket>
#include <QVariantMap>
#include <QVariantList>
#include <QUrl>
#include <QAbstractSocket>
#include <QJsonObject>
#include <QTimer>

class MapBridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY isConnectedChanged)
    Q_PROPERTY(qreal confidence READ confidence NOTIFY confidenceChanged)
    Q_PROPERTY(bool emergencyActive READ emergencyActive NOTIFY emergencyActiveChanged)
    Q_PROPERTY(bool simulationMode READ simulationMode WRITE setSimulationMode NOTIFY simulationModeChanged)

public:
    explicit MapBridge(QObject *parent = nullptr);
    ~MapBridge();

    bool isConnected() const { return m_connected; }
    qreal confidence() const { return m_confidence; }
    bool emergencyActive() const { return m_emergencyActive; }
    bool simulationMode() const { return m_simulationMode; }

    void setSimulationMode(bool mode) {
        if (m_simulationMode != mode) {
            m_simulationMode = mode;
            emit simulationModeChanged();
        }
    }

    // Receive URL (e.g. ws://host:65000). GUI commands (stop/resume/teleop/etc.) are sent on port 65001.
    Q_INVOKABLE void connectToServer(const QString &url = "ws://127.0.0.1:65000");
    Q_INVOKABLE void disconnectFromServer();
    Q_INVOKABLE void stopRobot(int deviceId);
    Q_INVOKABLE void resumeRobot(int deviceId);

    // Actions called from QML
    Q_INVOKABLE void runWebotsSim(const QVariantMap &config);
    /// Ask backend for .wbt list; replies with JSON command list_simulation_worlds_result + worlds[]
    Q_INVOKABLE void requestSimulationWorlds();
    /// List *.wbt on this machine (directory or WEBOTS_WORLDS_DIR; default ~/Documents/Webots/worlds)
    Q_INVOKABLE void queryLocalWebotsWorlds(const QString &directory = QString());
    Q_INVOKABLE void queryDockerWebotsWorlds();   // lists webots_<world> Docker containers
    Q_INVOKABLE void exitWebotsSim();
    Q_INVOKABLE void setForgingPattern(const QString &pattern);
    Q_INVOKABLE void setFlockingMode(const QString &mode);
    Q_INVOKABLE void triggerTaskAllocation();
    Q_INVOKABLE void requestTeleOp(int deviceId);
    Q_INVOKABLE void redirectToSensorControl(int deviceId);
    Q_INVOKABLE void emergencyStop();
    Q_INVOKABLE void emergencyResume();

    // TeleOp control
    Q_INVOKABLE void teleOpMove(int deviceId, double linearVel, double angularVel);
    Q_INVOKABLE void requestMapData(int deviceId = 0);
    Q_INVOKABLE void sendTask(int deviceId, const QVariantMap &target);
    Q_INVOKABLE void assignTaskToRobot(int robotId, double x, double y, const QString &taskName);

    // Sensor and Navigation updates
    Q_INVOKABLE void updateSensorValue(int deviceId, const QString &sensorName, double value);
    Q_INVOKABLE void updateNavParameters(int deviceId, const QVariantMap &navParams);
    Q_INVOKABLE void setCameraView(int deviceId, const QString &cameraType);

    // Dynamic JSON payload methods
    Q_INVOKABLE void sendSensorState(int deviceId, const QVariantMap &sensorStates);
    Q_INVOKABLE void sendForagingPattern(const QVariantList &patternPoints);

    // Request the current sensor state snapshot for a device on page open
    Q_INVOKABLE void requestSensorState(int deviceId);

    // Per-robot status (from robotStatusUpdated); used so only robots that reported show online/green in swarm
    Q_INVOKABLE bool getRobotStatusActive(int robotId) const;
    Q_INVOKABLE int getRobotBattery(int robotId) const;

signals:
    void isConnectedChanged();
    void confidenceChanged();
    void emergencyActiveChanged();
    void simulationModeChanged();

    // --- CRITICAL FIX: Add this signal to link C++ to QML Battery/Status ---
    void robotStatusUpdated(int id, bool active, int battery);

    void mapDataReceived(const QVariantMap &data);
    // Dedicated 2D laser-scan signal: emitted for every /ugv_XX/scan message
    void laserScanReceived(int deviceId, const QVariantList &points);
    // Emitted when a new robot ID is first seen so QML can populate the ComboBox
    void robotDiscovered(int deviceId);
    void imageReceived(const QString &topic, const QString &base64);
    void webotsSimRequested();
    /// Emitted when backend or local folder scan provides world filenames (QString entries)
    void simulationWorldsReceived(const QVariantList &worlds);
    void forgingPatternChanged(const QString &pattern);
    void flockingModeChanged(const QString &mode);
    void taskAllocationTriggered();
    void teleOpRequested(int deviceId);
    void sensorRedirectRequested(int deviceId);
    void sensorUpdated(int deviceId, const QString &sensorName, double value);
    void navParametersUpdated(int deviceId, const QVariantMap &navParams);
    void cameraViewChanged(int deviceId, const QString &cameraType);
    void emergencyStopTriggered();
    void emergencyResumed();
    // Emitted when backend publishes on tasks_ack topic
    void taskAckReceived(int robotId, const QString &taskName, bool success, const QString &message);
    // Emitted when backend acknowledges a sensor-state update command
    void sensorStateAckReceived(int deviceId, bool success, const QString &message);

private slots:
    void onSocketConnected();
    void onSocketDisconnected();
    void onTextMessageReceived(const QString &message);
    void onBinaryMessageReceived(const QByteArray &data);
    void onError(QAbstractSocket::SocketError error);

private:
    void parseRosMessage(const QByteArray &json);
    /// Mark robots online from /ugv_XX/, frame_id, etc. (used for every JSON root and again on publish)
    void applyTopicBasedRobotPresence(const QString &text);
    void emitMapData(const QVariantList &points, const QVariantList &path);
    void sendCommandToRos(const QJsonObject &payload);
    QUrl commandUrlFromReceiveUrl(const QString &receiveUrl) const;
    void parsePointCloud2(const QString &topic, const QJsonObject &msg);
    void launchWebotsDockerContainers(const QJsonObject &fullLaunchJson);
    void destroySimulationDockerContainers();

    QWebSocket *m_socket = nullptr;       // receive (e.g. port 65000)
    QWebSocket *m_commandSocket = nullptr; // send GUI commands (port 65001)
    QMap<QString, QStringList> m_fragments; // Added back for JSON compilation
    QMap<QString, int> m_fragmentsTotal;
    bool m_connected = false;
    qreal m_confidence = 1.0;
    bool m_emergencyActive = false;
    bool m_simulationMode = false;
    // Device tracking: only set by explicit battery/status JSON, never by topic presence
    QMap<int, QVariantMap> m_deviceStatus;
    // Set of robot IDs that have published at least one /scan message
    QSet<int> m_knownScanRobots;
    // Auto-reconnect
    QString m_lastUrl;
    QTimer *m_reconnectTimer = nullptr;
    QStringList m_lastSimulationContainers;
};

#endif // MAPBRIDGE_H
