#!/usr/bin/env bash
# start-edit.sh — Kill layer widget, launch floating editor, and position it.
set -euo pipefail

WIDGET_DIR="$HOME/.config/quickshell/widget/clock"
GEO_FILE="$WIDGET_DIR/geometry.json"

# ── Kill existing clock instances cleanly ──
pkill -f "clock/shell\.qml" 2>/dev/null || true
pkill -f "clock/edit\.qml"  2>/dev/null || true

for _ in $(seq 1 10); do
    if ! pgrep -f "clock/(shell|edit)\.qml" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
pkill -9 -f "clock/(shell|edit)\.qml" 2>/dev/null || true

# ── Read saved geometry ──
if [[ ! -f "$GEO_FILE" ]]; then
    echo "Error: geometry.json not found at $GEO_FILE" >&2
    exit 1
fi

x=$(jq -r '.x'           "$GEO_FILE")
y=$(jq -r '.y'           "$GEO_FILE")
width=$(jq -r '.width'   "$GEO_FILE")
height=$(jq -r '.height' "$GEO_FILE")

# ── Validate ──
for val in "$x" "$y" "$width" "$height"; do
    if [[ -z "$val" || "$val" == "null" ]]; then
        echo "Error: invalid geometry.json — got null or empty value" >&2
        exit 1
    fi
done

# ── Query focused monitor's origin coordinates ──
mon_json=$(hyprctl monitors -j 2>/dev/null | jq '.[] | select(.focused == true)' 2>/dev/null || true)
if [[ -z "$mon_json" ]]; then
    mon_json=$(hyprctl monitors -j 2>/dev/null | jq '.[0]' 2>/dev/null || true)
fi
mon_x=$(echo "$mon_json" | jq -r '.x // 0')
mon_y=$(echo "$mon_json" | jq -r '.y // 0')

# ── Calculate global screen coordinates ──
abs_x=$(( x + mon_x ))
abs_y=$(( y + mon_y ))

# Pre-register window rule with target position & size so it spawns in-place
echo "hl.window_rule({ match = { title = \"^WidgetEdit_Clock$\" }, float = true, pin = true, size = \"${width} ${height}\", move = \"${abs_x} ${abs_y}\" })" | hyprctl repl >/dev/null 2>&1 || true

# ── Launch editor window detached ──
nohup qs -p "$WIDGET_DIR/edit.qml" >/dev/null 2>&1 &

# ── Poll until the window maps in hyprctl clients ──
addr=""
for _ in $(seq 1 30); do
    addr=$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.title == "WidgetEdit_Clock") | .address' 2>/dev/null || true)
    if [[ -n "$addr" && "$addr" != "null" ]]; then
        break
    fi
    sleep 0.1
done

# ── Ensure exact position and size via Hyprland dispatchers ──
if [[ -n "$addr" && "$addr" != "null" ]]; then
    echo "
    local w = hl.get_window_by_address(\"$addr\")
    if w then
        hl.dispatch(hl.dsp.focus.window({ address = \"$addr\" }))
        hl.dispatch(hl.dsp.window.resize({ x = $width, y = $height, relative = false }))
        hl.dispatch(hl.dsp.window.move({ x = $abs_x, y = $abs_y, relative = false }))
    end
    " | hyprctl repl >/dev/null 2>&1 || true
fi

# Fallback dispatchers for standard Hyprland syntax
hyprctl dispatch resizewindowpixel "exact ${width} ${height},title:^WidgetEdit_Clock$" 2>/dev/null || true
hyprctl dispatch movewindowpixel "exact ${abs_x} ${abs_y},title:^WidgetEdit_Clock$" 2>/dev/null || true
