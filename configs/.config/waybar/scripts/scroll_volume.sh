#!/bin/bash

# ═══════════════════════════════════════════════════════════════
#  🔊 Scroll Volume Control - Throttled & Optimized
#  Usage: ./scroll_volume.sh [up|down]
# ═══════════════════════════════════════════════════════════════

action=$1
[[ -z "$action" || ! "$action" =~ ^(up|down)$ ]] && exit 1

APPNAME="volume_overlay"
NOTIF_ID=9991
STEP=3
MAX_VOL=275

# --- Simple Throttle: Skip if called too recently ---
THROTTLE_FILE="/tmp/.vol_throttle"
THROTTLE_MS=30  # Minimum ms between wpctl calls

now_ms=$(($(date +%s%N) / 1000000))
if [[ -f "$THROTTLE_FILE" ]]; then
    last_ms=$(<"$THROTTLE_FILE")
    ((now_ms - last_ms < THROTTLE_MS)) && exit 0
fi
echo "$now_ms" > "$THROTTLE_FILE"

# --- Get volume ONCE ---
read -r _ vol_float muted < <(wpctl get-volume @DEFAULT_AUDIO_SINK@)
vol_str="${vol_float//./}"
vol=$((10#${vol_str:-0}))

# --- Handle Volume ---
case $action in
    up)
        wpctl set-volume -l 2.75 @DEFAULT_AUDIO_SINK@ ${STEP}%+
        vol=$((vol + STEP))
        ((vol > MAX_VOL)) && vol=$MAX_VOL
        ;;
    down)
        if ((vol > 100)); then
            wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
            vol=100
        else
            wpctl set-volume @DEFAULT_AUDIO_SINK@ ${STEP}%-
            vol=$((vol - STEP))
            ((vol < 0)) && vol=0
        fi
        ;;
esac

# --- Icons (ORIGINAL - unchanged) ---
if [[ "$muted" == "[MUTED]" ]]; then
    icon=""
    text="Muted"
else
    if [ "$vol" -gt 100 ]; then icon="";
    elif [ "$vol" -eq 100 ]; then icon="";
    elif [ "$vol" -ge 60 ]; then icon="󱑽";
    elif [ "$vol" -ge 42 ]; then icon="";
    elif [ "$vol" -ge 1 ]; then icon="";
    else icon=""; fi
    text="$vol%"
fi

# --- Send Notification ---
dunstify -a "$APPNAME" -u low -r "$NOTIF_ID" \
         -h int:value:"$vol" \
         -h string:x-dunst-stack-tag:"volume" \
         "$icon $text"