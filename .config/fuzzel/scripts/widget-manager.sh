#!/usr/bin/env bash
# widget-manager.sh — Fuzzel-based state machine for managing Quickshell widgets.
set -euo pipefail

WIDGET_DIR="$HOME/.config/quickshell/widget/clock"
SCRIPTS="$WIDGET_DIR/scripts"
GEO_FILE="$WIDGET_DIR/geometry.json"

# ── Helper: run fuzzel with custom prompt ──
fuzzel_menu() {
    local prompt="${1:-  Widgets: }"
    shift
    printf '%s\n' "$@" | fuzzel --dmenu --prompt "$prompt"
}

# ── Dedicated Scale Submenu ──
scale_submenu() {
    while true; do
        local current_scale
        current_scale=$(jq -r '.scale // 1.0' "$GEO_FILE" 2>/dev/null || echo "1.0")
        local scale_pct
        scale_pct=$(python3 -c "print(int(round(float('$current_scale') * 100)))")

        local scale_choice
        scale_choice=$(
            fuzzel_menu "󰭍  Scale (${scale_pct}%): " \
                "󰘖  Increase Size (+10%)" \
                "󰘕  Decrease Size (-10%)" \
                "󰐗  Fine Tune (+1%)" \
                "󰍶  Fine Tune (-1%)" \
                "  Reset to 100%" \
                "󰁍  Back"
        ) || break

        case "$scale_choice" in
        *"Increase Size"*)
            "$SCRIPTS/adjust-scale.sh" "+0.10"
            ;;
        *"Decrease Size"*)
            "$SCRIPTS/adjust-scale.sh" "-0.10"
            ;;
        *"Fine Tune (+1%)"*)
            "$SCRIPTS/adjust-scale.sh" "+0.01"
            ;;
        *"Fine Tune (-1%)"*)
            "$SCRIPTS/adjust-scale.sh" "-0.01"
            ;;
        *"Reset to 100%"*)
            "$SCRIPTS/adjust-scale.sh" "reset"
            ;;
        *"Back"*)
            break
            ;;
        esac
    done
}

# ── Check if any widget is currently in edit mode ──
edit_running=false
if hyprctl clients -j 2>/dev/null | jq -e '.[] | select(.title == "WidgetEdit_Clock")' >/dev/null 2>&1; then
    edit_running=true
fi

if [[ "$edit_running" == "true" ]]; then
    # ── Edit mode is active ──
    while true; do
        current_scale=$(jq -r '.scale // 1.0' "$GEO_FILE" 2>/dev/null || echo "1.0")
        scale_pct=$(python3 -c "print(int(round(float('$current_scale') * 100)))")

        choice=$(
            fuzzel_menu "󰍜  Edit Mode: " \
                "󰆓  Save & Apply" \
                "󰅖  Discard Changes" \
                "󰁌  Scale Font Size [${scale_pct}%]"
        ) || exit 0

        case "$choice" in
        *"Save & Apply"*)
            exec "$SCRIPTS/save-edit.sh"
            ;;
        *"Discard Changes"*)
            exec "$SCRIPTS/start-layer.sh"
            ;;
        *"Scale Font Size"*)
            scale_submenu
            ;;
        esac
    done
else
    # ── Normal mode — show widget list ──
    widget=$(
        fuzzel_menu "󰍜  Widgets: " \
            "󰥔  Clock"
    ) || exit 0

    case "$widget" in
    *"Clock"*)
        current_scale=$(jq -r '.scale // 1.0' "$GEO_FILE" 2>/dev/null || echo "1.0")
        scale_pct=$(python3 -c "print(int(round(float('$current_scale') * 100)))")

        # ── Show actions for the Clock widget ──
        action=$(
            fuzzel_menu "󰥔  Clock: " \
                "󰁁  Resize & Move" \
                "󰵉  Scale Font Size [${scale_pct}%]" \
                "󰑐  Reload" \
                "󰓛  Stop" \
                "󰐊  Start"
        ) || exit 0

        case "$action" in
        *"Resize & Move"*)
            exec "$SCRIPTS/start-edit.sh"
            ;;
        *"Scale Font Size"*)
            scale_submenu
            ;;
        *"Reload"*)
            exec "$SCRIPTS/start-layer.sh"
            ;;
        *"Stop"*)
            pkill -f "clock/(shell|edit)\.qml" 2>/dev/null || true
            pkill -f "widget/clock" 2>/dev/null || true
            notify-send -a "Widget Manager" -i preferences-desktop-theme "Clock widget stopped" -t 2000
            ;;
        *"Start"*)
            exec "$SCRIPTS/start-layer.sh"
            ;;
        esac
        ;;
    esac
fi
