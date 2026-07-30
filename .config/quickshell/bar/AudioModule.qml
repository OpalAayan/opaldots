import QtQuick
import Quickshell.Io

/* AudioModule.qml — Volume Control */

Badge {
    id: audioBadge
    property int volume: SysBridge.audioVolume
    property bool isMuted: SysBridge.audioMuted

    function getVolumeIcon() {
      if (isMuted) return "󰖁";
      if(volume>100) return "";
        if (volume == 100) return ""; // Overdrive
        if (volume >= 51) return ""; // High
        if (volume >= 1) return "";  // Medium/Low
        return ""; // 0% / Muted
    }

    icon: getVolumeIcon()
    label: volume + "%"
    accentColor: isMuted ? "#6c7086" : "#fab387"
    tooltipText: "Volume: " + volume + "%" + (isMuted ? " (Muted)" : "")

    Process {
        id: audioWatcher
        command: ["wpctl", "subscribe"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                if (data.indexOf("sink") !== -1 || data.indexOf("server") !== -1) {
                    audioDebounce.restart();
                }
            }
        }
    }

    Timer {
        id: audioDebounce
        interval: 10
        repeat: false
        onTriggered: SysBridge.forceUpdate()
    }

    Timer {
        id: quickUpdateTimer
        interval: 5
        repeat: false
        onTriggered: SysBridge.forceUpdate()
    }

    onClicked: {
        pavuProc.running = true
    }
    onRightClicked: {
        muteProc.running = true
    }
    onScrollUp: {
        upProc.running = true
        quickUpdateTimer.restart()
    }
    onScrollDown: {
        downProc.running = true
        quickUpdateTimer.restart()
    }

    Process {
        id: pavuProc
        command: ["pavucontrol"]
        running: false
    }
    Process {
        id: muteProc
        command: ["wpctl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]
        running: false
    }
    Process {
        id: upProc
        command: ["sh", "-c", "~/.config/waybar/scripts/scroll_volume.sh up"]
        running: false
    }
    Process {
        id: downProc
        command: ["sh", "-c", "~/.config/waybar/scripts/scroll_volume.sh down"]
        running: false
    }
}
