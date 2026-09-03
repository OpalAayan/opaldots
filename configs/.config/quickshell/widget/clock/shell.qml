import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Bottom
    exclusiveZone: 0

    // ── Geometry defaults (overwritten synchronously when geometry.json loads) ──
    property int geoX: 650
    property int geoY: 15
    property int geoW: 800
    property int geoH: 180

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.geoY
        left: root.geoX
    }

    implicitWidth: root.geoW
    implicitHeight: root.geoH
    color: "transparent"

    FileView {
        id: geometryFile
        path: Qt.resolvedUrl("geometry.json").toString().replace(/^file:\/\//, "")
        blockLoading: true
        watchChanges: true

        onFileChanged: reload()

        function reload() {
            try {
                var content = geometryFile.text();
                if (content && content.length > 0) {
                    var geo = JSON.parse(content);
                    if (geo.x !== undefined) root.geoX = geo.x;
                    if (geo.y !== undefined) root.geoY = geo.y;
                    if (geo.width !== undefined) root.geoW = geo.width;
                    if (geo.height !== undefined) root.geoH = geo.height;
                }
            } catch (e) {
                console.warn("clock/shell.qml: failed to parse geometry.json:", e);
            }
        }

        Component.onCompleted: reload()
    }

    ClockContent {
        anchors.fill: parent
    }
}
