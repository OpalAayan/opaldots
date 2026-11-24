/**
 * @file shell.qml
 * @brief Quickshell Layer-Shell Mode Entry Point for Clock Widget
 *
 * This component runs the desktop clock in standard LAYER-SHELL mode as a
 * persistent background overlay.
 *
 * Key Architecture Details:
 * - Window Type: Quickshell PanelWindow configured with `WlrLayershell.layer: WlrLayer.Bottom`,
 *   rendering it directly above the wallpaper but beneath all regular desktop windows.
 * - Exclusive Zone: Set to 0 (`exclusiveZone: 0`) so the widget does not reserve panel
 *   space or push/resize other windows or tiled tiles in Hyprland.
 * - Coordinate Positioning: Positioned using `anchors.top: true` and `anchors.left: true`
 *   with `margins { top: root.geoY; left: root.geoX }`. These margins are calculated
 *   relative to the post-reserved monitor area (i.e. AFTER subtracting Waybar's top
 *   exclusive zone and monitor origin offsets).
 * - Configuration Loading: Geometry and scaling are loaded dynamically from `geometry.json`
 *   via Quickshell's `FileView`.
 *   CRITICAL API NOTE (Quickshell 0.3.1): `FileView` provides `.text()` as a METHOD,
 *   not a property. Accessing `geometryFile.text` as a property returns undefined or causes
 *   silent binding failures. Always invoke `geometryFile.text()`.
 * - Fallback Defaults: Initial values (geoX: 650, geoY: 15, geoW: 800, geoH: 180,
 *   geoScale: 1.0) provide safe fallback coordinates if geometry.json fails to load or parse.
 */

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
    property real geoScale: 1.0

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
                    if (geo.scale !== undefined) root.geoScale = geo.scale;
                }
            } catch (e) {
                console.warn("clock/shell.qml: failed to parse geometry.json:", e);
            }
        }

        Component.onCompleted: reload()
    }

    ClockContent {
        anchors.fill: parent
        fontScale: root.geoScale
    }
}
