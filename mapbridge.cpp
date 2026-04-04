#include "mapbridge.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QTimer>
#include <QUrl>
#include <QAbstractSocket>
#include <cmath>
#include <QRegularExpression>
#include <QProcess>
#include <QProcessEnvironment>
#include <QtGlobal>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryFile>
#include <QStandardPaths>
#include <QImage>
#include <QBuffer>
#include <QSet>

static const int GUI_COMMAND_PORT = 65000;

static int envIntValue(const char *key, int defaultValue)
{
    bool ok = false;
    const QString s = QString::fromUtf8(qgetenv(key));
    const int v = s.toInt(&ok);
    return ok ? v : defaultValue;
}

static QString envStrValue(const char *key)
{
    return QString::fromUtf8(qgetenv(key));
}

MapBridge::MapBridge(QObject *parent) : QObject(parent) {
    m_connected = false;

    // Allow overriding ws endpoints without code changes.
    // Examples:
    //   export MAPBRIDGE_WS_URL="ws://127.0.0.1:65000"
    //   export MAPBRIDGE_CMD_PORT="65000"
    const QString envWsUrl = envStrValue("MAPBRIDGE_WS_URL");
    const QString initialReceiveUrl = envWsUrl.isEmpty()
        ? QStringLiteral("ws://127.0.0.1:65000")
        : envWsUrl;

    // Auto-reconnect timer: fires every 3 s while disconnected
    m_reconnectTimer = new QTimer(this);
    m_reconnectTimer->setInterval(3000);
    m_reconnectTimer->setSingleShot(false);
    connect(m_reconnectTimer, &QTimer::timeout, this, [this]() {
        if (!m_connected) {
            qDebug() << "🔄 Auto-reconnect: retrying" << m_lastUrl;
            // Tear down stale sockets before re-opening
            if (m_commandSocket) { m_commandSocket->abort(); m_commandSocket->deleteLater(); m_commandSocket = nullptr; }
            if (m_socket)        { m_socket->abort();        m_socket->deleteLater();        m_socket = nullptr; }
            connectToServer(m_lastUrl);
        }
    });

    // First attempt after 100 ms
    QTimer::singleShot(100, this, [this, initialReceiveUrl]() {
        connectToServer(initialReceiveUrl);
    });
}


MapBridge::~MapBridge() {
    disconnectFromServer();
}

QUrl MapBridge::commandUrlFromReceiveUrl(const QString &receiveUrl) const {
    QUrl u(receiveUrl);
    const int cmdPort = envIntValue("MAPBRIDGE_CMD_PORT", GUI_COMMAND_PORT);
    u.setPort(cmdPort);
    return u;
}

void MapBridge::connectToServer(const QString &url) {
    if (m_socket) {
        qDebug() << "Already have websocket client";
        return;
    }

    // Remember the URL so the reconnect timer can retry it
    m_lastUrl = url;

    m_socket = new QWebSocket();
    connect(m_socket, &QWebSocket::connected, this, &MapBridge::onSocketConnected);
    connect(m_socket, &QWebSocket::disconnected, this, &MapBridge::onSocketDisconnected);
    connect(m_socket, &QWebSocket::textMessageReceived, this, &MapBridge::onTextMessageReceived);
    connect(m_socket, &QWebSocket::binaryMessageReceived, this, &MapBridge::onBinaryMessageReceived);
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    connect(m_socket, &QWebSocket::errorOccurred, this, &MapBridge::onError);
#else
    connect(m_socket, QOverload<QAbstractSocket::SocketError>::of(&QWebSocket::error), this, &MapBridge::onError);
#endif

    qDebug() << "Connecting to websocket server at" << url << "(receive)";
    m_socket->open(QUrl(url));

    QUrl cmdUrl = commandUrlFromReceiveUrl(url);
    m_commandSocket = new QWebSocket();
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    connect(m_commandSocket, &QWebSocket::errorOccurred, this, &MapBridge::onError);
#else
    connect(m_commandSocket, QOverload<QAbstractSocket::SocketError>::of(&QWebSocket::error), this, &MapBridge::onError);
#endif
    const int cmdPort = envIntValue("MAPBRIDGE_CMD_PORT", GUI_COMMAND_PORT);
    qDebug() << "Connecting command socket at" << cmdUrl.toString() << "(send, port" << cmdPort << ")";
    m_commandSocket->open(cmdUrl);

    // Start the reconnect heartbeat (no-op while connected)
    if (!m_reconnectTimer->isActive())
        m_reconnectTimer->start();
}

void MapBridge::disconnectFromServer() {
    if (m_commandSocket) {
        m_commandSocket->close();
        m_commandSocket->deleteLater();
        m_commandSocket = nullptr;
    }
    if (m_socket) {
        m_socket->close();
        m_socket->deleteLater();
        m_socket = nullptr;
    }
    if (m_connected) {
        m_connected = false;
        emit isConnectedChanged();
    }
}



void MapBridge::onSocketDisconnected() {
    m_connected = false;
    m_deviceStatus.clear();
    emit isConnectedChanged();
    qDebug() << "Websocket disconnected — will retry in 3 s";
    // Destroy stale sockets so connectToServer can re-create them
    if (m_commandSocket) { m_commandSocket->deleteLater(); m_commandSocket = nullptr; }
    if (m_socket)        { m_socket->deleteLater();        m_socket = nullptr; }
    if (!m_reconnectTimer->isActive())
        m_reconnectTimer->start();
}

void MapBridge::onSocketConnected() {
    m_connected = true;
    emit isConnectedChanged();
    // Stop retrying once connected
    m_reconnectTimer->stop();
    qDebug() << "Websocket client connected";
}

void MapBridge::onTextMessageReceived(const QString &message) {
    // Accept only JSON payloads coming as text frames.
    const QString trimmed = message.trimmed();
    if (trimmed.isEmpty()) {
        qDebug() << "⚠ Ignored empty websocket text frame";
        return;
    }
    parseRosMessage(trimmed.toUtf8());
}

void MapBridge::onBinaryMessageReceived(const QByteArray &data) {
    // Accept binary frames only when they still contain UTF-8 JSON bytes.
    if (data.isEmpty()) {
        qDebug() << "⚠ Ignored empty websocket binary frame";
        return;
    }
    parseRosMessage(data);
}

