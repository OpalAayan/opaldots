import QtQuick
import Quickshell.Io

/* PowerModule.qml — Power / Logout */

Badge {
    icon: "⏻"
    label: ""
    showLabel: false
    accentColor: isHovered ? "#f5c2e7" : "#f38ba8"
    tooltipText: "Power Menu"
    iconSize: 14
    implicitWidth: 34

    onClicked: {
        proc.running = true
    }

    Process {
        id: proc
        command: ["sh", "-c", "~/.config/wlogout/launch.sh"]
        running: false
    }
}
