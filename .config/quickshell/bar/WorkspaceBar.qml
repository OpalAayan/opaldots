import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: wsBar
    implicitWidth: wsRow.implicitWidth + 8
    implicitHeight: 28

    property string monitorName: ""
    property var allWorkspaces: Hyprland.workspaces.values
    property int activeId: Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1

    property var persistentWorkspaces: {
        if (monitorName.startsWith("LVDS") || monitorName.startsWith("eDP")) {
            return [1, 2, 3, 4];
        } else {
            return [6, 7, 8, 9]; // external monitor
        }
    }

    property var activeWorkspaces: {
        var set = {};
        
        // 1. Add persistent workspaces for this monitor
        for (var i = 0; i < persistentWorkspaces.length; ++i) {
            set[persistentWorkspaces[i]] = true;
        }
        
        // 2. Add existing ones on THIS monitor ONLY
        for (var i = 0; i < allWorkspaces.length; ++i) {
            var w = allWorkspaces[i];
            if (w.id > 0 && w.monitor && w.monitor.name === monitorName) {
                set[w.id] = true;
            }
        }
        
        var arr = Object.keys(set).map(function(k) { return parseInt(k); });
        arr.sort(function(a, b) { return a - b; });
        return arr;
    }

    RowLayout {
        id: wsRow
        anchors.centerIn: parent
        spacing: 6

        Repeater {
            model: wsBar.activeWorkspaces

            Rectangle {
                id: wsBtn
                property int wsId: modelData
                property bool isActive: wsBar.activeId === wsId
                property var wsObj: Hyprland.workspaces.values.find(w => w.id === wsId)
                property bool hasWindows: wsObj !== undefined && wsObj !== null && wsObj.windows > 0
                property bool isUrgent: (wsObj !== undefined && wsObj !== null && typeof wsObj.hasUrgent !== "undefined") ? wsObj.hasUrgent : false

                // ==========================================
                // TWEAK WORKSPACE CIRCLE SHAPE/SIZE HERE:
                // For a perfect circle, inactive width and height MUST be equal,
                // and the radius MUST be exactly HALF of that number!
                // Example: Width 24, Height 24, Radius 12
                Layout.preferredWidth: isActive ? 30 : 28 // 30 when active, 22 when inactive
                Layout.preferredHeight: 22 // 22 tall always
                radius: 11 // Half of 22 = perfect circle!
                // ==========================================

                // Elegant highlight for active workspace
                color: isActive 
                       ? Qt.rgba(203/255, 166/255, 247/255, 1.0) // Mauve solid
                       : (wsMouseArea.containsMouse ? Qt.rgba(255/255, 255/255, 255/255, 0.08) : "transparent")

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutExpo } }

                Text {
                    anchors.centerIn: parent
                    
                    // ==========================================
                    // TWEAK THESE VALUES TO PERFECTLY CENTER IT:
                    // Positive values move text right/down
                    // Negative values move text left/up
                    anchors.horizontalCenterOffset: -0.5
                    anchors.verticalCenterOffset: 1
                    // ==========================================
                    
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: wsBtn.wsId
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                    font.bold: true
                    // Text is dark when active, light when inactive
                    color: wsBtn.isActive 
                           ? "#11111b" 
                           : (wsBtn.hasWindows ? "#cdd6f4" : "#6c7086")
                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                // Tiny elegant dot indicator for workspaces with windows but not active
                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: "#cdd6f4"
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -2
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !wsBtn.isActive && wsBtn.hasWindows && !wsBtn.isUrgent
                }

                // Urgent Indicator: Bottom Red Bar (inset 0 -3px #f38ba8)
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    height: 3
                    radius: 2
                    color: "#f38ba8"
                    visible: wsBtn.isUrgent
                }

                // Urgent Indicator: Pulsing Outer Glow
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 4
                    height: parent.height + 4
                    radius: wsBtn.radius + 2
                    color: "transparent"
                    border.color: "#f38ba8"
                    border.width: 2
                    opacity: 0
                    visible: wsBtn.isUrgent

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: wsBtn.isUrgent
                        NumberAnimation { from: 0; to: 0.6; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.6; to: 0; duration: 600; easing.type: Easing.InOutSine }
                    }
                }

                MouseArea {
                    id: wsMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        wsProc.command = ["hyprctl", "dispatch",
                            "hl.dsp.focus({ workspace = \"" + wsBtn.wsId + "\" })"]
                        wsProc.running = true
                    }
                }

                Process {
                    id: wsProc
                    running: false
                }
            }
        }
    }
}