// FIX: Missing Action implementations
void MapBridge::runWebotsSim(const QVariantMap &config) { 
    QJsonObject obj = QJsonObject::fromVariantMap(config);
    obj[QStringLiteral("command")] = QStringLiteral("run_webots_sim");

    // Canonical world file name for Docker containers
    const QString world = obj.value(QStringLiteral("world")).toString(
        obj.value(QStringLiteral("simulation_world")).toString());
    if (world.trimmed().isEmpty()) {
        qWarning() << "runWebotsSim: empty world in config, refusing launch";
        return;
    }
    if (!world.isEmpty()) {
        obj[QStringLiteral("world")] = world;
        obj[QStringLiteral("simulation_world")] = world;
    }

    const QJsonArray ugvArr = obj.value(QStringLiteral("ugv")).toArray();
    const QJsonArray robotsArr = obj.value(QStringLiteral("robots")).toArray();
    const QJsonArray ugvInitialX = obj.value(QStringLiteral("ugv_initial_x")).toArray();
    const QJsonArray ugvInitialY = obj.value(QStringLiteral("ugv_initial_y")).toArray();
    const QJsonArray robotInitialX = obj.value(QStringLiteral("robot_initial_x")).toArray();
    const QJsonArray robotInitialY = obj.value(QStringLiteral("robot_initial_y")).toArray();

    // JSON payload that can be consumed by the backend/bridge side
    QJsonObject webotsLaunch;
    webotsLaunch[QStringLiteral("simulation_world")] = obj.value(QStringLiteral("simulation_world")).toString();
    // Preferred schema: ugv / ugv_initial_x / ugv_initial_y
    if (!ugvArr.isEmpty())
        webotsLaunch[QStringLiteral("ugv")] = ugvArr;
    else if (!robotsArr.isEmpty())
        webotsLaunch[QStringLiteral("ugv")] = robotsArr;
    if (!ugvInitialX.isEmpty())
        webotsLaunch[QStringLiteral("ugv_initial_x")] = ugvInitialX;
    else if (!robotInitialX.isEmpty())
        webotsLaunch[QStringLiteral("ugv_initial_x")] = robotInitialX;
    if (!ugvInitialY.isEmpty())
        webotsLaunch[QStringLiteral("ugv_initial_y")] = ugvInitialY;
    else if (!robotInitialY.isEmpty())
        webotsLaunch[QStringLiteral("ugv_initial_y")] = robotInitialY;

    // Mirror onto top-level object for backends that parse root fields (not webots_launch).
    if (webotsLaunch.contains(QStringLiteral("ugv")))
        obj[QStringLiteral("robots")] = webotsLaunch.value(QStringLiteral("ugv"));
    if (webotsLaunch.contains(QStringLiteral("ugv_initial_x")))
        obj[QStringLiteral("robot_initial_x")] = webotsLaunch.value(QStringLiteral("ugv_initial_x"));
    if (webotsLaunch.contains(QStringLiteral("ugv_initial_y")))
        obj[QStringLiteral("robot_initial_y")] = webotsLaunch.value(QStringLiteral("ugv_initial_y"));

    // Backward-compatible mirror fields for existing consumers.
    if (webotsLaunch.contains(QStringLiteral("ugv")))
        webotsLaunch[QStringLiteral("robots")] = webotsLaunch.value(QStringLiteral("ugv"));
    if (webotsLaunch.contains(QStringLiteral("ugv_initial_x")))
        webotsLaunch[QStringLiteral("robot_initial_x")] = webotsLaunch.value(QStringLiteral("ugv_initial_x"));
    if (webotsLaunch.contains(QStringLiteral("ugv_initial_y")))
        webotsLaunch[QStringLiteral("robot_initial_y")] = webotsLaunch.value(QStringLiteral("ugv_initial_y"));
    webotsLaunch[QStringLiteral("schema")] = QStringLiteral("docker_webots_sim_launch_v1");
    obj[QStringLiteral("webots_launch")] = webotsLaunch;

    sendCommandToRos(obj);
    launchWebotsDockerContainers(obj);
    setSimulationMode(true);
    emit webotsSimRequested();
}

void MapBridge::launchWebotsDockerContainers(const QJsonObject &fullLaunchJson)
{
    // World container name is the selected world name directly (e.g. env_hospital).
    const QString worldName = fullLaunchJson.value(QStringLiteral("simulation_world")).toString(
        fullLaunchJson.value(QStringLiteral("world")).toString());
    if (worldName.trimmed().isEmpty()) {
        qWarning() << "launchWebotsDockerContainers: no world specified";
        return;
    }

    // Try docker start first (container already exists but is stopped).
    // If that fails (container was removed), create it fresh with docker run.
    auto dockerStartOrCreate = [](const QString &containerName) -> bool {
        // Attempt 1: start an existing (stopped) container
        {
            QProcess p;
            p.start(QStringLiteral("docker"), QStringList{QStringLiteral("start"), containerName});
            if (p.waitForFinished(30000) && p.exitCode() == 0) {
                qDebug() << "✅ docker start OK:" << containerName;
                return true;
            }
            qDebug() << "docker start failed for" << containerName << "— will try docker run";
        }

        // Attempt 2: create and start a new container (image name == container name)
        {
            QProcess p;
            p.start(QStringLiteral("docker"),
                    QStringList{
                        QStringLiteral("run"),
                        QStringLiteral("--name"), containerName,
                        QStringLiteral("-d"),
                        containerName   // image name matches container name
                    });
            if (!p.waitForFinished(60000)) {
                qWarning() << "docker run timeout:" << containerName;
                return false;
            }
            if (p.exitCode() == 0) {
                qDebug() << "✅ docker run (create) OK:" << containerName;
                return true;
            }
            qWarning() << "docker run FAILED:" << containerName
                       << QString::fromUtf8(p.readAllStandardError().trimmed());
            return false;
        }
    };

    m_lastSimulationContainers.clear();

    // 1. Start (or create) the selected world container (e.g. env_hospital)
    if (dockerStartOrCreate(worldName)) {
        m_lastSimulationContainers.append(worldName);
    } else {
        qWarning() << "launchWebotsDockerContainers: world container not started:" << worldName;
        return;
    }

    // 2. Start (or create) selected UGV containers (webots_ugv_01 .. webots_ugv_0N)
    const QJsonArray ugvArr = fullLaunchJson.contains(QStringLiteral("ugv"))
        ? fullLaunchJson.value(QStringLiteral("ugv")).toArray()
        : fullLaunchJson.value(QStringLiteral("robots")).toArray();

    for (const QJsonValue &rv : ugvArr) {
        const int rid = rv.toInt();
        if (rid <= 0) continue;
        const QString containerName =
            QStringLiteral("webots_ugv_") + QStringLiteral("%1").arg(rid, 2, 10, QLatin1Char('0'));
        if (dockerStartOrCreate(containerName))
            m_lastSimulationContainers.append(containerName);
        else
            qWarning() << "launchWebotsDockerContainers: UGV container not started:" << containerName;
    }
}

