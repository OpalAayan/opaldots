/**
 * @file ClockContent.qml
 * @brief Reusable Visual Content Component for Clock Widget
 *
 * This component encapsulates the visual rendering of the clock widget. It is
 * shared identically between `shell.qml` (layer-shell mode) and `edit.qml` (edit mode).
 *
 * Component Architecture & Design Decisions:
 * - Reusability: By separating visual presentation into this component, both layer
 *   and edit modes render exactly the same typography, layout, and visual effects.
 * - Dynamic Font Scaling: Exposes a `fontScale` property (default `1.0`) that
 *   proportionally scales all font pixel sizes, letter spacing, and layout offsets:
 *     - Day name: base font size 64px, letter-spacing 30px
 *     - Time, Date, Separator: base font size 25px, letter-spacing 2px
 *     - Horizontal/vertical offsets scale dynamically with `root.fontScale`
 * - Design Pattern for New Widgets:
 *   To create a new desktop widget, follow this pattern: implement a dedicated
 *   `<Name>Content.qml` component with a `fontScale` property that scales all text
 *   and spacing relative to its base dimensions, then instantiate it inside both
 *   `shell.qml` and `edit.qml`.
 * - Typography & Fonts:
 *     - Day name: "Anurati" (modern geometric uppercase font)
 *     - Time / Date / Separator: "FiraCode Nerd Font" (monospace, bold)
 * - Visual Depth & Drop Shadow:
 *   Every text element utilizes QtQuick.Effects `MultiEffect` with smooth drop
 *   shadows (blur 0.5, offset 3,3) for contrast and readability against wallpapers.
 */

import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root
    anchors.fill: parent

    // ── Font scaling multiplier (default 1.0) ──
    property real fontScale: 1.0

    SystemClock {
        id: sysTime
        precision: SystemClock.Seconds
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Math.round(8 * root.fontScale)

        // --- THE DAY ---
        Text {
            id: dayText
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(sysTime.date, "dddd").toUpperCase()
            font.family: "Anurati"
            font.pixelSize: Math.max(12, Math.round(64 * root.fontScale))
            font.letterSpacing: Math.round(30 * root.fontScale)
            color: "#ffffff"

            // Fixes the 14-21px leftward skew caused by Anurati's trailing spacing
            transform: Translate {
                x: Math.round(dayText.font.letterSpacing / 2)
            }

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
            id: dateText
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Math.round(10 * root.fontScale)

            text: Qt.formatDateTime(sysTime.date, "dd MMMM, yyyy").toUpperCase()
            font {
                family: "FiraCode Nerd Font"
                pixelSize: Math.max(8, Math.round(22 * root.fontScale))
                letterSpacing: Math.round(3 * root.fontScale)
                bold: true
            }
            color: '#ffffff'

            transform: Translate {
                x: Math.round(dateText.font.letterSpacing / 2)
            }

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
            id: timeText
            Layout.alignment: Qt.AlignHCenter

            text: "- " + Qt.formatDateTime(sysTime.date, "hh:mm") + " -"
            font {
                family: "FiraCode Nerd Font"
                pixelSize: Math.max(8, Math.round(20 * root.fontScale))
                letterSpacing: Math.round(3 * root.fontScale)
                bold: true
            }
            color: '#ffffff'

            transform: Translate {
                x: Math.round(timeText.font.letterSpacing / 2)
            }

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
