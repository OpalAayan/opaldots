import QtQuick 
import Quickshell 
import Quickshell.Wayland
import QtQuick.Layouts
import QtQuick.Effects
 
PanelWindow {
    WlrLayershell.layer: WlrLayer.Bottom
    exclusiveZone: 0
    
    // ==========================================
    // 1. WINDOW POSITIONING (THE PLACEHOLDERS)
    // ==========================================
    // Turn these to 'true' to glue the window to that side.
    anchors {
        top: true
        right: true
        // left: true
        // bottom: true
    }
 
    // Push the window away from the edges here!
    // Note: These only work if the matching anchor above is 'true'
    margins {
        top: 15
        right : 650
        //left: 600
        // bottom: 0
    }

    // The size of the invisible master window holding everything
    implicitWidth: 800
    implicitHeight: 180
    color: "transparent"
 
    SystemClock {
        id: sysTime
        precision: SystemClock.Seconds
    }
 
    // ==========================================
    // 2. THE CONTENT ALIGNMENT
    // ==========================================
    ColumnLayout {
        anchors.centerIn: parent
        anchors.horizontalCenter: parent.horizontalCenter
        
        // --- THE DAY ---
        Text {
            text: Qt.formatDateTime(sysTime.date, "dddd").toUpperCase()
            font.family: "Anurati"
            font.pixelSize: 64 
            font.letterSpacing: 30
            color: "#ffffff"
            
            // Text Shadow Settings
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true 
                shadowColor: '#000000'
                shadowBlur: 0.5
                shadowVerticalOffset: 3
                shadowHorizontalOffset: 3
            }
        }
 
        // --- THE INVISIBLE BOX FOR TIME & DATE ---
        // We use an Item instead of a Row so we can nudge Time and Date independently!
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10    // Push the whole invisible box DOWN, away from the Day text
            implicitWidth: 12      // The width of our invisible box
            implicitHeight: 10     // The height of our invisible box

    
         // --- THE SLASH SEPARATOR ---
            Text {
                anchors.centerIn: parent
                // TICKLE THESE TO MOVE THE SLASH:
                anchors.horizontalCenterOffset: -75   // Nudge LEFT (negative) or RIGHT (positive)
                anchors.verticalCenterOffset: 0   // Nudge UP (negative) or DOWN (positive)
                
                text: "/"
                font {
                    family: "FiraCode Nerd Font"
                    pixelSize: 25
                    letterSpacing: 2
                    bold: true
                }
                color: '#ffffff'
                
                // Text Shadow Settings
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true 
                    shadowColor: '#000000'
                    shadowBlur: 0.5
                    shadowVerticalOffset: 3
                    shadowHorizontalOffset: 3 
                }
            }


            // --- THE TIME ---
            Text {
                anchors.centerIn: parent
                // TICKLE THESE TO MOVE THE TIME:
                anchors.horizontalCenterOffset: -140 // Nudge LEFT (negative) or RIGHT (positive)
                anchors.verticalCenterOffset: 0     // Nudge UP (negative) or DOWN (positive)

                textFormat: Text.RichText
                text: Qt.formatDateTime(sysTime.date, "hh:mm")
                font {
                    family: "FiraCode Nerd Font"
                    pixelSize: 25
                    letterSpacing: 2
                    bold: true
                }
                color: '#ffffff'
                
                // Text Shadow Settings
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true 
                    shadowColor: '#000000'
                    shadowBlur: 0.5
                    shadowVerticalOffset: 3
                    shadowHorizontalOffset: 3 
                }
            }
                      // --- THE DATE ---
            Text {
                anchors.centerIn: parent
                // TICKLE THESE TO MOVE THE DATE:
                anchors.horizontalCenterOffset: 30  // Nudge LEFT (negative) or RIGHT (positive)
                anchors.verticalCenterOffset: 0     // Nudge UP (negative) or DOWN (positive)

                textFormat: Text.RichText
                text: Qt.formatDateTime(sysTime.date, "dd:MM:yyyy")
                font {
                    family: "FiraCode Nerd Font"
                    pixelSize: 25
                    letterSpacing: 2
                    bold: true
                }
                color: '#ffffff' 
                
                // Text Shadow Settings
                layer.enabled: true 
                layer.effect: MultiEffect {
                    shadowEnabled: true 
                    shadowColor: '#000000'
                    shadowBlur: 0.5
                    shadowVerticalOffset: 3
                    shadowHorizontalOffset: 3 
                } 
            }
        } 
    }
}
