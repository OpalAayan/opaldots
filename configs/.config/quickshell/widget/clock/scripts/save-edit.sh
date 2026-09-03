#!/usr/bin/env bash
# save-edit.sh — Query Hyprland for the editor window geometry, save it, restart layer mode.
set -euo pipefail

WIDGET_DIR="$HOME/.config/quickshell/widget/clock"
GEO_FILE="$WIDGET_DIR/geometry.json"

# ── Query Hyprland IPC for the WidgetEdit_Clock window ──
client_json=$(hyprctl clients -j | jq '.[] | select(.title == "WidgetEdit_Clock")')

if [[ -z "$client_json" ]]; then
    echo "Error: WidgetEdit_Clock window not found — is it still open?" >&2
    exit 1
fi

# ── Extract absolute geometry fields & monitor ──
abs_x=$(echo "$client_json" | jq -r '.at[0]')
abs_y=$(echo "$client_json" | jq -r '.at[1]')
width=$(echo "$client_json" | jq -r '.size[0]')
height=$(echo "$client_json" | jq -r '.size[1]')
mon_id=$(echo "$client_json" | jq -r '.monitor')

# ── Validate ──
for val in "$abs_x" "$abs_y" "$width" "$height"; do
    if [[ -z "$val" || "$val" == "null" ]]; then
        echo "Error: failed to extract geometry from hyprctl output" >&2
        exit 1
    fi
done

# ── Query monitor origin ──
mon_json=$(hyprctl monitors -j | jq --argjson mid "$mon_id" '.[] | select(.id == $mid)')
if [[ -z "$mon_json" ]]; then
    mon_json=$(hyprctl monitors -j | jq '.[0]')
fi

mon_x=$(echo "$mon_json" | jq -r '.x // 0')
mon_y=$(echo "$mon_json" | jq -r '.y // 0')

# ── Calculate layer-relative margins ──
margin_x=$((abs_x - mon_x))
margin_y=$((abs_y - mon_y))

# Clamp to >= 0
((margin_x < 0)) && margin_x=0
((margin_y < 0)) && margin_y=0

echo "Saving geometry: x=$margin_x y=$margin_y width=$width height=$height (monitor: $mon_id, origin: $mon_x,$mon_y)"

# ── Atomically write geometry.json ──
tmp_file=$(mktemp "$WIDGET_DIR/.geometry.json.XXXXXX")
jq -n \
    --argjson x "$margin_x" \
    --argjson y "$margin_y" \
    --argjson w "$width" \
    --argjson h "$height" \
    '{ x: $x, y: $y, width: $w, height: $h }' \
    >"$tmp_file"
mv -f "$tmp_file" "$GEO_FILE"

# ── Send notification ──
notify-send -t 2000 -a "Widget Manager" -i preferences-desktop-theme "Changed applied"

# ── Terminate edit window and relaunch layer mode cleanly ──
pkill -f "clock/edit\.qml" 2>/dev/null || true
exec "$WIDGET_DIR/scripts/start-layer.sh"
