import QtQuick
import Quickshell.Io

/* LauncherModule.qml — Fuzzel Launcher */

Badge {
    icon: "󰣇"
    label: "Launcher"
    showLabel: false
    accentColor: isHovered ? "#cba6f7" : "#89b4fa"
    tooltipText: "App Launcher"
    iconSize: 18
    implicitWidth: 36

    onClicked: {
        proc.running = true
    }

    Process {
        id: proc
        command: ["rofi", "-show", "drun", "-show-icons"]
        running: false
    }
}
