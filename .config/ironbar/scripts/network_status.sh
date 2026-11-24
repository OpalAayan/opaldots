#!/bin/bash
# NetworkManager helper script for Ironbar bar & Network popup
# Usage: network_status.sh [icon|name|subtitle|details|wifi_status|wifi_list|toggle-wifi|rescan]

is_vpn_connected() {
    nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -qiE 'proton|pvpn|:vpn:|:wireguard:|:tun:' && return 0
    ip -br link 2>/dev/null | grep -qiE 'proton|pvpn|protun|wg-proton' && return 0
    return 1
}

line=$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null | grep -m1 -E ':(wifi|ethernet):connected:')
dev=$(echo "$line" | cut -d: -f1)
type=$(echo "$line" | cut -d: -f2)
name=$(echo "$line" | cut -d: -f4-)

case "$type" in
wifi)
    sig=$(nmcli -t -f IN-USE,SIGNAL device wifi 2>/dev/null | grep -m1 '^\*:' | cut -d: -f2)
    sig=${sig:-75}
    if ((sig >= 80)); then
        icon="󰤨"
    elif ((sig >= 60)); then
        icon="󰤥"
    elif ((sig >= 40)); then
        icon="󰤢"
    elif ((sig >= 20)); then
        icon="󰤟"
    else icon="󰤯"; fi
    type_label="Wi-Fi"
    ;;
ethernet)
    icon="󰈀"
    type_label="Ethernet"
    ;;
*)
    icon="󰖪"
    name="Disconnected"
    type_label="Offline"
    ;;
esac

if is_vpn_connected; then
    icon="󰖂"
fi

case "${1:-icon}" in
icon)
    echo "$icon"
    ;;
name)
    echo "${name:0:18}"
    ;;
subtitle)
    if [[ "$name" == "Disconnected" ]]; then
        echo "Not connected"
    else
        echo "${type_label} • Connected"
    fi
    ;;
details)
    if [[ "$name" == "Disconnected" || -z "$dev" ]]; then
        printf "<b>No Active Connection</b>\n<span size='small' alpha='70%%'>Select a Wi-Fi network or plug in Ethernet</span>\n"
    else
        ip=$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
        [[ -z "$ip" ]] && ip=$(nmcli -g IP4.ADDRESS device show "$dev" 2>/dev/null | cut -d/ -f1 | head -n1)
        [[ -z "$ip" ]] && ip="Obtaining IP..."
        printf "<b>%s (%s)</b>\n<span size='small' alpha='75%%'>󰩟 IP: %s   •   %s</span>\n" "$name" "$dev" "$ip" "$type_label"
    fi
    ;;
wifi_status)
    radio=$(nmcli radio wifi 2>/dev/null)
    if [[ "$radio" == "enabled" ]]; then
        echo "Enabled • Click to toggle"
    else
        echo "Disabled • Click to enable"
    fi
    ;;
wifi_list)
    radio=$(nmcli radio wifi 2>/dev/null)
    if [[ "$radio" != "enabled" ]]; then
        printf "<span size='small' alpha='70%%'>󰤮  Wi-Fi radio is turned off</span>\n"
        exit 0
    fi
    list=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null | awk -F: '
            $2 != "" && !seen[$2]++ {
                mark = ($1 == "*") ? "󰄬 " : "󰤨 "
                sec = ($4 != "" && $4 != "--") ? "" : " "
                printf "%s %-20s %3s%% %s\n", mark, substr($2, 1, 20), $3, sec
            }
        ' | head -n 5)
    if [[ -z "$list" ]]; then
        printf "<span size='small' alpha='70%%'>󰤯  No Wi-Fi networks found nearby</span>\n"
    else
        echo "$list"
    fi
    ;;
toggle-wifi)
    radio=$(nmcli radio wifi 2>/dev/null)
    if [[ "$radio" == "enabled" ]]; then
        nmcli radio wifi off 2>/dev/null
        dunstify -a "NetworkManager" -u low -r 9994 "󰤮  Wi-Fi Disabled" 2>/dev/null
    else
        nmcli radio wifi on 2>/dev/null
        dunstify -a "NetworkManager" -u low -r 9994 "󰤨  Wi-Fi Enabled" 2>/dev/null
    fi
    ;;
rescan)
    nmcli device wifi rescan 2>/dev/null
    dunstify -a "NetworkManager" -u low -r 9994 "󰑐  Scanning Wi-Fi networks..." 2>/dev/null
    ;;
esac
