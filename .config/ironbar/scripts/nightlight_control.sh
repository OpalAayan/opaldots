#!/bin/bash

# --- CONFIGURATION ---
STEP=100
MIN_TEMP=2500
MAX_TEMP=6500
DEFAULT_ON_TEMP=4500
# --- END CONFIGURATION ---

STATE_FILE="/tmp/gammarelay_last_temp"
APPNAME="nightlight_overlay"
NOTIF_ID=9992

get_current_temp() {
    temp=$(busctl --user get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature 2>/dev/null | awk '{print $2}')
    if [[ "$temp" =~ ^[0-9]+$ ]]; then
        echo "$temp"
    else
        echo "$MAX_TEMP"
    fi
}

set_temp() {
    local target=${1%.*}
    if [[ "$target" -lt "$MIN_TEMP" ]]; then target=$MIN_TEMP; fi
    if [[ "$target" -gt "$MAX_TEMP" ]]; then target=$MAX_TEMP; fi
    busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q "$target" 2>/dev/null
}

send_notification() {
    local temp=$1
    PERCENT=$((((temp - MIN_TEMP) * 100) / (MAX_TEMP - MIN_TEMP)))

    if [ "$temp" -ge 5000 ]; then
        icon="󰖙"
    elif [ "$temp" -ge 4000 ]; then
        icon="󰖚"
    else
        icon="󰖔"
    fi

    if [ "$temp" -ge "$MAX_TEMP" ]; then
        dunstify -a "$APPNAME" -u low -r "$NOTIF_ID" \
            -h int:value:100 \
            -h string:x-dunst-stack-tag:"nightlight" \
            "󰖙 Off (6500K)" 2>/dev/null
    else
        dunstify -a "$APPNAME" -u low -r "$NOTIF_ID" \
            -h int:value:"$PERCENT" \
            -h string:x-dunst-stack-tag:"nightlight" \
            "$icon ${temp}K" 2>/dev/null
    fi
}

case "$1" in
is-active)
    current=$(get_current_temp)
    [ "$current" -lt "$MAX_TEMP" ]
    exit $?
    ;;

is-inactive)
    current=$(get_current_temp)
    [ "$current" -ge "$MAX_TEMP" ]
    exit $?
    ;;

status)
    current=$(get_current_temp)
    if [ "$current" -ge "$MAX_TEMP" ]; then
        echo "󰖔"
    else
        echo "󰖚 ${current}K"
    fi
    ;;

subtitle)
    current=$(get_current_temp)
    if [ "$current" -ge "$MAX_TEMP" ]; then
        echo "Off • 6500K"
    else
        echo "On • ${current}K"
    fi
    ;;

temp)
    get_current_temp
    ;;

tooltip)
    current=$(get_current_temp)
    if [ "$current" -ge "$MAX_TEMP" ]; then
        echo "Off (6500K)"
    else
        echo "Active (${current}K)"
    fi
    ;;

set)
    if [[ -n "$2" ]]; then
        set_temp "$2"
    fi
    ;;

increase)
    current=$(get_current_temp)
    new=$((current + STEP))
    if [ "$new" -ge "$MAX_TEMP" ]; then new=$MAX_TEMP; fi
    set_temp "$new"
    send_notification "$new"
    ;;

decrease)
    current=$(get_current_temp)
    new=$((current - STEP))
    if [ "$new" -lt "$MIN_TEMP" ]; then new=$MIN_TEMP; fi
    set_temp "$new"
    send_notification "$new"
    ;;

toggle|*)
    current=$(get_current_temp)
    if [ "$current" -ge "$MAX_TEMP" ]; then
        if [ -f "$STATE_FILE" ]; then
            target=$(cat "$STATE_FILE")
        else
            target=$DEFAULT_ON_TEMP
        fi
        if [ "$target" -ge "$MAX_TEMP" ]; then target=$DEFAULT_ON_TEMP; fi
        set_temp "$target"
        send_notification "$target"
    else
        echo "$current" >"$STATE_FILE"
        set_temp "$MAX_TEMP"
        send_notification "$MAX_TEMP"
    fi
    ;;
esac
