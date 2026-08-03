#!/usr/bin/env zsh

MAC="E3:5F:23:22:BF:DD"
TIMEOUT=15

echo "Reconnecting Boult Audio Q ($MAC)..."

if ! bluetoothctl show | grep -q "Powered: yes"; then
    bluetoothctl power on > /dev/null 2>&1
    sleep 2
fi

if bluetoothctl info "$MAC" | grep -q "Connected: yes"; then
    echo "Already connected."
    exit 0
fi

# Background scan forces the Bluetooth daemon to refresh device visibility
bluetoothctl scan on > /dev/null 2>&1 &
SCAN_PID=$!

CONNECTED=false
for ((i=1; i<=TIMEOUT; i++)); do
    # Spam connect instead of unpairing
    if bluetoothctl connect "$MAC" > /dev/null 2>&1; then
        sleep 1
        if bluetoothctl info "$MAC" | grep -q "Connected: yes"; then
            CONNECTED=true
            break
        fi
    fi
    sleep 1
done

kill "$SCAN_PID" > /dev/null 2>&1
bluetoothctl scan off > /dev/null 2>&1

if [[ "$CONNECTED" == false ]]; then
    echo "Error: Failed to connect after $TIMEOUT seconds."
    exit 1
fi

echo "Success."
exit 0
