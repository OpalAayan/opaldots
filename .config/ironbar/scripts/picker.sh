#!/bin/bash

# Small delay so popup can close cleanly before hyprpicker grabs the screen
sleep 0.15

# 1. Pick the color
color=$(hyprpicker 2>/dev/null)

# 2. Check if a color was picked (user didn't press ESC)
if [[ -n "$color" ]]; then
    # Copy to clipboard
    echo -n "$color" | wl-copy

    # Generate a CIRCULAR icon (supports ImageMagick v7 magick or v6 convert)
    if command -v magick >/dev/null 2>&1; then
        magick -size 48x48 xc:none -fill "$color" -draw "circle 24,24 47,24" /tmp/color_icon.png 2>/dev/null
    elif command -v convert >/dev/null 2>&1; then
        convert -size 48x48 xc:none -fill "$color" -draw "circle 24,24 47,24" /tmp/color_icon.png 2>/dev/null
    fi

    # Send the notification with the new icon
    notify-send -t 2000 -i /tmp/color_icon.png "Copied" "$color"
fi
