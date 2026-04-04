import QtQuick 2.15

QtObject {
    id: theme

    // Core palette inspired by reference image.
    readonly property color bg0: "#050B12"
    readonly property color bg1: "#0A1622"
    readonly property color bg2: "#12263A"
    readonly property color glass0: "#152B3D"
    readonly property color glass1: "#1B364C"
    readonly property color glassStroke: "#2E546D"
    readonly property color neon: "#7BFF4F"
    readonly property color neonSoft: "#67D646"
    readonly property color cyan: "#31E0FF"
    readonly property color warning: "#F6B142"
    readonly property color danger: "#DB1A1A"
    readonly property color textPrimary: "#EAF6FF"
    readonly property color textSecondary: "#8FB0C7"
    readonly property color textMuted: "#5D7E96"

    // Shape / spacing
    readonly property int radiusSm: 8
    readonly property int radiusMd: 12
    readonly property int radiusLg: 18
    readonly property int spacingSm: 8
    readonly property int spacingMd: 12
    readonly property int spacingLg: 18

    // Common glows
    readonly property color glowNeon: Qt.rgba(neon.r, neon.g, neon.b, 0.30)
    readonly property color glowCyan: Qt.rgba(cyan.r, cyan.g, cyan.b, 0.24)
}
