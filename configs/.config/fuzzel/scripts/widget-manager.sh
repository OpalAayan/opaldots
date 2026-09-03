#!/usr/bin/env bash
# widget-manager.sh — Fuzzel-based state machine for managing Quickshell widgets.
set -euo pipefail

WIDGET_DIR="$HOME/.config/quickshell/widget/clock"
SCRIPTS="$WIDGET_DIR/scripts"

# ── Helper: run fuzzel with a piped menu ──
fuzzel_menu() {
    printf '%s\n' "$@" | fuzzel --dmenu --prompt "󰍜  Widgets: "
}

# ── Check if any widget is currently in edit mode ──
edit_running=false
if hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.title == "WidgetEdit_Clock")' >/dev/null 2>&1; then
    edit_running=true
fi

if [[ "$edit_running" == "true" ]]; then
    # ── Edit mode is active — show save/discard menu ──
    choice=$(
        fuzzel_menu \
            "󰆓  Save & Apply" \
            "󰅖  Discard Changes"
    ) || exit 0

    case "$choice" in
    *"Save & Apply"*)
        exec "$SCRIPTS/save-edit.sh"
        ;;
    *"Discard Changes"*)
        exec "$SCRIPTS/start-layer.sh"
        ;;
    esac
else
    # ── Normal mode — show widget list ──
    widget=$(
        fuzzel_menu \
            "󰥔  Clock"
    ) || exit 0

    case "$widget" in
    *"Clock"*)
        # ── Show actions for the Clock widget ──
        action=$(
            fuzzel_menu \
                "  Resize & Move" \
                "󰑐  Reload" \
                "󰓛  Stop" \
                "󰐊  Start"
        ) || exit 0

        case "$action" in
        *"Resize & Move"*)
            exec "$SCRIPTS/start-edit.sh"
            ;;
        *"Reload"*)
            exec "$SCRIPTS/start-layer.sh"
            ;;
        *"Stop"*)
            pkill -f "clock/(shell|edit)\.qml" 2>/dev/null || true
            pkill -f "widget/clock" 2>/dev/null || true
            notify-send -a "Widget Manager" -i preferences-desktop-theme "Clock widget stopped"
            ;;
        *"Start"*)
            exec "$SCRIPTS/start-layer.sh"
            ;;
        esac
        ;;
    esac
fi
