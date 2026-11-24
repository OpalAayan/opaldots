#!/usr/bin/env bash
#
# smart-mirrors.sh — refresh /etc/pacman.d/mirrorlist
# Auto-detects your country via IP, ranks mirrors there by real speed,
# and widens to a global search if that's thin or detection fails.
#
# Usage: smart-mirrors.sh [quick|hardy]
#   quick -> top 5 mirrors   (fast)
#   hardy -> top 15 mirrors  (thorough)

set -euo pipefail

# self-elevate, keeping args intact — so the alias doesn't need "sudo" in it
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

MIRRORLIST="/etc/pacman.d/mirrorlist"
BACKUP="${MIRRORLIST}.bak.$(date +%Y%m%d%H%M%S)"
MODE="${1:-quick}"

case "$MODE" in
quick | quicky) COUNT=5 ;;
hardy) COUNT=15 ;;
*)
    echo "Usage: $(basename "$0") [quick|hardy]" >&2
    exit 1
    ;;
esac

command -v reflector &>/dev/null || {
    echo "reflector not installed: sudo pacman -S reflector" >&2
    exit 1
}

# --- country detection: 3 keyless fallbacks, first valid 2-letter code wins
detect_country() {
    local c

    c=$(curl -s --max-time 4 https://ipapi.co/country/ 2>/dev/null || true)
    if [[ "$c" =~ ^[A-Za-z]{2}$ ]]; then
        printf '%s' "$c"
        return 0
    fi

    c=$(curl -s --max-time 4 https://ifconfig.co/country-iso 2>/dev/null || true)
    if [[ "$c" =~ ^[A-Za-z]{2}$ ]]; then
        printf '%s' "$c"
        return 0
    fi

    c=$(curl -s --max-time 4 https://api.country.is/ 2>/dev/null | grep -oP '"country":"\K[A-Z]{2}' || true)
    if [[ "$c" =~ ^[A-Za-z]{2}$ ]]; then
        printf '%s' "$c"
        return 0
    fi

    return 0
}

COUNTRY=""
if command -v curl &>/dev/null; then
    echo "Detecting country..."
    COUNTRY=$(detect_country)
fi

if [[ -n "$COUNTRY" ]]; then
    echo "Detected: $COUNTRY"
else
    echo "Couldn't detect country — going global."
fi

if cp "$MIRRORLIST" "$BACKUP" 2>/dev/null; then
    echo "Backed up mirrorlist -> $BACKUP"
fi

mirror_count() { grep -c "^Server" "$MIRRORLIST" 2>/dev/null || true; }

COMMON=(--protocol https --connection-timeout 3 --download-timeout 4 --sort rate --number "$COUNT" --save "$MIRRORLIST")

DONE=0
if [[ -n "$COUNTRY" ]]; then
    echo "Testing mirrors in $COUNTRY..."
    if reflector --country "$COUNTRY" "${COMMON[@]}" && [[ "$(mirror_count)" -ge 3 ]]; then
        DONE=1
    else
        echo "Country search came up short — widening to global."
    fi
fi

if [[ "$DONE" -ne 1 ]]; then
    echo "Testing global mirrors (freshest 30 candidates)..."
    reflector --latest 30 "${COMMON[@]}"
fi

N="$(mirror_count)"
if [[ "$N" -eq 0 ]]; then
    echo "Nothing usable came back — restoring old mirrorlist." >&2
    if [[ -f "$BACKUP" ]]; then
        cp "$BACKUP" "$MIRRORLIST"
    fi
    exit 1
fi

echo "Done — $N mirrors saved to $MIRRORLIST"
