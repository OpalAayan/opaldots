#!/bin/bash
# Usage: vpn_control.sh [status|is-active|is-inactive|toggle]
# Fast status checks via nmcli / ip link; robust edge-case handling on toggle.

LOCK_FILE="/tmp/.vpn_control.lock"
NOTIF_ID=9995
APPNAME="Proton VPN"

notify_vpn() {
    local urgency="${1:-normal}"
    local title="$2"
    local body="$3"
    if command -v dunstify >/dev/null 2>&1; then
        dunstify -a "$APPNAME" -u "$urgency" -r "$NOTIF_ID" "$title" "$body" 2>/dev/null
    else
        notify-send -a "$APPNAME" -u "$urgency" -t 3500 "$title" "$body" 2>/dev/null
    fi
}

is_connected() {
    nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -qiE 'proton|pvpn|:vpn:|:wireguard:|:tun:' && return 0
    ip -br link 2>/dev/null | grep -qiE 'proton|pvpn|protun|wg-proton' && return 0
    return 1
}

get_vpn_server() {
    local conn
    conn=$(nmcli -t -f NAME connection show --active 2>/dev/null | grep -iE 'proton|pvpn' | head -n1)
    if [[ -n "$conn" ]]; then
        conn="${conn#ProtonVPN }"
        conn="${conn#Proton VPN }"
        conn="${conn#pvpn-}"
        echo "$conn"
        return 0
    fi
    return 1
}

case "${1:-status}" in
is-active)
    is_connected
    exit $?
    ;;
is-inactive)
    ! is_connected
    exit $?
    ;;
status)
    if [[ -f "$LOCK_FILE" ]]; then
        cat "$LOCK_FILE" 2>/dev/null || echo "Working..."
        exit 0
    fi
    if is_connected; then
        srv=$(get_vpn_server)
        if [[ -n "$srv" && "${#srv}" -le 18 ]]; then
            echo "Connected • $srv"
        else
            echo "Connected"
        fi
    else
        echo "Disconnected"
    fi
    ;;
toggle)
    # Prevent overlapping toggle executions on rapid clicks
    if [[ -f "$LOCK_FILE" ]]; then
        notify_vpn low "󰦝  Proton VPN" "Operation already in progress..."
        exit 0
    fi

    # Determine CLI binary (Proton VPN v4 CLI is `protonvpn`, legacy is `protonvpn-cli`)
    if command -v protonvpn >/dev/null 2>&1; then
        VPN_BIN="protonvpn"
    elif command -v protonvpn-cli >/dev/null 2>&1; then
        VPN_BIN="protonvpn-cli"
    else
        notify_vpn critical "󰦝  Proton VPN Error" "protonvpn CLI is not installed."
        exit 1
    fi

    trap 'rm -f "$LOCK_FILE"' EXIT

    if is_connected; then
        echo "Disconnecting..." >"$LOCK_FILE"
        notify_vpn low "󰦝  Proton VPN" "Disconnecting..."
        out=$("$VPN_BIN" disconnect 2>&1)
        rc=$?
        rm -f "$LOCK_FILE"
        if [[ $rc -eq 0 ]] || ! is_connected; then
            notify_vpn low "󰦝  Proton VPN" "Disconnected."
        else
            err_msg=$(echo "$out" | grep -v '^$' | tail -n1)
            notify_vpn critical "󰦝  Disconnect Failed" "${err_msg:-Unable to disconnect VPN.}"
        fi
        exit 0
    fi

    # Check account sign-in status via `protonvpn info`
    if [[ "$VPN_BIN" == "protonvpn" ]]; then
        info_out=$("$VPN_BIN" info 2>&1)
        if echo "$info_out" | grep -qi "desktop app is currently running"; then
            notify_vpn critical "󰦝  Proton VPN" "Desktop GUI app is running. Close it to use CLI toggle."
            exit 1
        fi
        # `protonvpn info` prints `Account: 'username'` when signed in, or `Account: 'None'` / empty when signed out
        acct=$(echo "$info_out" | sed -n "s/.*Account: '\([^']*\)'.*/\1/p")
        if [[ -z "$acct" || "$acct" == "None" || "$acct" == "null" ]] || echo "$info_out" | grep -qiE "not signed in|authentication required|please sign in"; then
            notify_vpn critical "󰦝  Proton VPN" "Not signed in! Run 'protonvpn signin' in terminal first."
            exit 1
        fi
    fi

    echo "Connecting..." >"$LOCK_FILE"
    notify_vpn low "󰖂  Proton VPN" "Connecting to fastest server..."

    if [[ "$VPN_BIN" == "protonvpn" ]]; then
        out=$("$VPN_BIN" connect 2>&1)
        rc=$?
    else
        out=$("$VPN_BIN" connect -f 2>&1)
        rc=$?
    fi
    rm -f "$LOCK_FILE"

    if [[ $rc -eq 0 ]] && is_connected; then
        # Extract connection summary (e.g. "Connected to US-FREE#96 in Seattle, United States.")
        summary=$(echo "$out" | grep -i "Connected to" | head -n1)
        ip_line=$(echo "$out" | grep -i "Your new IP" | head -n1)
        notify_vpn normal "󰖂  Proton VPN Connected" "${summary:-Connected}${ip_line:+$'\n'$ip_line}"
    else
        if echo "$out" | grep -qiE "Authentication required|please sign in"; then
            notify_vpn critical "󰦝  Proton VPN" "Authentication required. Run 'protonvpn signin' in terminal."
        elif echo "$out" | grep -qi "desktop app is currently running"; then
            notify_vpn critical "󰦝  Proton VPN" "Desktop GUI app is running. Please close it first."
        elif echo "$out" | grep -qi "Network connectivity issues"; then
            notify_vpn critical "󰦝  Proton VPN" "Network error. Check your internet connection."
        else
            err_msg=$(echo "$out" | grep -v '^$' | tail -n1)
            notify_vpn critical "󰦝  Proton VPN Failed" "${err_msg:-Connection failed.}"
        fi
        exit 1
    fi
    ;;
esac
