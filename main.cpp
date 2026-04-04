#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QCoreApplication>
#include <QFile>
#include <QDir>
#include "mapbridge.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;
    MapBridge mapBridge;
    engine.rootContext()->setContextProperty("mapBridge", &mapBridge);

    // Load main.qml - use source file path directly (works reliably in development)
    // For production builds, you can switch to: QUrl(QStringLiteral("qrc:/Smart_Atonomous_Robot/main.qml"))
    const QUrl url = QUrl::fromLocalFile(QStringLiteral("/home/dinesh/Downloads/QT_Projects/Versions/Smart_Atonomous_Robot_3d done/Smart_Atonomous_Robot_ latest/Smart_Atonomous_Robot/main.qml"));

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl) {
            qDebug() << "❌ FATAL: QML object creation failed for" << objUrl;
            QCoreApplication::exit(-1);
        }
    }, Qt::QueuedConnection);

    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qDebug() << "❌ FATAL: No root QML objects created!";
        return -1;
    }

    qDebug() << "✅ QML loaded successfully, showing UI...";
    return app.exec();
}
