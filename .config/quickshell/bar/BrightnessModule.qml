import QtQuick
import Quickshell.Io

/* BrightnessModule.qml — Screen Brightness */

Badge {
    icon: "󱞖"
    label: SysBridge.brightness + "%"
    showLabel: false
    accentColor: isHovered ? "#f5c2e7" : "#f9e2af"
    iconSize: 14
    implicitWidth: 34
    tooltipText: "Brightness: " + SysBridge.brightness + "%"

    onScrollUp: {
        upProc.running = true
    }
    onScrollDown: {
        downProc.running = true
    }

    Process {
        id: upProc
        command: ["sh", "-c", "~/.config/waybar/scripts/brightness_waybar.sh up"]
        running: false
    }
    Process {
        id: downProc
        command: ["sh", "-c", "~/.config/waybar/scripts/brightness_waybar.sh down"]
        running: false
    }
}
