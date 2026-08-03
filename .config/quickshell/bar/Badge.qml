import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Rectangle {
    id: badge

    property string tooltipText: ""
    property string icon: ""
    property string label: ""
    property color accentColor: "#89b4fa"
    property bool showLabel: true
    property bool interactive: true
    property real iconSize: 14
    property real labelSize: 13
    
    // ==========================================
    // TWEAK THESE TO PERFECTLY ALIGN ICONS/TEXT:
    property real iconVerticalOffset: 0
    property real labelVerticalOffset: 0
    // ==========================================
    property string fontFamily: "JetBrainsMono Nerd Font"
    property bool critical: false
    property bool pulsing: false
    property bool showTooltip: false
    
    signal clicked()
    signal rightClicked()
    signal scrollUp()
    signal scrollDown()

    implicitWidth: row.implicitWidth + 8
    implicitHeight: 28
    Layout.preferredHeight: 28

    // Subtle, elegant hover state inside the bar
    color: mouseArea.containsMouse ? Qt.rgba(255/255, 255/255, 255/255, 0.06) : "transparent"
    radius: 6

    Behavior on color { ColorAnimation { duration: 150 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: badge.showLabel && badge.label !== "" ? 6 : 0

        Text {
            transform: Translate { y: badge.iconVerticalOffset }
            text: badge.icon
            // The icon assumes the accent color, giving a subtle pop to the bar
            color: badge.accentColor
            font.family: badge.fontFamily
            font.pixelSize: badge.iconSize
            font.bold: true
            visible: badge.icon !== ""
            opacity: mouseArea.containsMouse ? 1.0 : 0.9
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        Text {
            transform: Translate { y: badge.labelVerticalOffset }
            text: badge.label
            // The label is clean and white, easy to read
            color: mouseArea.containsMouse ? "#ffffff" : "#cdd6f4"
            font.family: badge.fontFamily
            font.pixelSize: badge.labelSize
            font.bold: true
            visible: badge.showLabel && badge.label !== ""
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: badge.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) badge.rightClicked()
            else badge.clicked()
        }
        onWheel: (wheel) => {
            if (wheel.angleDelta.y > 0) badge.scrollUp()
            else if (wheel.angleDelta.y < 0) badge.scrollDown()
        }
    }

    Timer {
        id: hoverTimer
        interval: 300
        running: mouseArea.containsMouse
        onTriggered: badge.showTooltip = true
    }
    
    property bool isHovered: mouseArea.containsMouse
    onIsHoveredChanged: {
        if (!isHovered) badge.showTooltip = false;
    }

    // Floating, detached tooltip below the bar
    PopupWindow {
        id: tooltipWindow
        visible: badge.showTooltip && badge.tooltipText !== ""
        anchor.item: badge
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 8
        color: "transparent"

        implicitWidth: tooltipRect.width
        implicitHeight: tooltipRect.height

        Rectangle {
            id: tooltipRect
            width: tooltipTextElement.implicitWidth + 20
            height: tooltipTextElement.implicitHeight + 12
            color: Qt.rgba(30/255, 30/255, 46/255, 0.98) // Mocha base
            border.color: Qt.rgba(255/255, 255/255, 255/255, 0.1)
            border.width: 1
            radius: 8

            Text {
                id: tooltipTextElement
                anchors.centerIn: parent
                text: badge.tooltipText
                color: "#cdd6f4"
                font.family: badge.fontFamily
                font.pixelSize: 14
                font.bold: true
            }
        }
    }
}
