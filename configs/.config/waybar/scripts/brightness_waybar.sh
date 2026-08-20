#!/bin/bash

# --- Configuration ---
STEP="3%"
NOTIF_ID=5555
APPNAME="volume_overlay"

# --- Action Handling ---
if [[ "$1" == "up" ]]; then
  brightnessctl set "+$STEP" -q
elif [[ "$1" == "down" ]]; then
  brightnessctl set "$STEP-" -q
fi

# --- Get Current State ---
# Extract percentage
bright=$(brightnessctl -m | awk -F, '{print substr($4, 0, length($4)-1)}')

# --- Icon Logic ---
if [ "$bright" -gt 66 ]; then
  icon="󰃠"
  class="high"
elif [ "$bright" -gt 33 ]; then
  icon="󰃟"
  class="medium"
else
  icon="󰃞"
  class="low"
fi

# --- Notification ---
# Only send notification if we actually changed the brightness (argument present)
if [[ -n "$1" ]]; then
  dunstify -a "$APPNAME" -u low -r "$NOTIF_ID" \
    -h int:value:"$bright" \
    -h string:x-dunst-stack-tag:"brightness" \
    "$icon ${bright}%"
fi

# --- Waybar Output ---
tooltip="Brightness: ${bright}%"
echo "{\"text\": \"$icon ${bright}%\", \"tooltip\": \"$tooltip\", \"class\": \"$class\", \"percentage\": $bright}"