void MapBridge::requestSimulationWorlds() {
    QJsonObject obj;
    obj[QStringLiteral("command")] = QStringLiteral("list_simulation_worlds");
    sendCommandToRos(obj);
}

void MapBridge::queryLocalWebotsWorlds(const QString &directory)
{
    QString dirPath = directory;
    if (dirPath.isEmpty())
        dirPath = qEnvironmentVariable("WEBOTS_WORLDS_DIR");
    if (dirPath.isEmpty()) {
        dirPath = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation)
                + QStringLiteral("/Webots/worlds");
    }

    QDir d(dirPath);
    if (!d.exists()) {
        qDebug() << "queryLocalWebotsWorlds: folder not found:" << dirPath << "- set WEBOTS_WORLDS_DIR or create it";
        emit simulationWorldsReceived(QVariantList{});
        return;
    }

    QVariantList worlds;
    const QFileInfoList entries = d.entryInfoList(QStringList() << QStringLiteral("*.wbt"),
                                                  QDir::Files | QDir::Readable,
                                                  QDir::Name);
    for (const QFileInfo &info : entries)
        worlds.append(info.fileName());

    if (!worlds.isEmpty())
        qDebug() << "queryLocalWebotsWorlds: found" << worlds.size() << "worlds in" << dirPath;
    else
        qDebug() << "queryLocalWebotsWorlds: no *.wbt worlds found in" << dirPath;
    emit simulationWorldsReceived(worlds);
}

void MapBridge::queryDockerWebotsWorlds()
{
    // Run: docker ps -a --format "{{.Names}}" and parse world-like names.
    // Accept container names:
    //   webots_<world>, webots-<world>, or raw env_<world>.
    QProcess proc;
    proc.start(QStringLiteral("docker"),
               QStringList{
                   QStringLiteral("ps"),
                   QStringLiteral("-a"),
                   QStringLiteral("--format"), QStringLiteral("{{.Names}}")
               });

    if (!proc.waitForFinished(10000)) {
        qWarning() << "queryDockerWebotsWorlds: docker command timed out";
        return;
    }

    if (proc.exitCode() != 0) {
        qWarning() << "queryDockerWebotsWorlds: docker error:"
                   << proc.readAllStandardError().trimmed();
        return;
    }

    const QString output = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    if (output.isEmpty()) {
        qDebug() << "queryDockerWebotsWorlds: no containers found";
        emit simulationWorldsReceived(QVariantList{});
        return;
    }

    QVariantList worlds;
    QSet<QString> seen;
    const QStringList lines = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QString name = line.trimmed();
        if (name.isEmpty())
            continue;

        QString candidate = name;
        if (candidate.startsWith(QStringLiteral("webots_"))) {
            candidate = candidate.mid(7);
        } else if (candidate.startsWith(QStringLiteral("webots-"))) {
            candidate = candidate.mid(7);
        } else if (!candidate.startsWith(QStringLiteral("env_"))) {
            // Ignore unrelated containers
            continue;
        }

        // Skip pure-numeric entries — those are robot containers (webots_1, webots_2 …)
        bool isNumeric = false;
        candidate.toInt(&isNumeric);
        if (isNumeric)
            continue;

        if (!candidate.startsWith(QStringLiteral("env_")))
            continue;
        if (seen.contains(candidate))
            continue;

        seen.insert(candidate);
        worlds.append(candidate);
    }

    if (!worlds.isEmpty()) {
        qDebug() << "queryDockerWebotsWorlds: found worlds:" << worlds;
    } else {
        qDebug() << "queryDockerWebotsWorlds: no env_ world containers found";
    }
    emit simulationWorldsReceived(worlds);
}

void MapBridge::exitWebotsSim() { 
    QJsonObject obj; 
    obj["command"] = "exit_webots_sim"; 
    sendCommandToRos(obj);
    destroySimulationDockerContainers();
    setSimulationMode(false);
}

void MapBridge::destroySimulationDockerContainers()
{
    if (m_lastSimulationContainers.isEmpty()) {
        qDebug() << "destroySimulationDockerContainers: nothing to destroy";
        return;
    }

    for (const QString &name : std::as_const(m_lastSimulationContainers)) {
        if (name.isEmpty()) continue;
        QProcess p;
        p.start(QStringLiteral("docker"), QStringList{QStringLiteral("stop"), name});
        p.waitForFinished(15000);

        QProcess rm;
        rm.start(QStringLiteral("docker"), QStringList{QStringLiteral("rm"), name});
        if (!rm.waitForFinished(15000)) {
            qWarning() << "destroySimulationDockerContainers: timeout removing" << name;
        } else if (rm.exitCode() == 0) {
            qDebug() << "✅ removed container:" << name;
        } else {
            qWarning() << "destroySimulationDockerContainers: rm failed for" << name
                       << QString::fromUtf8(rm.readAllStandardError().trimmed());
        }
    }
    m_lastSimulationContainers.clear();
}
void MapBridge::setForgingPattern(const QString &pattern) { 
    QJsonObject obj; obj["command"] = "set_forging_pattern"; obj["pattern"] = pattern; sendCommandToRos(obj);
    emit forgingPatternChanged(pattern); 
}
void MapBridge::setFlockingMode(const QString &mode) { 
    QJsonObject obj; obj["command"] = "set_flocking_mode"; obj["mode"] = mode; sendCommandToRos(obj);
    emit flockingModeChanged(mode); 
}
void MapBridge::triggerTaskAllocation() { 
    QJsonObject obj; obj["command"] = "trigger_task_allocation"; sendCommandToRos(obj);
    emit taskAllocationTriggered(); 
}

void MapBridge::assignTaskToRobot(int robotId, double x, double y, const QString &taskName) {
    QJsonObject obj;
    obj["op"]    = QStringLiteral("publish");
    obj["topic"] = QStringLiteral("/task_allocation");
    QJsonObject msg;
    msg["robot_id"]  = robotId;
    msg["task_name"] = taskName;
    msg["target_x"]  = x;
    msg["target_y"]  = y;
    obj["msg"] = msg;
    qDebug() << "📋 Assigning task to robot" << robotId << ":" << taskName << "@" << x << y;
    sendCommandToRos(obj);
}
void MapBridge::requestTeleOp(int id) { 
    QJsonObject obj; obj["command"] = "request_teleop"; obj["device_id"] = id; sendCommandToRos(obj);
    emit teleOpRequested(id); 
}
void MapBridge::redirectToSensorControl(int id) { 
    emit sensorRedirectRequested(id); 
}

