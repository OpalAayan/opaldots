import QtQuick
import Quickshell.Io

/* MemoryModule.qml — Memory Usage */

Badge {
    icon: ""
    label: SysBridge.memoryUsage + "%"
    accentColor: SysBridge.memoryUsage > 90 ? "#f38ba8" : "#a6e3a1"
    pulsing: SysBridge.memoryUsage > 90
    tooltipText: "Memory Usage: " + SysBridge.memoryUsage + "%"

    onClicked: {
        proc.running = true
    }

    Process {
        id: proc
        command: ["sh", "-c", "~/.config/waybar/scripts/btop-floating.sh"]
        running: false
    }
}
