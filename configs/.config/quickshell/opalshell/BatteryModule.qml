import QtQuick

/* BatteryModule.qml — Battery Status */

Badge {
    id: batBadge
    property int capacity: SysBridge.batteryCapacity
    property string status: SysBridge.batteryStatus
    property bool charging: status === "Charging"
    property bool plugged: status === "Full" || status === "Not charging"
    property bool hasBat: SysBridge.hasBattery

    icon: {
        if (!hasBat) return "󱟩";
        if (charging) return "󰂄";
        if (capacity > 80) return " ";
        if (capacity > 60) return " ";
        if (capacity > 40) return " ";
        if (capacity > 20) return " ";
        return " ";
    }

    label: hasBat ? capacity + "%" : ""
    showLabel: hasBat
    accentColor: {
        if (charging || plugged) return "#a6e3a1";
        if (capacity <= 15) return "#f38ba8";
        if (capacity <= 30) return "#f9e2af";
        return "#a6e3a1";
    }
    tooltipText: capacity >= 0 ? ("Battery: " + capacity + "%\nStatus: " + (charging ? "Charging" : "Discharging")) : "No Battery"
    pulsing: hasBat && !charging && capacity <= 15
    visible: hasBat

    SequentialAnimation on opacity {
        running: batBadge.charging
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.55; duration: 1200; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.55; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
    }
}
