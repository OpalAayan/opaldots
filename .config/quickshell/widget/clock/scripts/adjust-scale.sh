#!/usr/bin/env bash
# adjust-scale.sh — Adjust widget scale in geometry.json and refresh the running widget.
set -euo pipefail

WIDGET_DIR="$HOME/.config/quickshell/widget/clock"
SCRIPTS="$WIDGET_DIR/scripts"
GEO_FILE="$WIDGET_DIR/geometry.json"

if [[ ! -f "$GEO_FILE" ]]; then
    echo "Error: geometry.json not found at $GEO_FILE" >&2
    exit 1
fi

action="${1:-+0.10}"
val_arg="${2:-}"

current_scale=$(jq -r '.scale // 1.0' "$GEO_FILE" 2>/dev/null || echo "1.0")

if [[ "$action" == "reset" ]]; then
    new_scale="1.0"
elif [[ "$action" == "set" && -n "$val_arg" ]]; then
    new_scale=$(python3 -c "
v = float('$val_arg')
v = round(max(0.4, min(3.0, v)), 2)
print(f'{v:.2f}')
")
else
    # delta mode: e.g. +0.10, -0.10, +0.05, -0.05
    if [[ "$action" == "+" ]]; then
        delta="0.10"
    elif [[ "$action" == "-" ]]; then
        delta="-0.10"
    else
        delta="$action"
    fi

    new_scale=$(python3 -c "
cur = float('$current_scale')
d = float('$delta')
v = round(max(0.4, min(3.0, cur + d)), 2)
print(f'{v:.2f}')
")
fi

# ── If in edit mode, capture current live window position/size before updating ──
edit_running=false
client_json=$(hyprctl clients -j 2>/dev/null | jq '.[] | select(.title == "WidgetEdit_Clock")' 2>/dev/null || true)
if [[ -n "$client_json" && "$client_json" != "null" ]]; then
    edit_running=true
    abs_x=$(echo "$client_json" | jq -r '.at[0]')
    abs_y=$(echo "$client_json" | jq -r '.at[1]')
    width=$(echo "$client_json" | jq -r '.size[0]')
    height=$(echo "$client_json" | jq -r '.size[1]')
    mon_id=$(echo "$client_json" | jq -r '.monitor')

    mon_json=$(hyprctl monitors -j 2>/dev/null | jq --argjson mid "$mon_id" '.[] | select(.id == $mid)' 2>/dev/null || true)
    if [[ -z "$mon_json" || "$mon_json" == "null" ]]; then
        mon_json=$(hyprctl monitors -j 2>/dev/null | jq '.[0]' 2>/dev/null || true)
    fi
    mon_x=$(echo "$mon_json" | jq -r '.x // 0')
    mon_y=$(echo "$mon_json" | jq -r '.y // 0')
    reserved_left=$(echo "$mon_json" | jq -r '.reserved[0] // 0')
    reserved_top=$(echo "$mon_json" | jq -r '.reserved[1] // 0')

    margin_x=$(( abs_x - mon_x - reserved_left ))
    margin_y=$(( abs_y - mon_y - reserved_top ))
    (( margin_x < 0 )) && margin_x=0
    (( margin_y < 0 )) && margin_y=0

    # Write updated geometry + scale (using cat to preserve file inode for inotify)
    tmp_file=$(mktemp)
    jq -n \
        --argjson x "$margin_x" \
        --argjson y "$margin_y" \
        --argjson w "$width" \
        --argjson h "$height" \
        --argjson s "$new_scale" \
        '{ x: $x, y: $y, width: $w, height: $h, scale: $s }' > "$tmp_file"
    cat "$tmp_file" > "$GEO_FILE"
    rm -f "$tmp_file"

    # Refresh edit window in-place with new scale
    exec "$SCRIPTS/start-edit.sh"
else
    # In normal layer mode: update scale in geometry.json
    tmp_file=$(mktemp)
    jq --argjson s "$new_scale" '.scale = $s' "$GEO_FILE" > "$tmp_file"
    cat "$tmp_file" > "$GEO_FILE"
    rm -f "$tmp_file"

    # If layer widget is currently running, refresh it
    if pgrep -f "clock/shell\.qml" >/dev/null 2>&1; then
        exec "$SCRIPTS/start-layer.sh"
    fi
fi

pct=$(python3 -c "print(int(round(float('$new_scale') * 100)))")
notify-send -t 1200 -a "Widget Manager" -i preferences-desktop-theme "Clock Widget" "Scale: ${pct}%"
echo "Scale set to ${new_scale} (${pct}%)"
