#!/usr/bin/env bash

# Check for dependencies
if ! command -v gawk &>/dev/null; then
  notify-send "Error" "gawk is missing. Please install it (sudo pacman -S gawk)"
  exit 1
fi

thumbnail_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/thumbnails"
[ -d "$thumbnail_dir" ] || mkdir -p "$thumbnail_dir"

# Read cliphist list
cliphist_list=$(cliphist list)
if [ -z "$cliphist_list" ]; then
  notify-send "Clipboard" "History is empty"
  exit
fi

# GAWK script to handle thumbnails
# It checks if a line is an image, generates a thumb if missing, and appends the icon code for fuzzel
read -r -d '' gawk_script <<EOF
# Skip metadata lines
/^[0-9]+\s<meta http-equiv=/ { next }

# Match image entries (binary data)
match(\$0, /^([0-9]+)\s(\[\[\s)?binary.*(jpg|jpeg|png|bmp)/, grp) {
    cliphist_item_id=grp[1]
    ext=grp[3]
    thumbnail_file=cliphist_item_id"."ext
    full_path="${thumbnail_dir}/"thumbnail_file
    
    # If thumbnail doesn't exist, decode it from cliphist
    cmd="[ -f "full_path" ] || echo "cliphist_item_id" | cliphist decode > "full_path
    system(cmd)
    
    # Print the line with the special icon delimiter for fuzzel
    print \$0"\0icon\x1f"full_path
    next
}
# Print non-image lines normally
1
EOF

# Run fuzzel
# We pass the gawk script and customize fuzzel options here
item=$(echo "$cliphist_list" | gawk "$gawk_script" | fuzzel -d \
  --placeholder "Search Clipboard..." \
  --width 60 \
  --lines 15 \
  --no-sort \
  --with-nth 2) # Hides the ID (column 1) from view

exit_code=$?

# --- Handle Actions ---

# 1. Normal Selection (Enter)
if [ "$exit_code" -eq 0 ] && [ -n "$item" ]; then
  echo "$item" | cliphist decode | wl-copy
  notify-send "Clipboard" "Item copied to clipboard"

# 2. Delete Item (Alt+1 or Ctrl+Delete depending on fuzzel config)
# You need to set 'custom-1' in fuzzel.ini to a keybind (e.g., Mod1+d) to use this
elif [ "$exit_code" -eq 10 ] && [ -n "$item" ]; then
  item_id=$(echo "$item" | cut -f1 -d' ')
  echo "$item_id" | cliphist delete
  # Clean up the thumbnail
  find "$thumbnail_dir" -name "${item_id}.*" -delete
  notify-send "Clipboard" "Item deleted"

# 3. Wipe History (Alt+0 or custom-19)
elif [ "$exit_code" -eq 19 ]; then
  if echo -e "No\nYes" | fuzzel -d --prompt-only "Clear Entire History?" | grep -q "Yes"; then
    cliphist wipe
    rm -rf "$thumbnail_dir"
    notify-send "Clipboard" "History cleared"
  fi
fi

# Maintenance: Remove old thumbnails for items no longer in history
# (Runs in background)
(
  current_ids=$(cliphist list | cut -d' ' -f1)
  for file in "$thumbnail_dir"/*; do
    [ -f "$file" ] || continue
    fname=$(basename "$file")
    id="${fname%.*}"
    if ! echo "$current_ids" | grep -q "^$id$"; then
      rm "$file"
    fi
  done
) &
