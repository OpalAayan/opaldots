#!/bin/bash
# Battery monitor helper script for Ironbar bar & Battery popup
# Usage: battery_status.sh [icon|bar|popup_icon|tooltip|title|subtitle|details|devices]

pango_escape() {
    local s="$1"
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    printf '%s' "$s"
}

read_sys() {
    local file="$1"
    if [[ -r "$file" ]]; then
        tr -d '\n' < "$file" 2>/dev/null
    fi
}

# Auto-detect primary battery in /sys/class/power_supply/
BAT_DIR=""
for d in /sys/class/power_supply/BAT*; do
    if [[ -d "$d" ]]; then
        BAT_DIR="$d"
        break
    fi
done
if [[ -z "$BAT_DIR" ]]; then
    for d in /sys/class/power_supply/*; do
        [[ -d "$d" ]] || continue
        if [[ "$(read_sys "$d/type")" == "Battery" && "$(read_sys "$d/scope")" != "Device" ]]; then
            BAT_DIR="$d"
            break
        fi
    done
fi

# Auto-detect AC adapter
AC_DIR=""
for candidate in /sys/class/power_supply/ACAD /sys/class/power_supply/AC /sys/class/power_supply/AC0 /sys/class/power_supply/ADP*; do
    if [[ -d "$candidate" ]]; then
        AC_DIR="$candidate"
        break
    fi
done
if [[ -z "$AC_DIR" ]]; then
    for d in /sys/class/power_supply/*; do
        [[ -d "$d" ]] || continue
        if [[ "$(read_sys "$d/type")" == "Mains" ]]; then
            AC_DIR="$d"
            break
        fi
    done
fi

# Read sysfs values
cap=$(read_sys "$BAT_DIR/capacity")
cap=${cap:-0}
[[ "$cap" =~ ^[0-9]+$ ]] || cap=0

status=$(read_sys "$BAT_DIR/status")
status=${status:-Unknown}

ac_online=$(read_sys "$AC_DIR/online")
ac_online=${ac_online:-0}
if [[ "$ac_online" == "1" ]]; then
    ac_text="AC Connected"
    ac_short="AC"
else
    ac_text="On Battery"
    ac_short="Battery"
fi

mfr=$(read_sys "$BAT_DIR/manufacturer")
model=$(read_sys "$BAT_DIR/model_name")
model=${model:-$(basename "${BAT_DIR:-BAT}")}
tech=$(read_sys "$BAT_DIR/technology")
tech=${tech:-Li-ion}
cycles=$(read_sys "$BAT_DIR/cycle_count")
cycles=${cycles:-0}

voltage_now=$(read_sys "$BAT_DIR/voltage_now")
voltage_min=$(read_sys "$BAT_DIR/voltage_min_design")
current_now=$(read_sys "$BAT_DIR/current_now")
power_now=$(read_sys "$BAT_DIR/power_now")

energy_now=$(read_sys "$BAT_DIR/energy_now")
energy_full=$(read_sys "$BAT_DIR/energy_full")
energy_full_design=$(read_sys "$BAT_DIR/energy_full_design")

charge_now=$(read_sys "$BAT_DIR/charge_now")
charge_full=$(read_sys "$BAT_DIR/charge_full")
charge_full_design=$(read_sys "$BAT_DIR/charge_full_design")

# Calculate Voltage (V)
voltage_v=$(awk -v v="${voltage_now:-0}" 'BEGIN { printf "%.1f", v / 1e6 }')

# Calculate Energy (Wh)
if [[ -n "$energy_now" && -n "$energy_full" && "$energy_full" -gt 0 ]] 2>/dev/null; then
    energy_now_wh=$(awk -v e="$energy_now" 'BEGIN { printf "%.1f", e / 1e6 }')
    energy_full_wh=$(awk -v e="$energy_full" 'BEGIN { printf "%.1f", e / 1e6 }')
elif [[ -n "$charge_now" && -n "$charge_full" && "$charge_full" -gt 0 ]] 2>/dev/null; then
    v_ref="${voltage_min:-$voltage_now}"
    v_ref=${v_ref:-0}
    energy_now_wh=$(awk -v c="$charge_now" -v v="$v_ref" 'BEGIN { printf "%.1f", (c * v) / 1e12 }')
    energy_full_wh=$(awk -v c="$charge_full" -v v="$v_ref" 'BEGIN { printf "%.1f", (c * v) / 1e12 }')
else
    energy_now_wh="0.0"
    energy_full_wh="0.0"
fi

# Calculate Health (%)
if [[ -n "$energy_full" && -n "$energy_full_design" && "$energy_full_design" -gt 0 ]] 2>/dev/null; then
    health=$(awk -v f="$energy_full" -v d="$energy_full_design" 'BEGIN { printf "%.1f", (f / d) * 100 }')
elif [[ -n "$charge_full" && -n "$charge_full_design" && "$charge_full_design" -gt 0 ]] 2>/dev/null; then
    health=$(awk -v f="$charge_full" -v d="$charge_full_design" 'BEGIN { printf "%.1f", (f / d) * 100 }')
else
    health="100.0"
fi

# Calculate Power (W)
if [[ -n "$power_now" && "$power_now" != "0" ]]; then
    power_w=$(awk -v p="$power_now" 'BEGIN { if (p < 0) p = -p; printf "%.2f", p / 1e6 }')
elif [[ -n "$current_now" && -n "$voltage_now" ]]; then
    power_w=$(awk -v c="$current_now" -v v="$voltage_now" 'BEGIN { p = (c * v) / 1e12; if (p < 0) p = -p; printf "%.2f", p }')
else
    power_w="0.00"
fi

# Optional time remaining from UPower
time_rem=""
if command -v upower >/dev/null 2>&1; then
    bat_upath=$(upower -e 2>/dev/null | grep -m1 '/battery_')
    if [[ -n "$bat_upath" ]]; then
        time_rem=$(upower -i "$bat_upath" 2>/dev/null | awk -F: '/time to (full|empty):/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }')
    fi
fi

# Optional future charge limit threshold detection
charge_limit=""
if [[ -r /sys/devices/platform/gigabyte_laptop/charge_limit ]]; then
    charge_limit=$(read_sys /sys/devices/platform/gigabyte_laptop/charge_limit)
elif [[ -n "$BAT_DIR" && -r "$BAT_DIR/charge_control_end_threshold" ]]; then
    charge_limit=$(read_sys "$BAT_DIR/charge_control_end_threshold")
fi

# Dynamic icon & color selection
charging_icons=("󰢟" "󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅")
discharging_icons=("󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹")

idx=$(( cap / 10 ))
(( idx < 0 )) && idx=0
(( idx > 10 )) && idx=10

if [[ "$status" == "Charging" ]]; then
    glyph="${charging_icons[$idx]}"
    (( cap >= 98 )) && glyph="󰂅"
elif [[ "$status" == "Full" ]] || { [[ "$ac_online" == "1" ]] && (( cap >= 98 )); }; then
    glyph="󰁹"
else
    if (( cap <= 10 )); then
        glyph="󰂃"
    else
        glyph="${discharging_icons[$idx]}"
    fi
fi

if [[ "$status" == "Charging" || "$status" == "Full" ]] || (( cap > 50 )); then
    color="#a6e3a1"
elif (( cap > 20 )); then
    color="#f9e2af"
else
    color="#f38ba8"
fi

mfr_esc=$(pango_escape "$mfr")
model_esc=$(pango_escape "$model")
tech_esc=$(pango_escape "$tech")
status_esc=$(pango_escape "$status")
ac_text_esc=$(pango_escape "$ac_text")
time_esc=$(pango_escape "$time_rem")

case "${1:-icon}" in
icon)
    printf "<span color='%s'>%s</span>\n" "$color" "$glyph"
    ;;
bar)
    printf "<span color='%s'>%s</span> %s%%\n" "$color" "$glyph" "$cap"
    ;;
popup_icon)
    printf "%s\n" "$glyph"
    ;;
tooltip)
    if [[ -n "$time_rem" ]]; then
        printf "Battery (%s): %s%% • %s (%s • %s)\n" "$model" "$cap" "$status" "$ac_short" "$time_rem"
    else
        printf "Battery (%s): %s%% • %s (%s)\n" "$model" "$cap" "$status" "$ac_short"
    fi
    ;;
title)
    printf "Battery • %s%%\n" "$cap"
    ;;
subtitle)
    if [[ -n "$time_esc" ]]; then
        printf "%s • %s • %s\n" "$model_esc" "$status_esc" "$time_esc"
    else
        printf "%s • %s (%s)\n" "$model_esc" "$status_esc" "$ac_short"
    fi
    ;;
details)
    full_name="${mfr_esc:+$mfr_esc }${model_esc}"
    time_part=""
    [[ -n "$time_esc" ]] && time_part="  •  $time_esc"
    printf "<b>%s</b>  <span size='small' alpha='75%%'>%s</span>\n" "$full_name" "$tech_esc"
    printf "<span size='small' alpha='85%%'>󱐋 %s (%s)%s</span>\n" "$status_esc" "$ac_text_esc" "$time_part"
    printf "<span size='small' alpha='85%%'>󰁹 %s / %s Wh   •   Health: %s%%</span>\n" "$energy_now_wh" "$energy_full_wh" "$health"
    printf "<span size='small' alpha='85%%'>󱐥 %s V   •   %s W   •   Cycles: %s</span>\n" "$voltage_v" "$power_w" "$cycles"
    if [[ -n "$charge_limit" ]]; then
        printf "<span size='small' alpha='85%%'>󱈑 Charge Limit: %s%%</span>\n" "$(pango_escape "$charge_limit")"
    fi
    ;;
devices)
    out=""
    if command -v upower >/dev/null 2>&1; then
        while IFS= read -r dev; do
            [[ -z "$dev" ]] && continue
            [[ "$dev" == *"/line_power_"* || "$dev" == *"/DisplayDevice"* ]] && continue

            info=$(upower -i "$dev" 2>/dev/null) || continue
            d_model=$(awk -F: '/^[[:space:]]*model:/ { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }' <<< "$info")
            d_pct=$(awk -F: '/^[[:space:]]*percentage:/ { sub(/^[^:]+:[[:space:]]*/, ""); gsub(/%/, ""); printf "%.0f", $0; exit }' <<< "$info")
            d_state=$(awk -F: '/^[[:space:]]*state:/ { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }' <<< "$info")

            if [[ -z "$d_model" ]]; then
                d_model=$(basename "$dev" | sed 's/^battery_//; s/^headset_dev_//; s/^headphones_dev_//; s/_/:/g')
            fi

            case "$dev" in
                */battery_*) d_icon="󰌢" ;;
                */headset_*|*/headphones_*) d_icon="󰋋" ;;
                */mouse_*) d_icon="󰍽" ;;
                */keyboard_*) d_icon="󰌌" ;;
                */gaming_input_*) d_icon="󰊴" ;;
                *) d_icon="󰁹" ;;
            esac

            case "$d_state" in
                charging) d_state_str="  Charging" ;;
                discharging) d_state_str="  Discharging" ;;
                fully-charged) d_state_str="  Full" ;;
                pending-charge) d_state_str="  Not charging" ;;
                *) d_state_str="" ;;
            esac

            [[ -z "$d_pct" ]] && d_pct="--"
            d_model_esc=$(pango_escape "${d_model:0:20}")
            line=$(printf "%s %-20s %3s%%%s" "$d_icon" "$d_model_esc" "$d_pct" "$d_state_str")
            out+="${out:+$'\n'}$line"
        done < <(upower -e 2>/dev/null)
    fi

    if [[ -n "$out" ]]; then
        printf "%s\n" "$out"
    elif [[ -n "$BAT_DIR" ]]; then
        printf "󰌢 %-20s %3s%%  %s\n" "$(pango_escape "${model:0:20}")" "$cap" "$status_esc"
    else
        printf "<span size='small' alpha='70%%'>No battery devices detected</span>\n"
    fi
    ;;
esac
