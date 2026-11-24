#!/usr/bin/env bash

HOST=$(hostname)
LASTLOGIN=$(last "$USER" | head -n1 | tr -s ' ' | cut -d' ' -f5,6,7)
UPTIME=$(uptime -p | sed 's/up //')

LOCK=""
LOGOUT="󰍃"
SUSPEND=""
REBOOT=""
POWER=""

YES="󰄬"
BACK="󰁍"

ROFI_THEME="~/.config/rofi/power.rasi"

rofi_cmd() {
  rofi \
    -dmenu \
    -i \
    -theme "$ROFI_THEME" \
    -p "󰧵 $USER@$HOST" \
    -mesg "󱫐 Last Login: $LASTLOGIN   |   󰅐 Uptime: $UPTIME"
}

power_menu() {
  local choice

  choice=$(echo -e \
    "$LOCK
$LOGOUT
$SUSPEND
$REBOOT
$POWER" | rofi_cmd)

  case "$choice" in
  "$LOCK")
    hyprlock
    ;;

  "$LOGOUT")
    confirm_menu "Logout" " hyprctl dispatch 'hl.dispatch(hl.dsp.exit())'"
    ;;

  "$SUSPEND")
    confirm_menu "Suspend" "systemctl suspend"
    ;;

  "$REBOOT")
    confirm_menu "Reboot" "systemctl reboot"
    ;;

  "$POWER")
    confirm_menu "Power Off" "systemctl poweroff"
    ;;
  esac
}

confirm_menu() {
  local action="$1"
  local command="$2"

  local choice

  choice=$(echo -e \
    "$YES
$BACK" |
    rofi \
      -dmenu \
      -i \
      -theme "$ROFI_THEME" \
      -theme-str 'window { width: 350px; }' \
      -theme-str 'mainbox { children: [ "message", "listview" ]; }' \
      -theme-str 'listview { columns: 2; lines: 1; }' \
      -theme-str 'element-text { horizontal-align: 0.5; }' \
      -theme-str 'textbox { horizontal-align: 0.5; }' \
      -p "$action" \
      -mesg "You wanna $action?")

  case "$choice" in
  "$YES")
    eval "$command"
    ;;
  "$BACK")
    power_menu
    ;;
  esac
}

power_menu
