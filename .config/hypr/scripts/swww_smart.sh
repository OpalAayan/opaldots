#!/bin/bash
#
# 🚀 swww_smart.sh - The "Smart Runner"
#
# 1. Cleans up mpvpaper/hyprpaper (No conflicts!)
# 2. auto-starts swww-daemon if needed.
# 3. Cycles through your baked WebPs.
# 4. Uses ONLY the cool transitions you want.
#

# === CONFIGURATION ===
# Path to your baked WebP files
WALLPAPER_DIR="$HOME/Videos/Livewallpapers/baked"
STATE_FILE="$HOME/.cache/swww_smart_index.txt"

# The "Cool List" of transitions
# We pick one of these randomly every time we switch.
TRANSITIONS=("grow" "outer" "fade" "random" "wave")

# Transition Speed Settings (Tuned for snappiness)
TRANS_FPS=60
TRANS_STEP=90
TRANS_DURATION=1.5

# =====================

# 1. CLEANUP (The "Smart" Part)
# Stop heavy/conflicting backends immediately.
if pgrep -x "mpvpaper" >/dev/null; then
  pkill mpvpaper
fi
if pgrep -x "hyprpaper" >/dev/null; then
  pkill hyprpaper
fi

# 2. DAEMON CHECK
# If swww isn't running, start it quietly.
if ! pgrep -x "swww-daemon" >/dev/null; then
  swww-daemon &
  sleep 0.5 # Give it a moment to wake up
fi

# 3. FIND WALLPAPERS
# Look for your baked .webp files
mapfile -d '' WALLPAPERS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f -iname "*.webp" -print0 | sort -z)

if [ ${#WALLPAPERS[@]} -eq 0 ]; then
  notify-send -u critical "Live Wallpaper Error" "No baked wallpapers found in $WALLPAPER_DIR"
  exit 1
fi

# 4. INDEX LOGIC (Sequential Cycle)
# Reads the last index so you get the "Next" wallpaper, not a random one.
if [ ! -f "$STATE_FILE" ]; then
  echo "-1" >"$STATE_FILE"
fi

CURRENT_INDEX=$(cat "$STATE_FILE")
NEXT_INDEX=$(((CURRENT_INDEX + 1) % ${#WALLPAPERS[@]}))
NEXT_WALL="${WALLPAPERS[$NEXT_INDEX]}"
WALL_NAME=$(basename "$NEXT_WALL")

# 5. PICK A TRANSITION
# Randomly select one from your allowed list
RANDOM_TRANS=${TRANSITIONS[$RANDOM % ${#TRANSITIONS[@]}]}

# 6. APPLY WALLPAPER
# --resize crop ensures it fits your 1366x768 screen perfectly without stretching
swww img "$NEXT_WALL" \
  --transition-type "$RANDOM_TRANS" \
  --transition-fps "$TRANS_FPS" \
  --transition-step "$TRANS_STEP" \
  --transition-duration "$TRANS_DURATION" \
  --resize crop

# 7. SAVE STATE & NOTIFY
echo "$NEXT_INDEX" >"$STATE_FILE"
notify-send -t 2000 -i "preferences-desktop-wallpaper" "Live Wallpaper" "Playing: $WALL_NAME ($RANDOM_TRANS)"
