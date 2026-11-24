#!/bin/bash
# Bluetooth helper script for Ironbar
# Usage: bluetooth_status.sh [is-powered|is-off|count]

case "${1:-count}" in
is-powered)
    state=$(busctl get-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 Powered 2>/dev/null)
    [[ "$state" == "b true" ]]
    exit $?
    ;;
is-off)
    state=$(busctl get-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 Powered 2>/dev/null)
    [[ "$state" != "b true" ]]
    exit $?
    ;;
count)
    count=$(bluetoothctl devices Connected 2>/dev/null | grep -c '^Device ')
    echo "${count:-0}"
    ;;
*)
    echo "Usage: $0 [is-powered|is-off|count]" >&2
    exit 2
    ;;
esac
