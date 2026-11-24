#!/usr/bin/env python3

import sys
import os
import subprocess
import re
import html
import shutil
import json

# --- Configuration ---
CACHE_DIR = os.path.expanduser("~/.cache/cliphist/thumbnails")
RASI_FILE = os.path.expanduser("~/.config/rofi/clipboard/clipboard.rasi")
PINNED_FILE = os.path.expanduser("~/.cache/cliphist/pinned.json")
TEXT_ICON = "text-x-generic"
PIN_ICON = "<span foreground='#E59BD2' font='14'>󰐃 </span>"
MAX_TEXT_LEN = 60

os.makedirs(CACHE_DIR, exist_ok=True)
os.makedirs(os.path.dirname(PINNED_FILE), exist_ok=True)


# --- Pin State Management ---

def load_pinned():
    """Load pinned IDs from disk. Returns a set of clip ID strings."""
    try:
        with open(PINNED_FILE, 'r') as f:
            data = json.load(f)
            return set(data) if isinstance(data, list) else set()
    except (FileNotFoundError, json.JSONDecodeError):
        return set()

def save_pinned(pinned_set):
    """Persist the pinned set to disk."""
    with open(PINNED_FILE, 'w') as f:
        json.dump(sorted(pinned_set), f)

def toggle_pin(clip_id):
    """Toggle a clip ID in/out of the pinned set. Returns new state."""
    pinned = load_pinned()
    if clip_id in pinned:
        pinned.discard(clip_id)
        state = False
    else:
        pinned.add(clip_id)
        state = True
    save_pinned(pinned)
    return state

def remove_pinned(clip_id):
    """Remove a single ID from pinned storage if present."""
    pinned = load_pinned()
    if clip_id in pinned:
        pinned.discard(clip_id)
        save_pinned(pinned)

def clear_pinned():
    """Wipe the entire pinned file."""
    save_pinned(set())


# --- Utilities ---

def get_cliphist_items():
    result = subprocess.run(['cliphist', 'list'], capture_output=True, text=True)
    return result.stdout.strip().splitlines()

def send_notification(title, message):
    subprocess.run(['notify-send', '-t', '1600', '-u', 'normal', title, message])

def clean_cache(current_ids):
    try:
        for filename in os.listdir(CACHE_DIR):
            file_id = filename.split('.')[0]
            if file_id not in current_ids and file_id.isdigit():
                path = os.path.join(CACHE_DIR, filename)
                os.remove(path)
    except Exception as e:
        print(f"Cache clean error: {e}")

def relaunch():
    """Re-execute this script to refresh the UI."""
    os.execv(sys.executable, ['python3'] + sys.argv)


# --- Main ---

