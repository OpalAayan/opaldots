#!/bin/bash

# --- CONFIGURATION ---
STEP=100
MIN_TEMP=2500
MAX_TEMP=6500
DEFAULT_ON_TEMP=4500
# --- END CONFIGURATION ---

# File to store the "last known active temperature" (for toggling back on)
STATE_FILE="/tmp/gammarelay_last_temp"
APPNAME="nightlight_overlay"
NOTIF_ID=9992

# Function to get current temperature from wl-gammarelay-rs via Busctl
get_current_temp() {
  # Get the property, extract the integer value
  temp=$(busctl --user get-property rs.wl-gammarelay / rs.wl.gammarelay Temperature | awk '{print $2}')
  if [[ "$temp" =~ ^[0-9]+$ ]]; then
    echo "$temp"
  else
    echo "$MAX_TEMP" # Default to max (off) if query fails
  fi
}

# Function to set temperature
set_temp() {
  local target=$1
  busctl --user set-property rs.wl-gammarelay / rs.wl.gammarelay Temperature q "$target"
}

# Function to send the notification
send_notification() {
  local temp=$1

  # Calculate Percentage (6500K = 100%, 2500K = 0%)
  PERCENT=$((((temp - MIN_TEMP) * 100) / (MAX_TEMP - MIN_TEMP)))

  # Icon Logic
  if [ "$temp" -ge 5000 ]; then
    icon="󰖙" # Day / Sun
  elif [ "$temp" -ge 4000 ]; then
    icon="" # Sunset
  else
    icon="󰖔" # Night / Moon
  fi

  # Custom message for "Off" state (Max Temp)
  if [ "$temp" -ge "$MAX_TEMP" ]; then
    dunstify -a "$APPNAME" -u low -r "$NOTIF_ID" \
      -h int:value:100 \
      -h string:x-dunst-stack-tag:"nightlight" \
      "󰖙 Off (6500K)"
  else
    dunstify -a "$APPNAME" -u low -r "$NOTIF_ID" \
      -h int:value:"$PERCENT" \
      -h string:x-dunst-stack-tag:"nightlight" \
      "$icon ${temp}K"
  fi
}

# --- MAIN LOGIC ---

case "$1" in
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

*)
  # TOGGLE LOGIC
  current=$(get_current_temp)

  # If we are effectively "Off" (at Max Temp or higher), turn ON
  if [ "$current" -ge "$MAX_TEMP" ]; then
    # Try to read last used temp, otherwise use default
    if [ -f "$STATE_FILE" ]; then
      target=$(cat "$STATE_FILE")
    else
      target=$DEFAULT_ON_TEMP
    fi

    # Safety check to ensure we don't toggle "On" to 6500K
    if [ "$target" -ge "$MAX_TEMP" ]; then target=$DEFAULT_ON_TEMP; fi

    set_temp "$target"
    send_notification "$target"

  else
    # We are currently ON (Warmer), so turn OFF
    # Save current temp so we can restore it later
    echo "$current" >"$STATE_FILE"

    set_temp "$MAX_TEMP"
    send_notification "$MAX_TEMP"
  fi
  ;;
esac

