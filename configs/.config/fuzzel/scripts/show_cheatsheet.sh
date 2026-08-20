#!/usr/bin/env bash
# =============================================================================
# Hyprland Keybinding Cheatsheet
# =============================================================================
# This script dynamically pulls keybindings from 'hyprctl'
# and displays them in a searchable fuzzel menu.
# It prioritizes descriptions from 'bindd'/'bindde' lines.
# =============================================================================

# This map is used to translate keycodes (e.g., code:123) to symbols
# (e.g., Up) if 'hyprctl' provides a code but not a key name.
declare -A KEYCODE_SYM_MAP

# Populates the KEYCODE_SYM_MAP by parsing your local xkb keymap.
build_keymap_cache() {
  local keymap
  keymap="$(xkbcli compile-keymap)" || {
    echo "Failed to compile keymap" >&2
    return 1
  }

  while IFS=, read -r code sym; do
    [[ -z "$code" || -z "$sym" ]] && continue
    KEYCODE_SYM_MAP["$code"]="$sym"
  done < <(
    awk '
      BEGIN { sec = "" }
      /xkb_keycodes/ { sec = "codes"; next }
      /xkb_symbols/  { sec = "syms";  next }
      sec == "codes" {
        if (match($0, /<([A-Za-z0-9_]+)>\s*=\s*([0-9]+)\s*;/, m)) code_by_name[m[1]] = m[2]
      }
      sec == "syms" {
        if (match($0, /key\s*<([A-Za-z0-9_]+)>\s*\{\s*\[\s*([^, \]]+)/, m)) sym_by_name[m[1]] = m[2]
      }
      END {
        for (k in code_by_name) {
          c = code_by_name[k]
          s = sym_by_name[k]
          if (c != "" && s != "" && s != "NoSymbol") print c "," s
        }
      }
    ' <<<"$keymap"
  )
}

# Looks up a keycode from the cache.
lookup_keycode_cached() {
  printf '%s\n' "${KEYCODE_SYM_MAP[$1]}"
}

# Replaces 'code:XXX' or 'mouse:XXX' with a human-readable name.
parse_keycodes() {
  while IFS= read -r line; do
    if [[ "$line" =~ code:([0-9]+) ]]; then
      code="${BASH_REMATCH[1]}"
      symbol=$(lookup_keycode_cached "$code")
      echo "${line/code:${code}/$symbol}"
    elif [[ "$line" =~ mouse:([0-9]+) ]]; then
      code="${BASH_REMATCH[1]}"

      case "$code" in
        272) symbol="LMB" ;;  # Left Mouse Button
        273) symbol="RMB" ;;  # Right Mouse Button
        274) symbol="MMB" ;;  # Middle Mouse Button
        *)   symbol="mouse:${code}" ;;
      esac

      echo "${line/mouse:${code}/$symbol}"
    else
      echo "$line"
    fi
  done
}

# Fetch dynamic keybindings from Hyprland.
# This formats the 'hyprctl' JSON output into a simple CSV-like format
# and maps the numeric modifier mask (e.g., 64) to a text name (e.g., SUPER,).
dynamic_bindings() {
  hyprctl -j binds |
    jq -r '.[] | {modmask, key, keycode, description, dispatcher, arg} | "\(.modmask),\(.key)@\(.keycode),\(.description),\(.dispatcher),\(.arg)"' |
    sed -r \
      -e 's/null//' \
      -e 's/@0//' \
      -e 's/,@/,code:/' \
      -e 's/^0,/,/' \
      -e 's/^1,/SHIFT,/' \
      -e 's/^4,/CTRL,/' \
      -e 's/^5,/SHIFT CTRL,/' \
      -e 's/^8,/ALT,/' \
      -e 's/^9,/SHIFT ALT,/' \
      -e 's/^12,/CTRL ALT,/' \
      -e 's/^13,/SHIFT CTRL ALT,/' \
      -e 's/^64,/SUPER,/' \
      -e 's/^65,/SUPER SHIFT,/' \
      -e 's/^68,/SUPER CTRL,/' \
      -e 's/^69,/SUPER SHIFT CTRL,/' \
      -e 's/^72,/SUPER ALT,/' \
      -e 's/^73,/SUPER SHIFT ALT,/' \
      -e 's/^76,/SUPER CTRL ALT,/' \
      -e 's/^77,/SUPER SHIFT CTRL ALT,/'
}

