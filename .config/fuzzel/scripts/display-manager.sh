#!/usr/bin/env bash
# display-manager.sh — Simple Fuzzel GUI for toggle-display.sh

set -euo pipefail

TOGGLE_SCRIPT="$HOME/.config/hypr/scripts/toggle-display.sh"
MODE_FILE="$HOME/.config/hypr/.display_mode"

fuzzel_menu() {
    local prompt="$1"
    local lines="$2"
    shift 2
    printf '%s\n' "$@" | fuzzel \
        --dmenu \
        --prompt "$prompt" \
        --lines "$lines" \
        --width 42
}

mirror_submenu() {
    local choice
    choice=$(
        fuzzel_menu "󰍺  Mirror: " 3 \
            "󰌢  Laptop → External (LVDS-1 → DP-3)" \
            "󰍹  External → Laptop (DP-3 → LVDS-1)" \
            "󰁍  Back"
    ) || return 0

    case "$choice" in
        *"Laptop → External"*)
            exec "$TOGGLE_SCRIPT" -m laptop
            ;;
        *"External → Laptop"*)
            exec "$TOGGLE_SCRIPT" -m external
            ;;
    esac
}

while true; do
    saved="dual"
    if [[ -r "$MODE_FILE" ]]; then
        saved="$(tr -d '[:space:]' <"$MODE_FILE" || echo "dual")"
    fi

    choice=$(
        fuzzel_menu "󰍹  Display [$saved]: " 6 \
            "󰍹  External Only (DP-3 • WS 1–5)" \
            "󰌢  Laptop Only (LVDS-1 • WS 1–5)" \
            "󰶐  Dual Display (LVDS-1 [1–5] + DP-3 [6–10])" \
            "󰍺  Mirror Display ▸" \
            "󰁯  Failsafe Reset" \
            "󰋼  Status Notification"
    ) || exit 0

    case "$choice" in
        *"External Only"*)
            exec "$TOGGLE_SCRIPT" -e
            ;;
        *"Laptop Only"*)
            exec "$TOGGLE_SCRIPT" -l
            ;;
        *"Dual Display"*)
            exec "$TOGGLE_SCRIPT" -d
            ;;
        *"Mirror Display"*)
            mirror_submenu
            ;;
        *"Failsafe Reset"*)
            exec "$TOGGLE_SCRIPT" -f
            ;;
        *"Status Notification"*)
            status_out="$("$TOGGLE_SCRIPT" -s)"
            notify-send -t 4000 "Display Status" "$status_out"
            exit 0
            ;;
    esac
done
