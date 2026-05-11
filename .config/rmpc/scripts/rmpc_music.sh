#!/bin/bash

# 0. Quick bypass for informative flags (no MPD needed)
if [[ "$1" == "--version" || "$1" == "-V" || "$1" == "--help" || "$1" == "-h" ]]; then
  command rmpc "$@"
  exit 0
fi

STARTED_MPD=0
MPD_CACHE_DIR="$HOME/.cache/mpd"

# 1. Pre-flight checks (Idempotent setup for migration)
if [[ ! -d "$MPD_CACHE_DIR" ]]; then
  echo "Creating missing MPD cache directory at $MPD_CACHE_DIR..."
  mkdir -p "$MPD_CACHE_DIR"
fi

# 2. Start MPD if it's not running
if ! pgrep -x "mpd" >/dev/null; then
  echo "Starting MPD..."
  mpd
  STARTED_MPD=1

  # Wait for MPD to be ready
  for i in {1..10}; do
    # 'nc -z' checks if port is open without sending data
    if nc -z 127.0.0.1 6600 >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done
else
  echo "MPD is already running."
fi

# 3. Launch the client with all passed flags/arguments
# Using 'command' prevents infinite loops with your zsh alias
command rmpc "$@"

# 4. Cleanup: Kill MPD *only* if this script was the one that started it
if [ $STARTED_MPD -eq 1 ]; then
  echo "Stopping MPD..."
  pkill -x mpd
fi
