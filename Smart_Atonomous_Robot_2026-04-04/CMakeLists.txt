cmake_minimum_required(VERSION 3.24)
project(Smart_Atonomous_Robot_webs)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Force find the Gui module (which contains QGuiApplication)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick WebSockets)

qt_add_executable(appSmart_Atonomous_Robot
    main.cpp
)

qt_add_qml_module(appSmart_Atonomous_Robot
    URI MainQmlModule
    VERSION 1.0
    SOURCES
        mapbridge.h
        mapbridge.cpp
    QML_FILES
        main.qml
        LoginPage.qml
        BasePage.qml
        Tooltip.qml
        CenterPanel.qml
        DeviceStatusBlock.qml
        DeviceCameraBlock.qml
        SensorScreen.qml
        NavPageScreen.qml
        MaximizedViewScreen.qml
        TaskAllocationPopup.qml
        TeleOpScreen.qml
        SimulationConfigPopup.qml
        ForagingPopup.qml
        RESOURCES icons.qrc
        Theme.qml
        GlassCard.qml
        NeoButton.qml
        PanelHeader.qml
        StatusPill.qml
)

set_target_properties(appSmart_Atonomous_Robot PROPERTIES OUTPUT_NAME "Smart_Atonomous_Robot")

# Explicitly link Qt6::Gui
target_link_libraries(appSmart_Atonomous_Robot
    PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::WebSockets
)