# Parse and format keybindings
# This 'awk' script does the heavy lifting:
# 1. Joins mod + key (e.g., "SUPER + Q").
# 2. Checks if a description ($3) exists.
# 3. If YES: Use the description as the action.
# 4. If NO: Reconstruct the command (e.g., "exec, kitty") as the action.
# 5. Prints the formatted line.
parse_bindings() {
  awk -F, '
{
    # Combine the modifier and key (first two fields)
    key_combo = $1 " + " $2;

    # Clean up: strip leading "+" if present, trim spaces
    gsub(/^[ \t]*\+?[ \t]*/, "", key_combo);
    gsub(/[ \t]+$/, "", key_combo);

    # Use description ($3), if set
    action = $3;

    # If description is empty, build action from dispatcher+arg
    if (action == "") {
        # Reconstruct the command from the remaining fields
        for (i = 4; i <= NF; i++) {
            action = action $i (i < NF ? "," : "");
        }

        # Clean up trailing commas, remove leading "exec, ", and trim
        sub(/,$/, "", action);
        gsub(/(^|,)[[:space:]]*exec[[:space:]]*,?/, "", action);
        gsub(/^[ \t]+|[ \t]+$/, "", action);
        gsub(/[ \t]+/, " ", key_combo);  # Collapse multiple spaces to one
    }

    if (action != "") {
        printf "%-35s → %s\n", key_combo, action;
    }
}'
}

# Gives a priority number to certain entries so they appear
# higher in the list. (e.g., 'Terminal' gets priority 0).
prioritize_entries() {
  awk '
  {
    line = $0
    prio = 50  # Default priority

    if (match(line, /Terminal/)) prio = 0
    if (match(line, /Browser/) && !match(line, /Browser[[:space:]]*\(/)) prio = 1
    if (match(line, /File Manager/))  prio = 2
    if (match(line, /Launch App/))  prio = 3
    if (match(line, /System Menu/))  prio = 5
    if (match(line, /Power Menu/))   prio = 6
    if (match(line, /Full Screen/))  prio = 7
    if (match(line, /Close Window/))  prio = 8
    if (match(line, /Toggle.*Floating/)) prio = 9
    if (match(line, /Toggle.*Split/))  prio = 10
    if (match(line, /Clipboard/))  prio = 12
    if (match(line, /Color Picker/))  prio = 14
    if (match(line, /Screenshot/))  prio = 15
    if (match(line, /Screenrecording/))  prio = 16
    if (match(line, /(Switch|Next|Former|Previous).*Workspace/)) prio = 17
    if (match(line, /Move Window to Workspace/)) prio = 18
    if (match(line, /Move Window Focus/)) prio = 20
    if (match(line, /Move Window$/))  prio = 21
    if (match(line, /Resize Window/)) prio = 22
    if (match(line, /Scratchpad/))  prio = 25
    if (match(line, /Notification/))  prio = 26
    if (match(line, /Toggle.*Night Light/)) prio = 29
    if (match(line, /XF86/)) prio = 99 # Media keys

    # print "priority<TAB>line"
    printf "%d\t%s\n", prio, line
  }' |
    sort -k1,1n -k2,2 | # Sort by priority, then alphabetically
    cut -f2-            # Remove the priority number
}

# =============================================================================
# Main Execution
# =============================================================================

# 1. Build the keycode-to-symbol map
build_keymap_cache

# 2. Run the processing pipeline
dynamic_bindings |      # Get binds from 'hyprctl'
  sort -u |             # Remove duplicates
  parse_keycodes |      # Translate keycodes (e.g., code:272 -> LMB)
  parse_bindings |      # Format as "Key → Action"
  prioritize_entries |  # Sort with important binds at the top
  fuzzel \
    --dmenu \
    --prompt "🔍 Keybindings: " \
    --lines 20 \
    --width 85 \
    --font "monospace:size=11"
  # Add your old color flags here if you want!
  # --background "1e1e2eDD" \
  # --text-color "cdd6f4FF" \