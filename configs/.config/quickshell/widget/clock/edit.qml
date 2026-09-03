import QtQuick
import QtQuick.Window
import Quickshell.Io

Window {
    id: editWindow

    title: "WidgetEdit_Clock"
    visible: true

    width: 800
    height: 180
    color: "transparent"

    flags: Qt.FramelessWindowHint

    FileView {
        id: geometryFile
        path: Qt.resolvedUrl("geometry.json").toString().replace(/^file:\/\//, "")
        blockLoading: true
        Component.onCompleted: {
            try {
                var content = geometryFile.text();
                if (content && content.length > 0) {
                    var geo = JSON.parse(content);
                    if (geo.width !== undefined) editWindow.width = geo.width;
                    if (geo.height !== undefined) editWindow.height = geo.height;
                }
            } catch (e) {
                console.warn("clock/edit.qml: failed to parse geometry.json:", e);
            }
        }
    }

    // ── Visual bounding box for edit mode ──
    Rectangle {
        anchors.fill: parent
        color: "#20cba6f7"       // Catppuccin Mauve at ~12% opacity
        border.color: "#cba6f7"  // Catppuccin Mauve
        border.width: 2
        radius: 4

        // ── Widget Content ──
        ClockContent {
            anchors.fill: parent
        }
    }
}
