import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

ShellRoot {
    PanelWindow {
        id: bar
        anchors {
            top: true
            left: true
            right: true
        }
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Delay setting OnDemand by 1s to prevent Hyprland from stealing focus on startup
        Timer {
            interval: 1000
            running: true
            onTriggered: bar.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand
        }
        
        // Zero margins for a true full-width solid bar
        margins {
            top: 2
            bottom: -2
            left: 5
            right: 5
        }
        
        // Comfortable, pleasing height
        implicitHeight: 37
        
        // Solid pleasing background
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(17/255, 17/255, 27/255, 0.98) // Deep dark base (Catppuccin Crust)
            
                      radius: 8
            
            // Very subtle bottom border to detach from windows
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Qt.rgba(255/255, 255/255, 255/255, 0.05)
            }
            
            // LEFT: System Information
            RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                
                LauncherModule {}
                CpuModule {}
                MemoryModule {}
                DiskModule {}
                TemperatureModule {}
            }
            
            // CENTER: Workspaces (Perfectly absolute centered)
            WorkspaceBar {
                anchors.horizontalCenter: parent.horizontalCenter
                
                // ==========================================
                // TWEAK WORKSPACE BAR POSITION HERE:
                // Move the entire workspace block left or right.
                // Positive number = move right
                // Negative number = move left
                anchors.horizontalCenterOffset: 10
                // ==========================================
                
                anchors.verticalCenter: parent.verticalCenter
                monitorName: bar.screen.name
            }
            
            // RIGHT: Time, Context, Connectivity, Power
            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                
                // ==========================================
                // TWEAK INDIVIDUAL GAPS HERE:
                // You can add `Layout.leftMargin` or `Layout.rightMargin`
                // to ANY module to give it extra space without affecting the others!
                // ==========================================

                DateModule {}
                
                ClockModule {
                  Layout.leftMargin:0
                  Layout.rightMargin:2
                  Layout.topMargin:0
                  Layout.bottomMargin:0 
                }
                
                NightlightModule {
                  Layout.leftMargin:0
                  Layout.rightMargin:-8
                  Layout.topMargin:0
                  Layout.bottomMargin:0
                }
                BrightnessModule {
                  Layout.leftMargin:0
                  Layout.rightMargin:-8
                  Layout.topMargin:0
                  Layout.bottomMargin:0
                }
                
                NetworkModule {
                  id: networkModule
                  Layout.leftMargin:0
                  Layout.rightMargin:-6
                  Layout.topMargin:0
                  Layout.bottomMargin:0 
                }
                
                BluetoothModule {
                  networkModuleRef: networkModule
                  Layout.leftMargin:1
                  Layout.rightMargin:1
                  Layout.topMargin:0
                  Layout.bottomMargin:0
                }
                AudioModule {
                  Layout.leftMargin:2
                  Layout.rightMargin:-2
                  Layout.topMargin:0
                  Layout.bottomMargin:0
                }
                BatteryModule {}
                PowerModule {
                  Layout.leftMargin:0
                  Layout.rightMargin:-2
                  Layout.topMargin:0
                  Layout.bottomMargin:0
                }
            }
        }
    }
}
