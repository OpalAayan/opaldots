#!/bin/bash

# 1. Edge Case: Exit silently if no input is provided
[[ -z "$1" ]] && exit 0

ws="$1"
icons=("" "󰲠" "󰲢" "󰲤" "󰲦" "󰲨" "󰲪" "󰲬" "󰲮" "󰲰" "󰿬")

# 2. Standard Workspaces: Check if the input is a pure number
if [[ "$ws" =~ ^[0-9]+$ ]]; then

  # Force Base-10 evaluation to avoid the Bash "Octal Trap" (e.g., '08' breaking the script)
  num=$((10#$ws))

  # Check if within array bounds (1-10)
  if ((num >= 1 && num <= 10)); then
    echo "${icons[$num]}"
  else
    echo "$num" # Infinity condition
  fi

# 3. Special Workspaces
elif [[ "$ws" == special:* ]]; then

  # Strip the prefix
  name="${ws#special:}"

  # Edge Case: The special workspace somehow has no name after the prefix
  if [[ -z "$name" ]]; then
    echo "S"
  else
    # Grab first letter and uppercase it using native Bash (faster than 'tr')
    first_letter="${name:0:1}"
    echo "S ${first_letter^^}"
  fi

# 4. Fallback for custom named workspaces (e.g., "gaming", "browser")
else
  # Edge Case/Enhancement: Capitalize the first letter of named workspaces automatically
  first_letter="${ws:0:1}"
  rest_of_word="${ws:1}"
  echo "${first_letter^^}${rest_of_word}"
fi