def main():
    raw_lines = get_cliphist_items()
    pinned_set = load_pinned()

    pinned_items = []
    unpinned_items = []
    current_ids = set()

    for line in raw_lines:
        # --- Image detection ---
        match_img = re.search(r'^(\d+)\s+(?:\[\[\s+)?binary.*(jpg|jpeg|png|bmp)', line)

        if match_img:
            clip_id = match_img.group(1)
            ext = match_img.group(2)
            current_ids.add(clip_id)

            filename = f"{clip_id}.{ext}"
            path = os.path.join(CACHE_DIR, filename)

            if not os.path.exists(path):
                with open(path, 'wb') as f:
                    subprocess.run(['cliphist', 'decode', clip_id], stdout=f)

            is_pinned = clip_id in pinned_set
            prefix = PIN_ICON if is_pinned else ""
            display_text = f"{prefix}<b>Image</b>"

            entry = {'id': clip_id, 'type': 'image', 'raw': line,
                     'display': display_text, 'icon': path, 'pinned': is_pinned}

            (pinned_items if is_pinned else unpinned_items).append(entry)

        else:
            # --- Text detection ---
            match_text = re.search(r'^(\d+)\s+(.*)', line)
            if match_text:
                clip_id = match_text.group(1)
                content = match_text.group(2)
                current_ids.add(clip_id)

                display_content = (content[:MAX_TEXT_LEN] + '...') if len(content) > MAX_TEXT_LEN else content
                safe_content = html.escape(display_content).replace("\n", " ")

                is_pinned = clip_id in pinned_set
                prefix = PIN_ICON if is_pinned else ""
                display_text = f"{prefix}{safe_content}"

                entry = {'id': clip_id, 'type': 'text', 'raw': line,
                         'display': display_text, 'icon': TEXT_ICON, 'pinned': is_pinned}

                (pinned_items if is_pinned else unpinned_items).append(entry)

    # Prune orphaned pins (items that no longer exist in cliphist)
    orphans = pinned_set - current_ids
    if orphans:
        save_pinned(pinned_set - orphans)

    clean_cache(current_ids)

    # Sort: pinned first, then unpinned — both preserve cliphist order
    parsed_items = pinned_items + unpinned_items

    # Build rofi input
    rofi_input = ""
    for item in parsed_items:
        rofi_input += f"{item['display']}\0icon\x1f{item['icon']}\n"

    # --- Run Rofi ---
    rofi_cmd = [
        'rofi',
        '-dmenu',
        '-config', RASI_FILE,
        '-i',
        '-show-icons',
        '-markup-rows',
        '-format', 'i',
        '-kb-custom-1', 'Alt+1',    # Wipe All
        '-kb-custom-2', 'Alt+d',    # Delete Item
        '-kb-custom-3', 'Alt+p',    # Toggle Pin
        '-mesg', 'Alt+d: Delete | Alt+1: Wipe All | Alt+p: Pin/Unpin'
    ]

    proc = subprocess.run(rofi_cmd, input=rofi_input, text=True, capture_output=True)

    exit_code = proc.returncode
    selection_index = proc.stdout.strip()

    # --- Handle Copy (Enter) ---
    if exit_code == 0 and selection_index.isdigit():
        idx = int(selection_index)
        if 0 <= idx < len(parsed_items):
            item = parsed_items[idx]
            subprocess.run(f"cliphist decode {item['id']} | wl-copy", shell=True)

            msg = "Image Copied 🖼️" if item['type'] == 'image' else "Text Copied 📝"
            send_notification("Clipboard", msg)

    # --- Handle Single Delete (Alt+d, exit code 11) ---
    elif exit_code == 11 and selection_index.isdigit():
        idx = int(selection_index)
        if 0 <= idx < len(parsed_items):
            item = parsed_items[idx]

            subprocess.run(['cliphist', 'delete'], input=item['raw'], text=True)
            remove_pinned(item['id'])

            send_notification("Clipboard", "Item Deleted 🗑️")
            relaunch()

    # --- Handle Toggle Pin (Alt+p, exit code 12) ---
    elif exit_code == 12 and selection_index.isdigit():
        idx = int(selection_index)
        if 0 <= idx < len(parsed_items):
            item = parsed_items[idx]
            now_pinned = toggle_pin(item['id'])

            emoji = "📌" if now_pinned else "📍"
            verb = "Pinned" if now_pinned else "Unpinned"
            send_notification("Clipboard", f"{verb} {emoji}")
            relaunch()

    # --- Handle Wipe All (Alt+1, exit code 10) ---
    elif exit_code == 10:
        confirm_rofi = ['rofi', '-dmenu', '-config', RASI_FILE, '-p', '⚠️ WIPE ALL?', '-mesg', 'Irreversible action.']
        res = subprocess.run(confirm_rofi, input="Yes, Wipe\nNo, Cancel", text=True, capture_output=True)

        if "Yes" in res.stdout:
            subprocess.run(['cliphist', 'wipe'])
            if os.path.exists(CACHE_DIR):
                shutil.rmtree(CACHE_DIR)
                os.makedirs(CACHE_DIR)
            clear_pinned()
            send_notification("Clipboard", "History Wiped 🗑️")


if __name__ == "__main__":
    main()
