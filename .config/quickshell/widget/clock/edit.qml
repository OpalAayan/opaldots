/**
 * @file edit.qml
 * @brief Quickshell Edit-Mode Entry Point for Clock Widget
 *
 * This component runs the clock widget in EDIT MODE as an interactive,
 * floating Wayland window managed by Hyprland.
 *
 * Key Architecture Details:
 * - Window Type: Standard QtQuick `Window` (not a layer-shell PanelWindow).
 * - Window Rule Matching: Window title is explicitly set to `WidgetEdit_Clock`.
 *   This matches the Hyprland rule in `windowrules.lua` (`^(WidgetEdit_.*)$`),
 *   which automatically floats the window, pins it across workspaces, and
 *   draws a distinctive Catppuccin Mauve / Flamingo border.
 * - Frameless Appearance: Uses `flags: Qt.FramelessWindowHint` to strip all
 *   titlebars and native window decorations, ensuring the preview looks
 *   identical to its layer-shell counterpart.
 * - Interactive Manipulation: Moving and resizing are handled natively by
 *   Hyprland using `SUPER + Left-Click` (drag to move) and `SUPER + Right-Click`
 *   (drag to resize).
 * - Position Persistence: When the user saves their changes, `save-edit.sh`
 *   queries Hyprland IPC via `hyprctl clients -j`, captures this window's
 *   live position and dimensions, converts them to layer-relative margins,
 *   and writes them to `geometry.json`.
 * - Visual Feedback: A translucent mauve-tinted Rectangle overlay (`#20cba6f7`)
 *   provides immediate visual feedback that the widget is in edit mode.
 */

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

    // ── Font scaling factor (loaded from geometry.json) ──
    property real widgetScale: 1.0

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
                    if (geo.width !== undefined) editWindow.width = geo.width;
                    if (geo.height !== undefined) editWindow.height = geo.height;
                    if (geo.scale !== undefined) editWindow.widgetScale = geo.scale;
                }
            } catch (e) {
                console.warn("clock/edit.qml: failed to parse geometry.json:", e);
            }
        }

        Component.onCompleted: reload()
    }

    // ── Visual bounding box for edit mode ──
    Rectangle {
        anchors.fill: parent
        color: "#20cba6f7"       // Catppuccin Mauve at ~12% opacity
        border.color: "#cba6f7"  // Catppuccin Mauve
        border.width: 2
        radius: 6

        // ── Widget Content with reactive font scaling ──
        ClockContent {
            anchors.fill: parent
            fontScale: editWindow.widgetScale
        }
    }
}
