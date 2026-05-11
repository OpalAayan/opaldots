#!/usr/bin/env bash

# Fuzzel Power Menu for Hyprland
# Save this to: ~/.config/hypr/scripts/powermenu.sh

# Show menu and get selection using fuzzel
chosen=$(printf "󰌾  Lock\n󰤄  Suspend\n󰍃  Logout\n󰜉  Reboot\n󰐥  Shutdown" | fuzzel \
  --dmenu \
  --prompt="⏻ " \
  --lines=5 \
  --width=20 \
  --horizontal-pad=40 \
  --vertical-pad=20 \
  --inner-pad=20 \
  --font="JetBrains Mono Nerd Font:size=16" \
  --background=1e1e2eee \
  --text-color=cdd6f4ff \
  --match-color=f38ba8ff \
  --selection-color=45475aff \
  --selection-text-color=cdd6f4ff \
  --border-width=3 \
  --border-color=b4befeff \
  --border-radius=15)

# Exit if nothing is selected
[[ -z "$chosen" ]] && exit 0

# Confirmation for critical actions
case "$chosen" in
"󰜉  Reboot" | "󰐥  Shutdown" | "󰍃  Logout")
  confirm=$(printf "󰔹  Yes\n󰔷  No" | fuzzel \
    --dmenu \
    --prompt="Confirm? " \
    --lines=2 \
    --width=15 \
    --horizontal-pad=40 \
    --vertical-pad=20 \
    --inner-pad=20 \
    --font="JetBrains Mono Nerd Font:size=14" \
    --background=1e1e2eee \
    --text-color=cdd6f4ff \
    --match-color=a6e3a1ff \
    --selection-color=45475aff \
    --selection-text-color=cdd6f4ff \
    --border-width=3 \
    --border-color=f38ba8ff \
    --border-radius=15)

  [[ "$confirm" != "󰔹  Yes" ]] && exit 0
  ;;
esac

# Execute the selected action
case "$chosen" in
"󰌾  Lock")
  # Added sleep and simplified the command for reliability
  sleep 0.1
  hyprlock
  ;;
"󰤄  Suspend")
  systemctl suspend
  ;;
"󰍃  Logout")
  hyprctl dispatch exit
  ;;
"󰜉  Reboot")
  systemctl reboot
  ;;
"󰐥  Shutdown")
  systemctl poweroff
  ;;
esac

