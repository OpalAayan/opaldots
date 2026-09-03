import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

ShellRoot {
    PanelWindow {
        id: bar
        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 40
        
        Timer {
            interval: 500
            running: true
            onTriggered: {
                var ws = Hyprland.workspaces.values;
                console.log("Found workspaces: " + ws.length);
                if (ws.length > 0) {
                    console.log("Workspace 0 props:");
                    for (var key in ws[0]) {
                        console.log(key, ws[0][key]);
                    }
                    if (ws[0].monitor) {
                        console.log("Monitor type:", typeof ws[0].monitor);
                        for (var mkey in ws[0].monitor) {
                            console.log("monitor." + mkey, ws[0].monitor[mkey]);
                        }
                    }
                }
                Qt.quit();
            }
        }
    }
}
