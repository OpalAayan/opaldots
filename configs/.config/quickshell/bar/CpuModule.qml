import QtQuick
import Quickshell.Io

/* CpuModule.qml — CPU Usage */

Badge {
    icon: ""
    label: SysBridge.cpuUsage + "%"
    accentColor: "#cba6f7"
    tooltipText: "CPU Usage: " + SysBridge.cpuUsage + "%"

    onClicked: {
        proc.running = true
    }

    Process {
        id: proc
        command: ["sh", "-c", "~/.config/waybar/scripts/btop-floating.sh"]
        running: false
    }
}
