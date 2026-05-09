#!/bin/bash

# 1. Pick the color
color=$(hyprpicker)

# 2. Check if a color was picked (user didn't press ESC)
if [[ -n "$color" ]]; then
    # Copy to clipboard
    echo -n "$color" | wl-copy

    # Generate a CIRCULAR icon
    # -size 48x48 xc:none  -> Create a 48x48 transparent canvas
    # -fill "$color"       -> Set the fill color to the picked hex code
    # -draw "circle..."    -> Draw a circle from center (24,24) to edge (47,24)
    convert -size 48x48 xc:none -fill "$color" -draw "circle 24,24 47,24" /tmp/color_icon.png

    # Send the notification with the new icon
    notify-send -t 2000 -i /tmp/color_icon.png "Copied" "$color"
fi