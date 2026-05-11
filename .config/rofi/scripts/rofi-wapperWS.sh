#!/bin/bash

# 0. SAFETY DELAY
# This is crucial. It gives Hyprland time to register the keypress
# and hand over input focus to Rofi.
sleep 0.15

# 1. Count open windows
WINDOW_COUNT=$(hyprctl clients -j | jq length)

# Default to 1 if no windows found to prevent errors
if [ -z "$WINDOW_COUNT" ] || [ "$WINDOW_COUNT" -eq 0 ]; then
  WINDOW_COUNT=1
fi

# 2. Geometry calculations
CARD_WIDTH=220
BASE_WIDTH=60
MAX_SCREEN_WIDTH=1800

TOTAL_WIDTH=$(((WINDOW_COUNT * CARD_WIDTH) + BASE_WIDTH))

# Cap width at max screen width
if [ "$TOTAL_WIDTH" -gt "$MAX_SCREEN_WIDTH" ]; then
  TOTAL_WIDTH=$MAX_SCREEN_WIDTH
fi

# 3. Launch Rofi
# -selected-row 1: Highlights the second item (usually the previous window)
# We do NOT pass keybindings here because they are safely in the .rasi file
rofi \
  -show window \
  -theme ~/.config/rofi/window-switcher/window-switcher.rasi \
  -theme-str "window { width: ${TOTAL_WIDTH}px; }" \
  -theme-str "listview { columns: ${WINDOW_COUNT}; }" \
  -selected-row 1

