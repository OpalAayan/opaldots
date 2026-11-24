#!/usr/bin/env bash

# --- Configuration ---
SOUND_DIR="$HOME/.local/share/sounds"
INSERT_SOUND="$SOUND_DIR/insert.wav"
REMOVE_SOUND="$SOUND_DIR/remove.wav"

# --- Startup Safety ---
# Wait a moment for audio server (PipeWire/Pulse) to initialize on login
sleep 2

# --- Dependency Check ---
if ! command -v paplay &> /dev/null; then
    # Fallback to aplay if paplay (PulseAudio) is missing
    if command -v aplay &> /dev/null; then
        PLAYER="aplay"
    else
        exit 1
    fi
else
    PLAYER="paplay"
fi

# --- The Monitor Loop ---
# 1. stdbuf -oL: Forces output to be "Line Buffered". This fixes the delay/hang.
# 2. We filter for 'usb' subsystem events.
stdbuf -oL udevadm monitor --kernel --subsystem-match=usb | while read -r line; do
    
    # --- Filter Logic ---
    # We want to ignore "Interfaces" (e.g., 1-1:1.0) and keep "Devices" (e.g., 1-1).
    # Interface events usually end with something like ":1.0 (usb)".
    # We regex match the END of the line ($) to avoid matching PCI addresses in the middle.
    
    if [[ "$line" =~ :[0-9]+\.[0-9]+\ \(usb\)$ ]]; then
        continue
    fi

    # --- Actions ---
    if [[ "$line" == *"add"* ]]; then
        # Play Sound
        $PLAYER "$INSERT_SOUND" &
        # Send Notification (2 seconds)
        notify-send -t 2000 "Hardware" "USB Connected" -i drive-removable-media &
        
    elif [[ "$line" == *"remove"* ]]; then
        # Play Sound
        $PLAYER "$REMOVE_SOUND" &
        # Send Notification (2 seconds)
        notify-send -t 2000 "Hardware" "USB Removed" -i drive-removable-media &
    fi

done