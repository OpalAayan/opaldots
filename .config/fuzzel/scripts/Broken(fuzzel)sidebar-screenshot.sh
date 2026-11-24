#!/bin/bash

# -----------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------

# 1. PATHS
SCREENSHOT_DIR="$HOME/Picture/HyprScreenShot"
[ -d "$SCREENSHOT_DIR" ] || mkdir -p "$SCREENSHOT_DIR"

SOUND_FILE="/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"
FILENAME="$(date +'%y%m%d-%H%M-%S').png"

# 2. VISUALS
# Colors (Dracula/Dark theme)
BG_COLOR="191a21ff"        
FG_COLOR="e0def4ff"        
SEL_COLOR="44475add"       
SEL_TEXT="f8f8f2ff"        
BORDER="bd93f9ff"          

TEXT_FONT="JetBrains Mono Nerd Font:size=20"

# 3. ICONS
ICON_AREA="  Area"
ICON_WIN="  Window"
ICON_FULL="  Full"
ICON_COPY="  Copy"
ICON_SAVE="  Save"

# -----------------------------------------------------
# FUZZEL FUNCTION
# -----------------------------------------------------
run_fuzzel() {
    fuzzel --dmenu \
        --config /dev/null \
        --anchor right \
        --lines 3 \
        --width 10 \
        --x-margin 0 \
        --y-margin 0 \
        --horizontal-pad 15 \
        --vertical-pad 15 \
        --inner-pad 5 \
        --background "$BG_COLOR" \
        --text-color "$FG_COLOR" \
        --selection-color "$SEL_COLOR" \
        --selection-text-color "$SEL_TEXT" \
        --border-width 2 \
        --border-color "$BORDER" \
        --border-radius 0 \
        --prompt "" \
        --font "$TEXT_FONT"
}

play_sound() {
    if [ -f "$SOUND_FILE" ]; then
        paplay "$SOUND_FILE" &
    fi
}

# -----------------------------------------------------
# EXECUTION LOGIC
# -----------------------------------------------------

# STEP 1: Choose Screenshot Mode
MODE=$(echo -e "$ICON_AREA\n$ICON_WIN\n$ICON_FULL" | run_fuzzel)

[ -z "$MODE" ] && exit 0

# STEP 2: Choose Action
ACTION=$(echo -e "$ICON_SAVE\n$ICON_COPY" | run_fuzzel)

[ -z "$ACTION" ] && exit 0

# STEP 3: Handle Screenshot
case "$MODE" in
    "$ICON_AREA")
        if [ "$ACTION" == "$ICON_COPY" ]; then
            hyprshot -m region --clipboard-only --freeze
            notify-send -u low "Screenshot" "Area copied to clipboard"
        elif [ "$ACTION" == "$ICON_SAVE" ]; then
            sleep 0.2
            hyprshot -m region -o "$SCREENSHOT_DIR" -f "$FILENAME" --freeze
            play_sound
            notify-send -u low "Screenshot Saved" "Path: $SCREENSHOT_DIR/$FILENAME"
        fi
        ;;
        
    "$ICON_WIN")
        if [ "$ACTION" == "$ICON_COPY" ]; then
            hyprshot -m window --clipboard-only --freeze
            notify-send -u low "Screenshot" "Window copied to clipboard"
        elif [ "$ACTION" == "$ICON_SAVE" ]; then
            sleep 0.2
            hyprshot -m window -o "$SCREENSHOT_DIR" -f "$FILENAME" --freeze
            play_sound
            notify-send -u low "Screenshot Saved" "Path: $SCREENSHOT_DIR/$FILENAME"
        fi
        ;;
        
    "$ICON_FULL")
        sleep 0.5 
        if [ "$ACTION" == "$ICON_COPY" ]; then
            hyprshot -m output --clipboard-only
            notify-send -u low "Screenshot" "Fullscreen copied to clipboard"
        elif [ "$ACTION" == "$ICON_SAVE" ]; then
            hyprshot -m output -o "$SCREENSHOT_DIR" -f "$FILENAME"
            play_sound
            notify-send -u low "Screenshot Saved" "Path: $SCREENSHOT_DIR/$FILENAME"
        fi
        ;;
esac