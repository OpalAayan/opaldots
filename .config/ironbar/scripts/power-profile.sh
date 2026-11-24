#!/bin/bash

# Function to send notification
send_notification() {
    local new_profile=$1
    local system_icon=""
    local nerd_icon=""
    local text_body=""

    case "$new_profile" in
        "power-saver")
            system_icon="power-profile-power-saver-symbolic"
            nerd_icon="󰌪"
            text_body="Power Saver"
            ;;
        "balanced")
            system_icon="power-profile-balanced-symbolic"
            nerd_icon=""
            text_body="Balanced"
            ;;
        "performance")
            system_icon="power-profile-performance-symbolic"
            nerd_icon="󰓅"
            text_body="Performance"
            ;;
    esac

    notify-send -t 2000 -h string:x-canonical-private-synchronous:powerprofile \
        "${nerd_icon} ${text_body}" \
        -i "$system_icon"
}

get_profile() {
    if command -v powerprofilesctl >/dev/null 2>&1; then
        powerprofilesctl get 2>/dev/null || echo "balanced"
    else
        echo "balanced"
    fi
}

case "$1" in
    "get")
        CURRENT_PROFILE=$(get_profile)
        icon=""
        text=""
        case "$CURRENT_PROFILE" in
            "power-saver")
                icon="󰌪"
                text="Power Saver"
                ;;
            "balanced")
                icon=""
                text="Balanced"
                ;;
            "performance")
                icon="󰓅"
                text="Performance"
                ;;
            *)
                icon=""
                text="Balanced"
                ;;
        esac
        printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$icon" "$text" "$CURRENT_PROFILE"
        ;;

    "icon")
        CURRENT_PROFILE=$(get_profile)
        case "$CURRENT_PROFILE" in
            "power-saver") echo "󰌪" ;;
            "performance") echo "󰓅" ;;
            *) echo "" ;;
        esac
        ;;

    "subtitle")
        CURRENT_PROFILE=$(get_profile)
        case "$CURRENT_PROFILE" in
            "power-saver") echo "Power Saver" ;;
            "performance") echo "Performance" ;;
            *) echo "Balanced" ;;
        esac
        ;;

    "label"|"")
        CURRENT_PROFILE=$(get_profile)
        case "$CURRENT_PROFILE" in
            "power-saver")
                echo "󰌪  Power Saver"
                ;;
            "balanced")
                echo "  Balanced"
                ;;
            "performance")
                echo "󰓅  Performance"
                ;;
            *)
                echo "  Balanced"
                ;;
        esac
        ;;

    "cycle")
        CURRENT_PROFILE=$(get_profile)
        next_profile=""
        case "$CURRENT_PROFILE" in
            "performance")
                next_profile="balanced"
                ;;
            "balanced")
                next_profile="power-saver"
                ;;
            "power-saver")
                next_profile="performance"
                ;;
            *)
                next_profile="balanced"
                ;;
        esac
        if command -v powerprofilesctl >/dev/null 2>&1; then
            powerprofilesctl set "$next_profile" 2>/dev/null
        fi
        send_notification "$next_profile"
        ;;
esac
