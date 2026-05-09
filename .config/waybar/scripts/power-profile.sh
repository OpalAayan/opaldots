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
    
    # Send the notification with the Nerd Font icon and text in the body
    notify-send -t 2000 -h string:x-canonical-private-synchronous:powerprofile \
    "${nerd_icon} ${text_body}" \
    -i "$system_icon"
}

# Handle script arguments
case "$1" in
    "get")
        CURRENT_PROFILE=$(powerprofilesctl get)
        local icon=""
        local text=""
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
                icon="?"
                text="Unknown"
                ;;
        esac
        # Output JSON for Waybar
        printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$icon" "$text" "$CURRENT_PROFILE"
        ;;

    "cycle")
        CURRENT_PROFILE=$(powerprofilesctl get)
        local next_profile=""
        case "$CURRENT_PROFILE" in
            "performance")
                next_profile="balanced"
                ;;
            "balanced")
                next_profile="power-saver"
                ;;
            "power-saver")
                next_profile="performance" # Wrap around
                ;;
            *)
                next_profile="balanced" # Default fallback
                ;;
        esac
        powerprofilesctl set "$next_profile"
        send_notification "$next_profile"
        ;;
esac