void MapBridge::emergencyStop() {
    m_emergencyActive = true;
    QJsonObject obj; obj["command"] = "emergency_stop"; sendCommandToRos(obj);
    emit emergencyActiveChanged();
    emit emergencyStopTriggered();
}

void MapBridge::emergencyResume() {
    m_emergencyActive = false;
    QJsonObject obj; obj["command"] = "emergency_resume"; sendCommandToRos(obj);
    emit emergencyActiveChanged();
    emit emergencyResumed();
}

void MapBridge::stopRobot(int deviceId) {
    int battery = m_deviceStatus.contains(deviceId) ? m_deviceStatus[deviceId].value("battery", QVariant(85)).toInt() : 85;
    m_deviceStatus[deviceId] = QVariantMap{{"active", false}, {"battery", battery}};
    emit robotStatusUpdated(deviceId, false, battery);
    QJsonObject obj; obj["command"] = "stop_robot"; obj["device_id"] = deviceId; sendCommandToRos(obj);
    teleOpMove(deviceId, 0.0, 0.0);
}

void MapBridge::resumeRobot(int deviceId) {
    int battery = m_deviceStatus.contains(deviceId) ? m_deviceStatus[deviceId].value("battery", QVariant(85)).toInt() : 85;
    m_deviceStatus[deviceId] = QVariantMap{{"active", true}, {"battery", battery}};
    emit robotStatusUpdated(deviceId, true, battery);
    QJsonObject obj; obj["command"] = "resume_robot"; obj["device_id"] = deviceId; sendCommandToRos(obj);
}

void MapBridge::teleOpMove(int deviceId, double linearVel, double angularVel) {
    qDebug() << "🕹️ Moving Robot" << deviceId << ":" << linearVel << angularVel;
    QJsonObject obj; obj["command"] = "teleop_move"; obj["device_id"] = deviceId; obj["linear_vel"] = linearVel; obj["angular_vel"] = angularVel; sendCommandToRos(obj);
}

void MapBridge::requestMapData(int deviceId) {
    QJsonObject obj;
    obj["command"] = "request_map_data";
    obj["device_id"] = deviceId;
    sendCommandToRos(obj);
}

void MapBridge::sendTask(int deviceId, const QVariantMap &target) {
    QJsonObject obj;
    obj["command"] = "send_task";
    obj["device_id"] = deviceId;
    obj["target"] = QJsonObject::fromVariantMap(target);
    sendCommandToRos(obj);
}

// FIX: Missing Update implementations
void MapBridge::updateSensorValue(int id, const QString &name, double val) { emit sensorUpdated(id, name, val); }
void MapBridge::updateNavParameters(int id, const QVariantMap &params) { emit navParametersUpdated(id, params); }
void MapBridge::setCameraView(int id, const QString &type) { emit cameraViewChanged(id, type); }

void MapBridge::sendSensorState(int deviceId, const QVariantMap &sensorStates) {
    QJsonObject obj;
    obj[QStringLiteral("command")]   = QStringLiteral("update_sensor_states");
    obj[QStringLiteral("device_id")] = deviceId;
    // Nest the sensor key-value pairs under "sensors" so the backend can parse them unambiguously
    obj[QStringLiteral("sensors")]   = QJsonObject::fromVariantMap(sensorStates);
    sendCommandToRos(obj);
}

void MapBridge::requestSensorState(int deviceId) {
    QJsonObject obj;
    obj[QStringLiteral("command")]   = QStringLiteral("get_sensor_state");
    obj[QStringLiteral("device_id")] = deviceId;
    sendCommandToRos(obj);
    qDebug() << "📡 requestSensorState sent for device" << deviceId;
}

void MapBridge::sendForagingPattern(const QVariantList &patternPoints) {
    QJsonObject obj;
    obj["command"] = "transmit_foraging_pattern";
    obj["pattern"] = QJsonArray::fromVariantList(patternPoints);
    sendCommandToRos(obj);
}

void MapBridge::onError(QAbstractSocket::SocketError error) {
    // This slot is connected for BOTH sockets (receive + command), so use sender()
    QWebSocket *ws = qobject_cast<QWebSocket *>(sender());
    const QString wsUrl = ws ? ws->requestUrl().toString() : QStringLiteral("<unknown>");
    const QString errStr = ws ? ws->errorString() : QStringLiteral("unknown");
    qDebug() << "❌ Socket Error occurred from" << wsUrl
             << "error=" << static_cast<int>(error)
             << "state=" << (ws ? ws->state() : QAbstractSocket::UnconnectedState)
             << "reason=" << errStr;
    // Keep trying to reconnect if we are not yet connected
    if (!m_connected && !m_reconnectTimer->isActive())
        m_reconnectTimer->start();
}

void MapBridge::applyTopicBasedRobotPresence(const QString &text)
{
    if (text.isEmpty())
        return;
    QRegularExpression re(QStringLiteral("(?:ugv_?0*|robot_?0*|device_?0*)(\\d+)"),
                          QRegularExpression::CaseInsensitiveOption);
    QRegularExpressionMatchIterator it = re.globalMatch(text);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        const int id = m.captured(1).toInt();
        if (id <= 0)
            continue;
        if (!m_deviceStatus.contains(id)) {
            m_deviceStatus[id] = QVariantMap{{QStringLiteral("active"), true}, {QStringLiteral("battery"), 0}};
            emit robotStatusUpdated(id, true, 0);
            qDebug() << "🤖 Robot" << id << "first seen → ONLINE (from topic/frame)";
        } else {
            const bool a = m_deviceStatus[id].value(QStringLiteral("active"), true).toBool();
            const int  b = m_deviceStatus[id].value(QStringLiteral("battery"), 0).toInt();
            emit robotStatusUpdated(id, a, b);
        }
    }
}

