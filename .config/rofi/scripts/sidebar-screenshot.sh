#!/bin/bash

# --- Configuration ---
screenshot_dir="$HOME/Pictures/Screenshots"
screenshot_sound="/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"
icon="$HOME/.config/rofi/screenshot/camera.png"

# !!! Ensure this path matches your file !!!
roficonfig="$HOME/.config/rofi/screenshot/screenshot.rasi"

# Create directory if it doesn't exist
[ -d "$screenshot_dir" ] || mkdir -p "$screenshot_dir"

# --- Icons (Nerd Fonts) ---
area_icon="󰆞"   # Crop icon
full_icon="󰹑"   # Monitor icon
record_icon="󰖠" # Recording icon
save_icon="󰆓"   # Save floppy
copy_icon="󰆏"   # Copy clipboard
back_icon="󰶢"   # Back Arrow

# --- Rofi Menu 1: Main Menu ---
options="$area_icon\n$full_icon\n$record_icon"
selected_mode="$(echo -e "$options" | rofi -dmenu -theme "$roficonfig" -p "Screenshot")"

# Exit if nothing selected
[ -z "$selected_mode" ] && exit 0

# --- Logic Implementation ---

# 1. HANDLE "RECORD" (Special Icon Menu)
if [ "$selected_mode" = "$record_icon" ]; then
    # We use 'go-previous' for the icon because we are in Icon-Only mode
    rec_options="GPU-Recorder\0icon\x1f/home/aayanopal/.local/share/icons/McMojave-circle/apps/scalable/GPU.Screen.Recorder.svg\nOBS\0icon\x1fobs\nBack\0icon\x1fgo-previous"
    
    selected_app="$(echo -e "$rec_options" | rofi -dmenu \
        -theme "$roficonfig" \
        -p "Record" \
        -show-icons \
        -theme-str 'listview { lines: 3; } element { padding: 15px; } element-text { enabled: false; } element-icon { enabled: true; size: 50px; margin: 0px; background-color: transparent; vertical-align: 0.5; horizontal-align: 0.5; }')"


    if [[ "$selected_app" == "GPU-Recorder"* ]]; then
        notify-send -t 2000 "Recording" "Launching GPU Screen Recorder..."
        nohup gpu-screen-recorder-gtk >/dev/null 2>&1 & 
    elif [[ "$selected_app" == "OBS"* ]]; then
        notify-send -t 2000 "Recording" "Launching OBS Studio..."
        nohup obs >/dev/null 2>&1 &
    elif [[ "$selected_app" == "Back"* ]]; then
        exec "$0" # Restart script (Go Back)
    fi
    exit 0

# 2. HANDLE SCREENSHOTS (Area & Full)
else
    # Show Save / Copy / Back
    actions="$save_icon\n$copy_icon\n$back_icon"
    selected_action="$(echo -e "$actions" | rofi -dmenu -theme "$roficonfig" -p "Action")"
    
    [ -z "$selected_action" ] && exit 0

    # --- Back Button Logic ---
    if [ "$selected_action" = "$back_icon" ]; then
        exec "$0" # Restart script to go back to main menu
        exit 0
    fi

    # --- Area Logic ---
    if [ "$selected_mode" = "$area_icon" ]; then
        if [ "$selected_action" = "$copy_icon" ]; then
            grim -g "$(slurp)" - | wl-copy && paplay "$screenshot_sound" && notify-send -t 2000 "Screenshot Copied" "Selected area copied to clipboard."
        elif [ "$selected_action" = "$save_icon" ]; then
            file="$screenshot_dir/$(date +'%Y-%m-%d_%H-%M-%S').png"
            grim -g "$(slurp)" "$file" && paplay "$screenshot_sound" && notify-send -t 2000 "Screenshot Saved" "Selected area saved to Hyprland Screenshots."
        fi

    # --- Full Logic ---
    elif [ "$selected_mode" = "$full_icon" ]; then
        sleep 0.5
        if [ "$selected_action" = "$copy_icon" ]; then
            grim - | wl-copy && paplay "$screenshot_sound" && notify-send -t 2000 "Screenshot Copied" "Full screen image copied to clipboard."
        elif [ "$selected_action" = "$save_icon" ]; then
            file="$screenshot_dir/$(date +'%Y-%m-%d_%H-%M-%S').png"
            grim "$file" && paplay "$screenshot_sound" && notify-send -t 2000 "Screenshot Saved" "Full screen image saved to Hyprland Screenshots."
        fi
    fi
fi