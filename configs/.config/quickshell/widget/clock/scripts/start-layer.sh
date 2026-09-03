#!/usr/bin/env bash
# start-layer.sh — Kill running clock widgets and launch layer mode cleanly.
set -euo pipefail

WIDGET_DIR="$HOME/.config/quickshell/widget/clock"

# ── Kill existing clock instances (both layer and edit) ──
pkill -f "clock/shell\.qml" 2>/dev/null || true
pkill -f "clock/edit\.qml"  2>/dev/null || true

# Wait until processes are dead (up to 1s)
for _ in $(seq 1 10); do
    if ! pgrep -f "clock/(shell|edit)\.qml" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
pkill -9 -f "clock/(shell|edit)\.qml" 2>/dev/null || true

# ── Launch layer-shell widget fully detached ──
nohup qs -p "$WIDGET_DIR/shell.qml" >/dev/null 2>&1 &
