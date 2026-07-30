import QtQuick
import Quickshell.Io

/* DiskModule.qml — Disk Usage */

Badge {
    icon: ""
    label: SysBridge.diskUsage + "%"
    accentColor: "#f9e2af"
    tooltipText: "Disk Usage: " + SysBridge.diskUsage + "%"

    onClicked: {
        proc.running = true
    }

    Process {
        id: proc
        command: ["baobab"]
        running: false
    }
}
