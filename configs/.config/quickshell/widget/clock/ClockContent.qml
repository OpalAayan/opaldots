import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Effects

Item {
    anchors.fill: parent

    SystemClock {
        id: sysTime
        precision: SystemClock.Seconds
    }

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
            implicitWidth: 12       // The width of our invisible box
            implicitHeight: 10      // The height of our invisible box

            // --- THE SLASH SEPARATOR ---
            Text {
                anchors.centerIn: parent
                // TICKLE THESE TO MOVE THE SLASH:
                anchors.horizontalCenterOffset: -75   // Nudge LEFT (negative) or RIGHT (positive)
                anchors.verticalCenterOffset: 0       // Nudge UP (negative) or DOWN (positive)

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
                anchors.verticalCenterOffset: 0      // Nudge UP (negative) or DOWN (positive)

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
