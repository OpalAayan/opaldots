#!/bin/bash
# Outputs dynamic user@hostname, session/uptime, and optional battery info for Ironbar Control Center

get_battery_part() {
    local bat_dir cap status icon
    bat_dir=$(compgen -G "/sys/class/power_supply/BAT*" 2>/dev/null | sort | head -n1)
    [[ -z "$bat_dir" || ! -r "$bat_dir/capacity" ]] && return 0

    cap=$(cat "$bat_dir/capacity" 2>/dev/null)
    [[ ! "$cap" =~ ^[0-9]+$ ]] && return 0

    status=$(cat "$bat_dir/status" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [[ "$status" == "charging" ]]; then
        icon="󰂄"
    elif ((cap >= 90)); then
        icon="󰁹"
    elif ((cap >= 70)); then
        icon="󰂀"
    elif ((cap >= 45)); then
        icon="󰁾"
    elif ((cap >= 20)); then
        icon="󰁼"
    else
        icon="󰁺"
    fi
    printf "   %s %s%%" "$icon" "$cap"
}

case "${1:-header}" in
    userhost)
        user=$(whoami 2>/dev/null || echo "${USER:-user}")
        host=$(hostnamectl --static 2>/dev/null)
        [[ -z "$host" ]] && host=$(cat /etc/hostname 2>/dev/null || uname -n)
        echo "${user}@${host}"
        ;;
    subline)
        up=$(uptime -p 2>/dev/null | sed -e 's/^up //' -e 's/ days\?/d/' -e 's/ hours\?/h/' -e 's/ minutes\?/m/' -e 's/,//g')
        wm="${XDG_CURRENT_DESKTOP:-hyprland}"
        wm="${wm,,}"
        bat=$(get_battery_part)
        echo "󰖯 ${wm}    up ${up:-0m}${bat}"
        ;;
    *)
        user=$(whoami 2>/dev/null || echo "${USER:-user}")
        host=$(hostnamectl --static 2>/dev/null)
        [[ -z "$host" ]] && host=$(cat /etc/hostname 2>/dev/null || uname -n)
        up=$(uptime -p 2>/dev/null | sed -e 's/^up //' -e 's/ days\?/d/' -e 's/ hours\?/h/' -e 's/ minutes\?/m/' -e 's/,//g')
        wm="${XDG_CURRENT_DESKTOP:-hyprland}"
        wm="${wm,,}"
        bat=$(get_battery_part)
        printf "<b>%s@%s</b>\n<span size='small' alpha='70%%'>󰖯 %s    up %s%s</span>\n" "$user" "$host" "$wm" "${up:-0m}" "$bat"
        ;;
esac
