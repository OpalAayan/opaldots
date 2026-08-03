import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/* DateModule.qml — Current Date with beautiful custom Calendar popup */

Badge {
    id: dateBadge
    property var currentDate: new Date()
    property var displayDate: new Date()
    property bool popupVisible: false

    Timer {
        interval: 60000 // 1 minute
        running: true
        repeat: true
        onTriggered: dateBadge.currentDate = new Date()
    }

    icon: ""
    label: currentDate.toLocaleDateString(Qt.locale(), "ddd dd MMM")
    accentColor: "#94e2d5"
    tooltipText: "" // disable default tooltip

    focus: true
    Keys.onEscapePressed: (event) => {
        if (popupVisible) {
            popupVisible = false
            event.accepted = true
        }
    }

    onClicked: {
        popupVisible = !popupVisible
        if (popupVisible) {
            // Reset the calendar to the current month when opened
            displayDate = new Date(currentDate.getFullYear(), currentDate.getMonth(), 1)
            dateBadge.forceActiveFocus()
        }
    }

    PopupWindow {
        id: calendarPopup
        visible: dateBadge.popupVisible
        anchor.item: dateBadge
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 8
        
        implicitWidth: 260
        implicitHeight: 290
        
        color: "transparent"

        Rectangle {
            focus: true
            Keys.onEscapePressed: (event) => {
                dateBadge.popupVisible = false
                event.accepted = true
            }
            onVisibleChanged: {
                if (visible) {
                    forceActiveFocus()
                }
            }
            anchors.fill: parent
            color: "#1e1e2e"
            radius: 12
            border.color: dateBadge.accentColor
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header: Month and Year with Navigation
                RowLayout {
                    Layout.fillWidth: true
                    
                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 4
                        color: prevMouseArea.containsMouse ? "#313244" : "transparent"
                        
                        Text {
                            anchors.centerIn: parent
                            text: ""
                            color: "#cdd6f4"
                            font.family: dateBadge.fontFamily
                            font.pixelSize: 14
                        }
                        
                        MouseArea {
                            id: prevMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                var newDate = new Date(dateBadge.displayDate.getFullYear(), dateBadge.displayDate.getMonth() - 1, 1);
                                dateBadge.displayDate = newDate;
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: dateBadge.displayDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                        color: "#cdd6f4"
                        font.family: dateBadge.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 4
                        color: nextMouseArea.containsMouse ? "#313244" : "transparent"
                        
                        Text {
                            anchors.centerIn: parent
                            text: ""
                            color: "#cdd6f4"
                            font.family: dateBadge.fontFamily
                            font.pixelSize: 14
                        }
                        
                        MouseArea {
                            id: nextMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                var newDate = new Date(dateBadge.displayDate.getFullYear(), dateBadge.displayDate.getMonth() + 1, 1);
                                dateBadge.displayDate = newDate;
                            }
                        }
                    }
                }
                
                // Separator
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#313244"
                }

                // Calendar Grid
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    rows: 7
                    columnSpacing: 4
                    rowSpacing: 4

                    // Days of week header
                    Repeater {
                        model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
                        Text {
                            text: modelData
                            color: "#9399b2"
                            font.family: dateBadge.fontFamily
                            font.pixelSize: 14
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                        }
                    }

                    // Month days
                    Repeater {
                        model: {
                            var yr = dateBadge.displayDate.getFullYear();
                            var mo = dateBadge.displayDate.getMonth();
                            var d = new Date(yr, mo, 1);
                            var startDay = d.getDay(); // 0 is Sunday
                            var daysInMonth = new Date(yr, mo + 1, 0).getDate();
                            var totalCells = 42; // 6 rows * 7 cols
                            var arr = [];
                            for (var i = 0; i < totalCells; i++) {
                                if (i < startDay || i >= startDay + daysInMonth) {
                                    arr.push("");
                                } else {
                                    arr.push((i - startDay + 1).toString());
                                }
                            }
                            return arr;
                        }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: isToday ? "rgba(148, 226, 213, 0.2)" : "transparent"
                            radius: 6
                            border.color: isToday ? "#94e2d5" : "transparent"
                            border.width: 1

                            property bool isToday: {
                                if (modelData === "") return false;
                                return dateBadge.currentDate.getDate().toString() === modelData &&
                                       dateBadge.currentDate.getMonth() === dateBadge.displayDate.getMonth() &&
                                       dateBadge.currentDate.getFullYear() === dateBadge.displayDate.getFullYear();
                            }

                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: isToday ? "#94e2d5" : "#cdd6f4"
                                font.family: dateBadge.fontFamily
                                font.pixelSize: 14
                                font.bold: isToday
                            }
                        }
                    }
                }
            }
        }
    }
}
