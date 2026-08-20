import QtQuick
import Quickshell.Io

/* NightlightModule.qml — Night Light Toggle */

Badge {
    icon: "󰖔"
    label: "Nightlight"
    accentColor: isHovered ? "#fab387" : "#cba6f7"
    tooltipText: "Toggle Nightlight"
    showLabel: false
    iconSize: 14
    implicitWidth: 34

    onClicked: {
        toggleProc.running = true
    }
    onScrollUp: {
        incProc.running = true
    }
    onScrollDown: {
        decProc.running = true
    }

    Process {
        id: toggleProc
        command: ["sh", "-c", "~/.config/waybar/scripts/nightlight_control.sh"]
        running: false
    }
    Process {
        id: incProc
        command: ["sh", "-c", "~/.config/waybar/scripts/nightlight_control.sh increase"]
        running: false
    }
    Process {
        id: decProc
        command: ["sh", "-c", "~/.config/waybar/scripts/nightlight_control.sh decrease"]
        running: false
    }
}
