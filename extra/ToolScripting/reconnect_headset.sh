#!/usr/bin/env bash

MAC="E3:5F:23:22:BF:DD"
NAME="Boult Audio Q"
SCAN_TIMEOUT=15
CONNECT_TIMEOUT=15
MAX_RETRIES=2
SCAN_PID=""

# Always stop scanning if the script exits or is interrupted (Ctrl+C)
cleanup() {
    if [[ -n "$SCAN_PID" ]]; then
        kill "$SCAN_PID" 2>/dev/null || true
    fi
    bluetoothctl scan off >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

is_connected() {
    bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"
}

is_paired() {
    bluetoothctl info "$MAC" 2>/dev/null | grep -q "Paired: yes"
}

# 1. Ensure Bluetooth adapter is powered on
if ! bluetoothctl show | grep -q "Powered: yes"; then
    echo "Powering on Bluetooth..."
    bluetoothctl power on >/dev/null 2>&1
    sleep 2
fi

if is_connected; then
    echo "$NAME ($MAC) is already connected."
    exit 0
fi

# 2. Main retry loop
for ((attempt = 1; attempt <= MAX_RETRIES; attempt++)); do
    echo "--- Attempt $attempt of $MAX_RETRIES ---"
    echo "Scanning for $NAME ($MAC)..."

    # --timeout keeps bluetoothctl alive so bluetoothd actually scans
    bluetoothctl --timeout "$SCAN_TIMEOUT" scan on >/dev/null 2>&1 &
    SCAN_PID=$!

    FOUND=false
    for ((i = 1; i <= SCAN_TIMEOUT; i++)); do
        if bluetoothctl devices | grep -qi "$MAC"; then
            FOUND=true
            break
        fi
        sleep 1
    done

    # Stop scanning before connecting so the radio isn't busy
    kill "$SCAN_PID" 2>/dev/null || true
    SCAN_PID=""
    bluetoothctl scan off >/dev/null 2>&1
    sleep 1

    if [[ "$FOUND" == false ]]; then
        echo "Device not found during scan."
    else
        echo "Found $NAME ($MAC)!"

        # Pair and trust if not already paired
        if ! is_paired; then
            echo "Pairing and trusting..."
            timeout "$CONNECT_TIMEOUT" bluetoothctl pair "$MAC" >/dev/null 2>&1
            bluetoothctl trust "$MAC" >/dev/null 2>&1
            sleep 1
        fi

        echo "Connecting..."
        timeout "$CONNECT_TIMEOUT" bluetoothctl connect "$MAC" >/dev/null 2>&1
        sleep 2

        if is_connected; then
            echo "Success: Connected to $NAME!"
            exit 0
        fi
        echo "Connection failed or timed out."
    fi

    # 3. Reset state before retrying
    if ((attempt < MAX_RETRIES)); then
        echo "Forgetting device and resetting scan before retrying..."
        bluetoothctl remove "$MAC" >/dev/null 2>&1
        bluetoothctl scan off >/dev/null 2>&1
        sleep 2
    fi
done

echo "Error: Could not connect to $NAME after $MAX_RETRIES attempts."
exit 1
