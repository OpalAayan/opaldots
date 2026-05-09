#!/bin/bash

# Smart Float Script for Hyprland
# Purpose: Intelligently toggle floating windows with custom sizes
# Dependencies: hyprctl (built-in), jq (install with: sudo pacman -S jq)
# Author: Hyprland Smart Float System Vaxry
# Version: 1.7

# Configuration file path
CONFIG_FILE="$HOME/.config/hypr/float_sizes.conf"

# Function to print debug messages (can be enabled for troubleshooting)
debug() {
  # Uncomment the line below to enable debug output
  # echo "[DEBUG] $1" >&2
  :
}

# Function to get the active window's information
get_active_window_info() {
  hyprctl activewindow -j
}

# Function to check if a command exists
check_dependency() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: $1 is not installed. Please install it first." >&2
    echo "For Arch-based systems: sudo pacman -S $1" >&2
    exit 1
  fi
}

# Check for required dependencies
check_dependency "hyprctl"
check_dependency "jq"

# Get active window information as JSON
WINDOW_INFO=$(get_active_window_info)

# Check if we got valid window information
if [ -z "$WINDOW_INFO" ] || [ "$WINDOW_INFO" = "null" ]; then
  echo "Error: No active window found" >&2
  exit 1
fi

# Extract window properties using jq
WINDOW_CLASS=$(echo "$WINDOW_INFO" | jq -r '.class // empty')
IS_FLOATING=$(echo "$WINDOW_INFO" | jq -r '.floating // false')

debug "Window Class: $WINDOW_CLASS"
debug "Is Floating: $IS_FLOATING"

# Check if window class was successfully retrieved
if [ -z "$WINDOW_CLASS" ]; then
  echo "Error: Could not determine window class" >&2
  exit 1
fi

# STEP 1: Check if the window is already floating
if [ "$IS_FLOATING" = "true" ]; then
  debug "Window is floating, toggling back to tiled"
  # Window is floating, so toggle it back to tiled mode
  hyprctl dispatch togglefloating
  exit 0
fi

# STEP 2: Window is tiled, so we need to float it
debug "Window is tiled, checking for custom size"

# Initialize variables for custom size
CUSTOM_SIZE=""

# Check if configuration file exists and is readable
if [ -f "$CONFIG_FILE" ] && [ -r "$CONFIG_FILE" ]; then
  debug "Reading configuration file: $CONFIG_FILE"

  # Read the configuration file line by line
  while IFS= read -r line; do
    # Skip empty lines and comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    # Trim whitespace
    line=$(echo "$line" | xargs)

    # Check if the line starts with our window class
    if [[ "$line" =~ ^${WINDOW_CLASS}= ]]; then
      # Extract the size value (everything after the first =)
      CUSTOM_SIZE="${line#*=}"
      debug "Found custom size for $WINDOW_CLASS: $CUSTOM_SIZE"
      break
    fi
  done <"$CONFIG_FILE"
else
  debug "Configuration file not found or not readable: $CONFIG_FILE"
fi

# STEP 3: Apply floating with or without custom size
if [ -n "$CUSTOM_SIZE" ]; then
  # Custom size found - parse WIDTH and HEIGHT
  if [[ "$CUSTOM_SIZE" =~ ^([0-9]+)x([0-9]+)$ ]]; then
    WIDTH="${BASH_REMATCH[1]}"
    HEIGHT="${BASH_REMATCH[2]}"

    debug "Applying custom size: ${WIDTH}x${HEIGHT}"

    # Execute the three commands in sequence
    hyprctl dispatch togglefloating
    hyprctl dispatch resizeactive exact "$WIDTH" "$HEIGHT"
    hyprctl dispatch centerwindow

    echo "Floated $WINDOW_CLASS with custom size: ${WIDTH}x${HEIGHT}"
  else
    echo "Warning: Invalid size format for $WINDOW_CLASS: $CUSTOM_SIZE" >&2
    echo "Expected format: WIDTHxHEIGHT (e.g., 1200x700)" >&2
    # Fall back to default floating
    hyprctl dispatch togglefloating
  fi
else
  # No custom size found - use default Hyprland floating behavior
  debug "No custom size found, using default floating"
  hyprctl dispatch togglefloating
  echo "Floated $WINDOW_CLASS with default size"
fi

exit 0