void MapBridge::parseRosMessage(const QByteArray &jsonBytes) {
    if (jsonBytes.size() > 100) {
        qDebug() << "⬇️ MapBridge received JSON payload of size:" << jsonBytes.size() << "bytes";
    } else if (!jsonBytes.isEmpty()) {
        // Log small messages in full so we can see their structure
        qDebug() << "⬇️ MapBridge small msg:" << QString::fromUtf8(jsonBytes.left(256));
    }

    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(jsonBytes, &error);
    if (doc.isNull()) {
        qDebug() << "❌ Dropped non-JSON websocket payload:" << error.errorString() << "at offset:" << error.offset;
        return;
    }
    if (doc.isArray()) {
        const QJsonArray arr = doc.array();
        for (const QJsonValue &v : arr) {
            if (v.isObject())
                parseRosMessage(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact));
        }
        return;
    }
    if (!doc.isObject()) {
        qDebug() << "❌ Dropped JSON payload because root is not an object";
        return;
    }
    QJsonObject root = doc.object();

    // ══════════════════════════════════════════════════════════════════════════
    // ROBOT STATUS — runs BEFORE any dispatch so early returns can't skip it
    // ══════════════════════════════════════════════════════════════════════════
    {
        // Helper: mark robot fully online with given status
        auto markOnline = [&](int id, bool active, int battery) {
            if (id <= 0) return;
            m_deviceStatus[id] = QVariantMap{{"active", active}, {"battery", battery}};
            emit robotStatusUpdated(id, active, battery);
            qDebug() << "🤖 Robot" << id << (active ? "ONLINE" : "STOPPED") << "bat:" << battery;
        };

        // Helper: first-seen marks online; subsequent calls preserve stored state
        auto markSeen = [&](int id) {
            if (id <= 0) return;
            if (!m_deviceStatus.contains(id)) {
                m_deviceStatus[id] = QVariantMap{{"active", true}, {"battery", 0}};
                emit robotStatusUpdated(id, true, 0);
                qDebug() << "🤖 Robot" << id << "first seen → ONLINE";
            } else {
                bool a = m_deviceStatus[id].value("active",  true).toBool();
                int  b = m_deviceStatus[id].value("battery", 0).toInt();
                emit robotStatusUpdated(id, a, b);
            }
        };

        // 1. Explicit battery / robot_id message (toVariant handles string IDs from JSON)
        if (root.contains("battery") || root.contains("robot_id") || root.contains("device_id")
            || root.contains(QStringLiteral("robotId")) || root.contains(QStringLiteral("deviceId"))) {
            int id = 0;
            if (root.contains("robot_id"))
                id = root["robot_id"].toVariant().toInt();
            else if (root.contains(QStringLiteral("robotId")))
                id = root[QStringLiteral("robotId")].toVariant().toInt();
            else if (root.contains("device_id"))
                id = root["device_id"].toVariant().toInt();
            else if (root.contains(QStringLiteral("deviceId")))
                id = root[QStringLiteral("deviceId")].toVariant().toInt();
            const bool act = root.value("active").toBool(true);
            const int  bat = root.value("battery").toInt(0);
            if (id > 0) markOnline(id, act, bat);
        }

        // 2. robot_status array
        if (root.contains("robot_status") && root["robot_status"].isArray()) {
            for (const QJsonValue &v : root["robot_status"].toArray()) {
                if (!v.isObject()) continue;
                QJsonObject r = v.toObject();
                int rid = 0;
                if (r.contains("robot_id"))
                    rid = r["robot_id"].toVariant().toInt();
                else if (r.contains(QStringLiteral("robotId")))
                    rid = r[QStringLiteral("robotId")].toVariant().toInt();
                else if (r.contains("device_id"))
                    rid = r["device_id"].toVariant().toInt();
                else if (r.contains(QStringLiteral("deviceId")))
                    rid = r[QStringLiteral("deviceId")].toVariant().toInt();
                if (rid > 0)
                    markOnline(rid, r["active"].toBool(true), r["battery"].toInt(0));
            }
        }

        // 3–4. Topic, nested msg.topic, msg.header.frame_id, device_id / ugv_id (+ camelCase, nested msg)
        if (root.contains("topic"))
            applyTopicBasedRobotPresence(root["topic"].toString());
        if (root.contains("msg") && root["msg"].isObject()) {
            const QJsonObject inner = root["msg"].toObject();
            if (inner.contains("topic"))
                applyTopicBasedRobotPresence(inner["topic"].toString());
            if (inner.contains("header") && inner["header"].isObject()) {
                const QString frameId = inner["header"].toObject().value(QStringLiteral("frame_id")).toString();
                applyTopicBasedRobotPresence(frameId);
            }
            const auto markInner = [&](const QString &key) {
                if (inner.contains(key))
                    markSeen(inner[key].toVariant().toInt());
            };
            markInner(QStringLiteral("device_id"));
            markInner(QStringLiteral("ugv_id"));
            markInner(QStringLiteral("deviceId"));
            markInner(QStringLiteral("ugvId"));
            markInner(QStringLiteral("robot_id"));
            markInner(QStringLiteral("robotId"));
        }
        if (root.contains("device_id"))
            markSeen(root["device_id"].toVariant().toInt());
        if (root.contains("ugv_id"))
            markSeen(root["ugv_id"].toVariant().toInt());
        if (root.contains(QStringLiteral("deviceId")))
            markSeen(root[QStringLiteral("deviceId")].toVariant().toInt());
        if (root.contains(QStringLiteral("ugvId")))
            markSeen(root[QStringLiteral("ugvId")].toVariant().toInt());
    }
    // ══════════════════════════════════════════════════════════════════════════

    // Worlds inventory for simulation ComboBox (backend responds to list_simulation_worlds)
    if (root.contains(QStringLiteral("worlds")) && root[QStringLiteral("worlds")].isArray()) {
        const QString cmd = root.value(QStringLiteral("command")).toString();
        const QString msgType = root.value(QStringLiteral("type")).toString();
        if (cmd == QStringLiteral("list_simulation_worlds_result")
            || cmd == QStringLiteral("simulation_worlds_list")
            || msgType == QStringLiteral("simulation_worlds")
            || root.contains(QStringLiteral("simulation_worlds_reply"))) {
            QVariantList worlds;
            for (const QJsonValue &v : root[QStringLiteral("worlds")].toArray()) {
                const QString s = v.toString();
                if (!s.isEmpty())
                    worlds.append(s);
            }
            if (!worlds.isEmpty())
                emit simulationWorldsReceived(worlds);
        }
    }

    // Task acknowledgement — backend publishes on tasks_ack topic
    {
        const QString topicStr = root.value(QStringLiteral("topic")).toString();
        const QJsonObject msgObj2 = root.value(QStringLiteral("msg")).isObject()
                                    ? root[QStringLiteral("msg")].toObject() : root;
        if (topicStr.contains(QStringLiteral("tasks_ack")) || root.value("command").toString() == "tasks_ack") {
            int robotId      = msgObj2.value(QStringLiteral("robot_id")).toInt();
            QString taskName = msgObj2.value(QStringLiteral("task_name")).toString();
            bool success     = msgObj2.value(QStringLiteral("success")).toBool(true);
            QString message  = msgObj2.value(QStringLiteral("message")).toString();
            qDebug() << "✅ tasks_ack received for robot" << robotId << "task:" << taskName << "success:" << success;
            emit taskAckReceived(robotId, taskName, success, message);
        }

        // Existing tasks list — load all robot tasks on connect
        if (topicStr.contains(QStringLiteral("existing_tasks"))
            || topicStr.contains(QStringLiteral("tasks_list"))
            || root.value("command").toString() == "existing_tasks") {
            // Pass through to QML as a mapDataReceived with topic tag
            QVariantMap taskMap = (root.contains("msg") && root["msg"].isObject())
                                  ? root["msg"].toObject().toVariantMap()
                                  : root.toVariantMap();
            taskMap["topic"] = "existing_tasks";
            emit mapDataReceived(taskMap);
        }

        // ── Sensor topic: backend pushes sensor values keyed by sensor_name ──────
        // Accepted shapes:
        //   { "command": "sensor_topic",  "device_id": N, "sensors": { "3d_lidar": 1, ... } }
        //   { "topic": "/ugv_01/sensors", "msg": { "device_id": N, "sensors": {...} } }
        //   { "command": "sensor_state_result", "device_id": N, "sensors": {...} }
        const QString cmdStr = root.value(QStringLiteral("command")).toString();
        const bool isSensorTopic =
            cmdStr == QStringLiteral("sensor_topic")
            || cmdStr == QStringLiteral("sensor_state_result")
            || cmdStr == QStringLiteral("sensor_states")
            || topicStr.contains(QStringLiteral("sensor"));

        if (isSensorTopic) {
            // Resolve device id and sensors object from either root or nested msg
            const QJsonObject sensorMsg = (root.contains(QStringLiteral("msg")) && root[QStringLiteral("msg")].isObject())
                                          ? root[QStringLiteral("msg")].toObject() : root;
            int devId = sensorMsg.value(QStringLiteral("device_id")).toInt(
                        root.value(QStringLiteral("device_id")).toInt());

            // sensors may live under "sensors" key or be flat in the msg object
            QJsonObject sensorsObj;
            if (sensorMsg.contains(QStringLiteral("sensors")) && sensorMsg[QStringLiteral("sensors")].isObject())
                sensorsObj = sensorMsg[QStringLiteral("sensors")].toObject();
            else if (root.contains(QStringLiteral("sensors")) && root[QStringLiteral("sensors")].isObject())
                sensorsObj = root[QStringLiteral("sensors")].toObject();
            else
                sensorsObj = sensorMsg;  // flat fallback

            for (auto it = sensorsObj.begin(); it != sensorsObj.end(); ++it) {
                const QString sensorName = it.key();
                // Skip non-sensor metadata keys
                if (sensorName == QStringLiteral("device_id") || sensorName == QStringLiteral("command")
                    || sensorName == QStringLiteral("topic")  || sensorName == QStringLiteral("schema"))
                    continue;
                const double sensorValue = it.value().toDouble();
                qDebug() << "📊 sensorUpdated device" << devId << sensorName << "=" << sensorValue;
                emit sensorUpdated(devId, sensorName, sensorValue);
            }
        }

        // ── Sensor state acknowledgement ──────────────────────────────────────────
        // Shape: { "command": "sensor_state_ack", "device_id": N, "success": true, "message": "..." }
        if (cmdStr == QStringLiteral("sensor_state_ack")
            || cmdStr == QStringLiteral("update_sensor_states_ack")
            || topicStr.contains(QStringLiteral("sensor_ack"))) {
            const QJsonObject ackMsg = (root.contains(QStringLiteral("msg")) && root[QStringLiteral("msg")].isObject())
                                       ? root[QStringLiteral("msg")].toObject() : root;
            const int devId      = ackMsg.value(QStringLiteral("device_id")).toInt(
                                   root.value(QStringLiteral("device_id")).toInt());
            const bool success   = ackMsg.value(QStringLiteral("success")).toBool(true);
            const QString ackMsg2 = ackMsg.value(QStringLiteral("message")).toString(
                                    success ? QStringLiteral("Sensor update applied") : QStringLiteral("Sensor update failed"));
            qDebug() << "📡 sensorStateAck device" << devId << "success:" << success << ackMsg2;
            emit sensorStateAckReceived(devId, success, ackMsg2);
        }
    }

    if (root.contains("op")) {
        QString op = root["op"].toString();
        if (op == "fragment") {
            QString id = root["id"].toString();
            int num = root["num"].toInt();
            int total = root["total"].toInt();
            QString data = root["data"].toString();
            if (id.isEmpty() || total <= 0 || num < 0 || num >= total || data.isEmpty()) {
                qDebug() << "❌ Dropped invalid JSON fragment payload";
                return;
            }

            if (!m_fragmentsTotal.contains(id)) {
                m_fragmentsTotal[id] = total;
                QStringList list;
                for (int i = 0; i < total; ++i) list.append("");
                m_fragments[id] = list;
            }

            m_fragments[id][num] = data;

            bool complete = true;
            for (const QString &s : m_fragments[id]) {
                if (s.isEmpty()) { complete = false; break; }
            }

            if (complete) {
                QByteArray fullMsg = m_fragments[id].join("").toUtf8();
                m_fragments.remove(id);
                m_fragmentsTotal.remove(id);
                parseRosMessage(fullMsg);
            }
            return;
        } else if (op == "publish") {
            QString topic = root["topic"].toString();
            QJsonObject msgObj = (root.contains("msg") && root["msg"].isObject())
                ? root["msg"].toObject() : QJsonObject();

            // Redundant safety: some paths only hit publish; also pick up frame_id in msg
            applyTopicBasedRobotPresence(topic);
            if (!msgObj.isEmpty() && msgObj.contains("header") && msgObj["header"].isObject()) {
                const QString frameId = msgObj["header"].toObject().value(QStringLiteral("frame_id")).toString();
                applyTopicBasedRobotPresence(frameId);
            }

            if (topic.contains("velodyne_points") || topic.contains("pointcloud") ||
                topic.contains("point_cloud")) {
                qDebug() << "📡 PointCloud topic received:" << topic;
                if (!msgObj.isEmpty())
                    parsePointCloud2(topic, msgObj);
            }

            if (topic.contains("/scan") && msgObj.contains("ranges") && msgObj["ranges"].isArray()) {
                qDebug() << "📡 LaserScan topic received:" << topic;
                double angleMin = msgObj["angle_min"].toDouble();
                double angleInc = msgObj["angle_increment"].toDouble();
                double rMin     = msgObj["range_min"].toDouble(0.1);
                double rMax     = msgObj["range_max"].toDouble(30.0);
                QJsonArray ranges = msgObj["ranges"].toArray();
                QVariantList points;
                for (int i = 0; i < ranges.size(); ++i) {
                    double r = ranges[i].toDouble();
                    if (r < rMin || r > rMax || std::isnan(r) || std::isinf(r)) continue;
                    double angle = angleMin + i * angleInc;
                    points.append(r * std::cos(angle));
                    points.append(r * std::sin(angle));
                    points.append(0.0);
                }
                QRegularExpression re2(QStringLiteral("/ugv_?0*(\\d+)/"));
                QRegularExpressionMatch m2 = re2.match(topic);
                const int scanDeviceId = m2.hasMatch() ? m2.captured(1).toInt() : 0;

                if (!points.isEmpty()) {
                    qDebug() << "📡 LaserScan →" << points.size()/3 << "points for robot" << scanDeviceId;
                    // Notify QML of a new robot so the ComboBox can be updated
                    if (!m_knownScanRobots.contains(scanDeviceId)) {
                        m_knownScanRobots.insert(scanDeviceId);
                        emit robotDiscovered(scanDeviceId);
                    }
                    // Dedicated per-robot scan signal (used by CenterPanel ComboBox selector)
                    emit laserScanReceived(scanDeviceId, points);
                }
            }

            if (topic.contains("map")) {
                if (!msgObj.isEmpty() && msgObj.contains("data") && msgObj["data"].isArray()) {
                    QVariantMap resultMap;
                    resultMap["topic"] = "map";
                    if (msgObj.contains("info")) {
                        QJsonObject infoObj = msgObj["info"].toObject();
                        resultMap["resolution"] = infoObj["resolution"].toDouble();
                        resultMap["width"] = infoObj["width"].toInt();
                        resultMap["height"] = infoObj["height"].toInt();
                        if (infoObj.contains("origin") && infoObj["origin"].toObject().contains("position")) {
                            QJsonObject posObj = infoObj["origin"].toObject()["position"].toObject();
                            QVariantMap originMap;
                            originMap["x"] = posObj["x"].toDouble();
                            originMap["y"] = posObj["y"].toDouble();
                            resultMap["origin"] = originMap;
                        }
                    } else {
                        resultMap["resolution"] = msgObj["resolution"].toDouble();
                        resultMap["width"] = msgObj["width"].toInt();
                        resultMap["height"] = msgObj["height"].toInt();
                    }
                    QVariantList dataList;
                    QJsonArray arr = msgObj["data"].toArray();
                    for (const QJsonValue &v : arr)
                        dataList.append(v.toInt());
                    resultMap["data"] = dataList;
                    emit mapDataReceived(resultMap);
                    return;
                }
            }

            if (topic.contains(QStringLiteral("/image_raw"))) {
                if (!msgObj.isEmpty() && msgObj.contains("data")) {
                    QString encoding = msgObj["encoding"].toString("rgb8");
                    int w = msgObj["width"].toInt();
                    int h = msgObj["height"].toInt();
                    int step = msgObj["step"].toInt(0);
                    QByteArray rawBytes;
                    if (msgObj["data"].isString()) {
                        rawBytes = QByteArray::fromBase64(msgObj["data"].toString().toLatin1());
                    } else if (msgObj["data"].isArray()) {
                        QJsonArray arr = msgObj["data"].toArray();
                        rawBytes.resize(arr.size());
                        for (int i = 0; i < arr.size(); ++i)
                            rawBytes[i] = static_cast<char>(arr[i].toInt());
                    }
                    qDebug() << "📷 Camera image_raw:" << topic << "encoding:" << encoding
                             << "size:" << w << "x" << h << "rawBytes:" << rawBytes.size();
                    if (!rawBytes.isEmpty()) {
                        QString base64out;
                        bool isJpeg = rawBytes.size() >= 2
                            && (unsigned char)rawBytes[0] == 0xFF
                            && (unsigned char)rawBytes[1] == 0xD8;
                        bool isPng = rawBytes.size() >= 4 && rawBytes.startsWith("\x89PNG");
                        if (isJpeg || isPng) {
                            base64out = rawBytes.toBase64();
                        } else if (w > 0 && h > 0) {
                            const QString enc = encoding.toLower();
                            if (enc == QStringLiteral("32fc1")) {
                                const int n = w * h;
                                if (rawBytes.size() >= n * 4) {
                                    const float *fp = reinterpret_cast<const float *>(rawBytes.constData());
                                    float minD = 1e9f, maxD = -1e9f;
                                    for (int i = 0; i < n; ++i) {
                                        float v = fp[i];
                                        if (!std::isnan(v) && !std::isinf(v) && v > 0) {
                                            if (v < minD) minD = v;
                                            if (v > maxD) maxD = v;
                                        }
                                    }
                                    float range = (maxD - minD) < 0.001f ? 1.0f : (maxD - minD);
                                    QByteArray gray8(n, '\0');
                                    for (int i = 0; i < n; ++i) {
                                        float v = fp[i];
                                        if (std::isnan(v) || std::isinf(v) || v <= 0) gray8[i] = 0;
                                        else {
                                            int g = static_cast<int>(((v - minD) / range) * 255.0f);
                                            gray8[i] = static_cast<char>(qBound(0, g, 255));
                                        }
                                    }
                                    QImage img(reinterpret_cast<const uchar *>(gray8.constData()),
                                               w, h, w, QImage::Format_Grayscale8);
                                    QByteArray jpegBuf;
                                    QBuffer jpegIO(&jpegBuf);
                                    jpegIO.open(QIODevice::WriteOnly);
                                    if (img.save(&jpegIO, "JPEG", 80))
                                        base64out = jpegBuf.toBase64();
                                }
                            } else if (enc == QStringLiteral("16uc1") || enc == QStringLiteral("mono16")) {
                                const int n = w * h;
                                if (rawBytes.size() >= n * 2) {
                                    const uint16_t *sp = reinterpret_cast<const uint16_t *>(rawBytes.constData());
                                    uint16_t minD = 65535, maxD = 0;
                                    for (int i = 0; i < n; ++i) {
                                        if (sp[i] > 0) {
                                            if (sp[i] < minD) minD = sp[i];
                                            if (sp[i] > maxD) maxD = sp[i];
                                        }
                                    }
                                    float range = (maxD - minD) < 1 ? 1.0f : float(maxD - minD);
                                    QByteArray gray8(n, '\0');
                                    for (int i = 0; i < n; ++i) {
                                        uint16_t v = sp[i];
                                        int g = v == 0 ? 0 : static_cast<int>((v - minD) / range * 255.0f);
                                        gray8[i] = static_cast<char>(qBound(0, g, 255));
                                    }
                                    QImage img(reinterpret_cast<const uchar *>(gray8.constData()),
                                               w, h, w, QImage::Format_Grayscale8);
                                    QByteArray jpegBuf;
                                    QBuffer jpegIO(&jpegBuf);
                                    jpegIO.open(QIODevice::WriteOnly);
                                    if (img.save(&jpegIO, "JPEG", 80))
                                        base64out = jpegBuf.toBase64();
                                }
                            } else {
                                QImage::Format fmt = QImage::Format_RGB888;
                                int bpp = 3;
                                if (enc == QStringLiteral("mono8") || enc == QStringLiteral("8uc1")) {
                                    fmt = QImage::Format_Grayscale8;
                                    bpp = 1;
                                } else if (enc == QStringLiteral("rgba8") || enc == QStringLiteral("8uc4")) {
                                    fmt = QImage::Format_RGBA8888;
                                    bpp = 4;
                                } else if (enc == QStringLiteral("bgr8")) {
                                    for (int i = 0; i + 2 < rawBytes.size(); i += 3) {
                                        char t = rawBytes[i];
                                        rawBytes[i]   = rawBytes[i + 2];
                                        rawBytes[i+2] = t;
                                    }
                                }
                                if (step <= 0)
                                    step = w * bpp;
                                const int minNeed = step * h;
                                if (rawBytes.size() >= minNeed || rawBytes.size() >= w * h * bpp) {
                                    const int bpl = (rawBytes.size() >= minNeed) ? step : (w * bpp);
                                    QImage im(reinterpret_cast<const uchar *>(rawBytes.constData()),
                                              w, h, bpl, fmt);
                                    QImage safe = im.copy();
                                    QByteArray jpegBuf;
                                    QBuffer jpegIO(&jpegBuf);
                                    jpegIO.open(QIODevice::WriteOnly);
                                    if (safe.save(&jpegIO, "JPEG", 80))
                                        base64out = jpegBuf.toBase64();
                                }
                            }
                        }
                        if (!base64out.isEmpty())
                            emit imageReceived(topic, base64out);
                    }
                }
            }

            const QString lowerTopic = topic.toLower();
            if (!msgObj.isEmpty() &&
                (lowerTopic.contains("path") || lowerTopic.contains("target") ||
                 lowerTopic.contains("goal") || lowerTopic.contains("pose") ||
                 lowerTopic.contains("odom") || lowerTopic.contains("robot_position"))) {
                QVariantMap navMap = msgObj.toVariantMap();
                navMap["topic"] = topic;
                emit mapDataReceived(navMap);
            }
        }
    }
    // Directly received msg (no wrapper)
    else if (root.contains("data") && root.contains("point_step")) {
        // Topic name might not be known if there's no wrapper, fallback to default
        QString top = root.contains("topic") ? root["topic"].toString() : "/ugv_01/velodyne_points";
        parsePointCloud2(top, root);
    }
    else if (root.contains("topic") && (root["topic"].toString() == "velodyne_points" || root["topic"].toString() == "map")) {
        // Direct array pass
        emit mapDataReceived(root.toVariantMap());
    }

}


