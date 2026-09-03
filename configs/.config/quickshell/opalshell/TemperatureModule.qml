import QtQuick

/* TemperatureModule.qml — CPU Temperature */

Badge {
    property int temp: SysBridge.temperature
    property bool hot: temp >= 80

    icon: hot ? "" : ""
    label: temp + "\u{00b0}C"
    accentColor: hot ? "#f38ba8" : "#89dceb"
    tooltipText: "System Temperature: " + temp + "\u{00b0}C"
    pulsing: hot
}
