#!/bin/bash
# Returns a JSON signal only during the first 2 seconds of the day
current_time=$(date +%H%M%S)

if [ "$current_time" -ge "000000" ] && [ "$current_time" -le "000002" ]; then
  # Class 'alert' triggers the CSS animation
  echo '{"text": " 󰃭 NEW DAY ", "class": "alert"}'
else
  # Empty text hides the module completely
  echo '{"text": "", "class": ""}'
fi