void MapBridge::parsePointCloud2(const QString &topic, const QJsonObject &msg) {
    QString dataStr = msg["data"].toString();
    QByteArray dataBytes;

    if (!dataStr.isEmpty()) {
        dataBytes = QByteArray::fromBase64(dataStr.toUtf8());
    } else if (msg.contains("data") && msg["data"].isArray()) {
        QJsonArray arr = msg["data"].toArray();
        dataBytes.resize(arr.size());
        for (int i = 0; i < arr.size(); ++i) {
            dataBytes[i] = (char)arr[i].toInt();
        }
    } else {
        return;
    }

    int pointStep = msg["point_step"].toInt();
    int width = msg["width"].toInt();
    int height = msg["height"].toInt();
    int count = width * height;

    if (pointStep < 12 || dataBytes.isEmpty()) {
        return;
    }

    if (dataBytes.size() < count * pointStep || count <= 0) {
        count = dataBytes.size() / pointStep;
    }

    QVariantList points;
    const char *rawData = dataBytes.constData();

    int step = 1;
    const int maxPoints = 12000;
    if (count > maxPoints) {
        step = count / maxPoints;
    }

    for (int i = 0; i < count; i += step) {
        int offset = i * pointStep;

        float x, y, z;
        memcpy(&x, rawData + offset, 4);
        memcpy(&y, rawData + offset + 4, 4);
        memcpy(&z, rawData + offset + 8, 4);

        if (std::isnan(x) || std::isnan(y) || std::isnan(z)) continue;

        points.append(static_cast<double>(x));
        points.append(static_cast<double>(y));
        points.append(static_cast<double>(z));
    }

    QVariantMap result;
    result["topic"] = "velodyne_points";
    result["points"] = points;

    QRegularExpression re("/ugv_0?(\\d+)/");
    QRegularExpressionMatch match = re.match(topic);
    if (match.hasMatch()) {
        result["device_id"] = match.captured(1).toInt();
    } else {
        result["device_id"] = 0;
    }

    emit mapDataReceived(result);
}

