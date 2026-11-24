#!/bin/bash
# Returns a signal during the first 2 seconds of the day
current_time=$(date +%H%M%S)

if [[ "$1" == "check" ]]; then
  if [ "$current_time" -ge "000000" ] && [ "$current_time" -le "000002" ]; then
    exit 0
  else
    exit 1
  fi
fi

if [ "$current_time" -ge "000000" ] && [ "$current_time" -le "000002" ]; then
  if [[ "$1" == "json" ]]; then
    echo '{"text": " 󰃭 NEW DAY ", "class": "alert"}'
  else
    echo " 󰃭 NEW DAY "
  fi
else
  if [[ "$1" == "json" ]]; then
    echo '{"text": "", "class": ""}'
  else
    echo ""
  fi
fi
