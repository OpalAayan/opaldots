#!/bin/bash

# 0. Quick bypass for informative flags (no MPD needed)
if [[ "$1" == "--version" || "$1" == "-V" || "$1" == "--help" || "$1" == "-h" ]]; then
  rmpc "$@"
  exit 0
fi

STARTED_MPD=0

# 1. Start MPD if it's not running
if ! pgrep -x "mpd" >/dev/null; then
  echo "Starting MPD..."
  mpd
  STARTED_MPD=1

  # Wait for MPD to be ready
  for i in {1..10}; do
    # 'nc -z' is the standard way to just check if a port is open without sending data
    if nc -z 127.0.0.1 6600 >/dev/null 2>&1; then
      break
    fi
    sleep 0.5
  done
else
  echo "MPD is already running."
fi

# 2. Launch the client with all passed flags/arguments
rmpc "$@"

# 3. Cleanup: Kill MPD *only* if this script was the one that started it
if [ $STARTED_MPD -eq 1 ]; then
  echo "Stopping MPD..."
  pkill -x mpd
fi