void MapBridge::sendCommandToRos(const QJsonObject& payload) {
    if (payload.isEmpty()) {
        qDebug() << "❌ Refusing to send empty JSON command payload";
        return;
    }

    QJsonObject wrappedPayload = payload;
    if (!wrappedPayload.contains("command")) {
        qDebug() << "⚠ Sending JSON payload without 'command' field";
    }

    // Automatically append 'simulation' flag if we are in Simulation Mode
    if (m_simulationMode) {
        wrappedPayload["simulation_mode"] = true;
    }

    QJsonDocument doc(wrappedPayload);
    QString jsonStr = QString::fromUtf8(doc.toJson(QJsonDocument::Compact));
    qDebug() << "📤 Sending command to backend (port" << GUI_COMMAND_PORT << "):" << jsonStr;
    QWebSocket *sendSocket = (m_commandSocket && m_commandSocket->state() == QAbstractSocket::ConnectedState)
        ? m_commandSocket : m_socket;
    if (sendSocket && sendSocket->isValid()) {
        sendSocket->sendTextMessage(jsonStr);
    }
}

bool MapBridge::getRobotStatusActive(int robotId) const {
    if (!m_deviceStatus.contains(robotId)) return false;
    return m_deviceStatus[robotId].value("active").toBool();
}

int MapBridge::getRobotBattery(int robotId) const {
    if (!m_deviceStatus.contains(robotId)) return 0;
    return m_deviceStatus[robotId].value("battery").toInt();
}

