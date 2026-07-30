#!/usr/bin/env bash

# Standalone Ethernet panel logic for quickshell bar popup
# Adapted from nixos-configuration — no external dependencies

# Zero-latency hardware presence check via sysfs
if ! ls -1d /sys/class/net/e* &>/dev/null; then
    if command -v jq &>/dev/null; then
        jq -nc --arg power "off" '{ "present": false, "power": $power, "device": "", "connected": null }'
    else
        echo '{"present":false,"power":"off","device":"","connected":null}'
    fi
    exit 0
fi

ETH_DEV=$(LC_ALL=C nmcli -t -f DEVICE,TYPE d 2>/dev/null | awk -F: '$2=="ethernet" {print $1; exit}')

if [[ -z "$ETH_DEV" ]]; then
    if command -v jq &>/dev/null; then
        jq -nc --arg power "off" '{ "present": false, "power": $power, "device": "", "connected": null }'
    else
        echo '{"present":false,"power":"off","device":"","connected":null}'
    fi
    exit 0
fi

STATE=$(LC_ALL=C nmcli -t -f DEVICE,STATE d 2>/dev/null | awk -F: -v dev="$ETH_DEV" '$1==dev {print $2; exit}')

if [[ "$STATE" == "connected" || "$STATE" == "connecting" ]]; then
    POWER="on"
    
    IP=$(ip -4 addr show dev "$ETH_DEV" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    [ -z "$IP" ] && IP="No IP"

    SPEED=$(cat /sys/class/net/"$ETH_DEV"/speed 2>/dev/null)
    [ -n "$SPEED" ] && SPEED="${SPEED} Mbps" || SPEED="Unknown"

    MAC=$(cat /sys/class/net/"$ETH_DEV"/address 2>/dev/null)

    PROFILE=$(LC_ALL=C nmcli -t -f NAME,DEVICE c show --active 2>/dev/null | grep ":$ETH_DEV$" | cut -d: -f1 | head -n1)
    [ -z "$PROFILE" ] && PROFILE="Wired Connection"

    if command -v jq &>/dev/null; then
        CONNECTED_JSON=$(jq -nc \
            --arg id "$ETH_DEV" \
            --arg name "$PROFILE" \
            --arg icon "󰈀" \
            --arg ip "$IP" \
            --arg speed "$SPEED" \
            --arg mac "$MAC" \
            '{id: $id, name: $name, icon: $icon, ip: $ip, speed: $speed, mac: $mac}')
    else
        CONNECTED_JSON="{\"id\":\"$ETH_DEV\",\"name\":\"$PROFILE\",\"icon\":\"󰈀\",\"ip\":\"$IP\",\"speed\":\"$SPEED\",\"mac\":\"$MAC\"}"
    fi
else
    POWER="off"
    CONNECTED_JSON="null"
fi

if command -v jq &>/dev/null; then
    jq -nc \
        --arg power "$POWER" \
        --arg device "$ETH_DEV" \
        --argjson connected "$CONNECTED_JSON" \
        '{present: true, power: $power, device: $device, connected: $connected}'
else
    echo "{\"present\":true,\"power\":\"$POWER\",\"device\":\"$ETH_DEV\",\"connected\":$CONNECTED_JSON}"
fi
