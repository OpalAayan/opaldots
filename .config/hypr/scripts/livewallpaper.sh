#!/bin/bash
#
# ██╗     ██╗██╗   ██╗███████╗     ██╗    ██╗ █████╗ ██╗     ██╗     ███████╗
# ██║     ██║╚██╗ ██╔╝██╔════╝     ██║    ██║██╔══██╗██║     ██║     ██╔════╝
# ██║     ██║ ╚████╔╝ █████╗       ██║ █╗ ██║███████║██║     ██║     █████╗
# ██║     ██║  ╚██╔╝  ██╔══╝       ██║███╗██║██╔══██║██║     ██║     ██╔══╝
# ███████╗██║   ██║   ███████╗     ╚███╔███╔╝██║  ██║███████╗███████╗███████╗
# ╚══════╝╚═╝   ╚═╝   ╚══════╝      ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝
#
#             Live Wallpaper Changer - Sequential
#

# --- CONFIGURATION ---
LIVE_WALLPAPER_DIR="$HOME/Videos/Livewallpapers"
STATE_FILE="$HOME/.cache/livewallpaper_index.txt"
MPV_MONITOR="*" # Use "*" for all monitors, or specify (e.g., "DP-1")

# --- SCRIPT LOGIC ---

# Define some colors for stylish terminal output
C_GREEN='\033[0;32m'
C_CYAN='\033[0;36m'
C_NC='\033[0m' # No Color

# --- 1. CLEAN SLATE ---
# Kill all other wallpaper backends to prevent overlap or issues.
# This also handles the mpvpaper constraint (kill old one before starting new one).
echo -e "${C_CYAN}Stopping existing wallpaper backends...${C_NC}"
pkill mpvpaper
pkill awww-daemon
pkill hyprpaper
# Give pkill a moment to act before launching the new process
sleep 0.1

# --- 2. FIND WALLPAPERS ---
# Ensure the cache directory exists
mkdir -p "$(dirname "$STATE_FILE")"

# Get a sorted list of all live wallpapers (add any other video formats you use)
mapfile -d '' WALLPAPERS < <(find "$LIVE_WALLPAPER_DIR" -type f \( -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" -o -iname "*.mov" \) -print0 | sort -z)

# --- 3. CHECK IF EMPTY ---
# Exit if no wallpapers are found
if [ ${#WALLPAPERS[@]} -eq 0 ]; then
  notify-send -u critical "Live Wallpaper Error" "No videos found in $LIVE_WALLPAPER_DIR"
  exit 1
fi

# --- 4. INDEXING LOGIC ---
# Read the last used index. Default to -1 if the file doesn't exist.
LAST_INDEX=-1
if [ -f "$STATE_FILE" ]; then
  LAST_INDEX=$(cat "$STATE_FILE")
fi

# Calculate the next index, looping back to the start if necessary.
if ! [[ "$LAST_INDEX" =~ ^[0-9]+$ ]] || [ "$LAST_INDEX" -ge "${#WALLPAPERS[@]}" ]; then
  LAST_INDEX=-1
fi
NEXT_INDEX=$(((LAST_INDEX + 1) % ${#WALLPAPERS[@]}))

# --- 5. SET WALLPAPER ---
# Select the wallpaper for the new index
NEXT_WALLPAPER="${WALLPAPERS[$NEXT_INDEX]}"
WALLPAPER_BASENAME=$(basename "$NEXT_WALLPAPER")

# Launch mpvpaper in the background, looping, on the specified monitor(s)
# We use nohup and redirect output to /dev/null to ensure it detaches
# cleanly and runs in the background without spamming logs.
# NEW (with hardware acceleration profile):
nohup mpvpaper -o "--loop --profile=wallpaper --no-audio" "$MPV_MONITOR" "$NEXT_WALLPAPER" >/dev/null 2>&1 &

# --- 6. SAVE STATE & NOTIFY ---
# Save the new index to the state file for the next run
echo "$NEXT_INDEX" >"$STATE_FILE"

# Send a notification
#notify-send "Live Wallpaper Changed" "$WALLPAPER_BASENAME"

# Echo to terminal with some style
echo -e "${C_GREEN}Live wallpaper set to:${C_NC} ${C_CYAN}$WALLABAPER_BASENAME${C_NC}"

