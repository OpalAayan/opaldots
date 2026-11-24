#!/bin/bash

# --- Configuration ---
STEP="3%"
NOTIF_ID=5555
APPNAME="volume_overlay"

# --- Action Handling ---
if [[ "$1" == "up" ]]; then
  brightnessctl set "+$STEP" -q 2>/dev/null
elif [[ "$1" == "down" ]]; then
  brightnessctl set "$STEP-" -q 2>/dev/null
elif [[ "$1" == "set" && -n "$2" ]]; then
  val="${2%.*}"
  (( val < 5 )) && val=5
  (( val > 100 )) && val=100
  brightnessctl set "${val}%" -q 2>/dev/null
fi

# --- Get Current State ---
bright=$(brightnessctl -m 2>/dev/null | awk -F, '{print substr($4, 0, length($4)-1)}')
if [[ ! "$bright" =~ ^[0-9]+$ ]]; then
  bright=100
fi

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
if [[ "$1" == "up" || "$1" == "down" ]]; then
  dunstify -a "$APPNAME" -u low -r "$NOTIF_ID" \
    -h int:value:"$bright" \
    -h string:x-dunst-stack-tag:"brightness" \
    "$icon ${bright}%" 2>/dev/null
fi

# --- Output Mode ---
case "$1" in
  percent)
    echo "$bright"
    ;;
  icon)
    echo "$icon"
    ;;
  get|status)
    echo "$icon ${bright}%"
    ;;
  up|down|set)
    ;;
  json)
    tooltip="Brightness: ${bright}%"
    echo "{\"text\": \"$icon ${bright}%\", \"tooltip\": \"$tooltip\", \"class\": \"$class\", \"percentage\": $bright}"
    ;;
  *)
    echo "$icon ${bright}%"
    ;;
esac
