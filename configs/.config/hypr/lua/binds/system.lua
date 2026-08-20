--//================================================================//
--//                    SYSTEM BINDS                                //
--//  Volume, brightness, nightlight, media, screenshots,           //
--//  clipboard, power menu, zoom, snappy tools, wayscriber.        //
--//================================================================//

local v = require("lua.core.variables")
-- local window_ss = require("lua.utils.smart_screenshot")
--*================================================================*--
--                        SYSTEM RELOAD                              --
--*================================================================*--

hl.bind(
    "SUPER + CTRL + R",
    hl.dsp.exec_cmd("hyprctl reload && notify-send -t 2000 '(>////<) Hyprland Reloaded'"),
    { description = "Reload Hyprland" }
)

--*================================================================*--
--                        LOCKSCREEN                                 --
--*================================================================*--

hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock --quiet"), { description = "Lock Screen" })

--*================================================================*--
--                       VOLUME CONTROL                              --
--*================================================================*--

--- Testing Aurisd ---
hl.bind(
    "SUPER + ALT + F",
    hl.dsp.exec_cmd("aurisd --up"),
    { description = "Volume Up", locked = true, repeating = true }
)

hl.bind(
    "SUPER + ALT + D",
    hl.dsp.exec_cmd("aurisd --down"),
    { description = "Volume Up", locked = true, repeating = true }
)

hl.bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd(v.ctl_script .. " up"),
    { description = "Volume Up", locked = true, repeating = true }
)

hl.bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(v.ctl_script .. " down"),
    { description = "Volume Down", locked = true, repeating = true }
)

hl.bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd(v.ctl_script .. " mute"),
    { description = "Toggle Mute", locked = true, repeating = true }
)

--*================================================================*--
--                     BRIGHTNESS CONTROL                            --
--*================================================================*--

-- Laptop function keys
hl.bind(
    "XF86MonBrightnessUp",
    hl.dsp.exec_cmd(v.ctl_script .. " brightness_up"),
    { description = "Brightness Up", locked = true, repeating = true }
)

hl.bind(
    "XF86MonBrightnessDown",
    hl.dsp.exec_cmd(v.ctl_script .. " brightness_down"),
    { description = "Brightness Down", locked = true, repeating = true }
)

-- External keyboard (CTRL+F1/F2)
hl.bind(
    "CTRL + F2",
    hl.dsp.exec_cmd(v.ctl_script .. " brightness_up"),
    { description = "Brightness Up", repeating = true }
)

hl.bind(
    "CTRL + F1",
    hl.dsp.exec_cmd(v.ctl_script .. " brightness_down"),
    { description = "Brightness Down", repeating = true }
)

--*================================================================*--
--                      MEDIA CONTROLS                               --
--*================================================================*--

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })

--*================================================================*--
--                      NIGHT LIGHT                                  --
--*================================================================*--

local nightlight_script = v.home .. "/.config/waybar/scripts/nightlight_control.sh"

hl.bind("SUPER + N", hl.dsp.exec_cmd(nightlight_script), { description = "Toggle Night Light" })

hl.bind(
    "SUPER + ALT + 2",
    hl.dsp.exec_cmd(nightlight_script .. " increase"),
    { description = "Night Light (Cooler)", repeating = true }
)

hl.bind(
    "SUPER + ALT + 1",
    hl.dsp.exec_cmd(nightlight_script .. " decrease"),
    { description = "Night Light (Warmer)", repeating = true }
)

--*================================================================*--
--                      SCREENSHOTS                                  --
--*================================================================*--

local ss_dir = v.screenshot_dir
local ss_sound = v.screenshot_sound
local rofi_ss = v.home .. "/.config/rofi/scripts/sidebar-screenshot.sh"

-- Screenshot/Record menu
hl.bind("Print", hl.dsp.exec_cmd(rofi_ss), { description = "Screenshot/Record Menu" })
hl.bind("SUPER + SHIFT + s", hl.dsp.exec_cmd(rofi_ss), { description = "Screenshot/Record Menu" })

-- Full screen → clipboard
hl.bind(
    "SUPER + Print",
    hl.dsp.exec_cmd(
        "grim - | wl-copy && paplay "
        .. ss_sound
        .. " && notify-send -t 2000 'Screenshot Copied' 'Full screen image copied to clipboard.'"
    ),
    { description = "Full Screenshot Copy" }
)

-- Area → save to file
hl.bind(
    "SHIFT + Print",
    hl.dsp.exec_cmd(
        'grim -g "$(slurp)" "'
        .. ss_dir
        .. "/$(date +'%Y-%m-%d_%H-%M-%S').png\""
        .. " && paplay "
        .. ss_sound
        .. " && notify-send -t 2000 'Screenshot Saved' 'Selected area saved to Hyprland Screenshots.'"
    ),
    { description = "Area Screenshot Save" }
)

-- Area → clipboard
hl.bind(
    "CTRL + Print",
    hl.dsp.exec_cmd(
        'grim -g "$(slurp)" - | wl-copy && paplay '
        .. ss_sound
        .. " && notify-send -t 2000 'Screenshot Copied' 'Selected area copied to clipboard.'"
    ),
    { description = "Area Screenshot Copy" }
)

-- Alternative Area → clipboard
hl.bind(
    "SUPER + CTRL + s",
    hl.dsp.exec_cmd(
        'grim -g "$(slurp)" - | wl-copy && paplay '
        .. ss_sound
        .. " && notify-send -t 2000 'Screenshot Copied' 'Selected area copied to clipboard.'"
    ),
    { description = "Area Screenshot Copy" }
)

-- Focused Monitor → clipboard
hl.bind(
    "SUPER + s",
    hl.dsp.exec_cmd(
        "grim -o \"$(hyprctl activeworkspace -j | jq -r '.monitor')\" - | wl-copy && paplay "
        .. ss_sound
        .. " && notify-send -t 2000 'Screenshot Copied' 'Focused monitor copied to clipboard.'"
    ),
    { description = "Quick Focused Monitor Screenshot Copy" }
)

-- Focused Monitor → save to file
hl.bind(
    "SUPER + ALT + x", -- Or whichever key you prefer
    hl.dsp.exec_cmd(
        'grim -o "$(hyprctl activeworkspace -j | jq -r \'.monitor\')" "'
        .. ss_dir
        .. "/$(date +'%Y-%m-%d_%H-%M-%S').png\""
        .. " && paplay "
        .. ss_sound
        .. " && notify-send -t 2000 'Screenshot Saved' 'Focused monitor saved to Hyprland Screenshots.'"
    ),
    { description = "Focused Monitor Screenshot Save" }
)

hl.bind(
    "SUPER + SHIFT + x",
    hl.dsp.exec_cmd(
        'grim -g "$(slurp)" "'
        .. ss_dir
        .. "/$(date +'%Y-%m-%d_%H-%M-%S').png\""
        .. " && paplay "
        .. ss_sound
        .. " && notify-send -t 2000 'Screenshot Saved' 'Selected area saved to Hyprland Screenshots.'"
    ),
    { description = "Area Screenshot Save" }
)


-- Window → clipboard (via hyprshot)
hl.bind(
    "ALT + w",
    hl.dsp.exec_cmd(
        "hyprshot -m window --clipboard-only"
        .. " && paplay "
        .. ss_sound
        .. " && notify-send -t 2000 'Screenshot Copied' 'Window copied to clipboard.'"
    ),
    { description = "Select Window to Copy (hyprshot)" }
)

--*================================================================*--
--                     CLIPBOARD & UTILITIES                         --
--*================================================================*--

-- Color picker
hl.bind(
    "SUPER + SHIFT + C",
    hl.dsp.exec_cmd(v.home .. "/.config/waybar/scripts/picker.sh"),
    { description = "Color Picker" }
)

-- Clipboard history (Rofi)
hl.bind(
    "SUPER + SHIFT + V",
    hl.dsp.exec_cmd(v.home .. "/.config/rofi/scripts/cliphist-rofi.py"),
    { description = "Clipboard History" }
)

-- Power menu
hl.bind(
    "SUPER + ALT + S",
    hl.dsp.exec_cmd(v.home .. "/.config/fuzzel/scripts/powermenu.sh"),
    { description = "Power Menu" }
)

-- Keybinding cheatsheet
hl.bind(
    "SUPER + Escape",
    hl.dsp.exec_cmd(v.home .. "/.config/fuzzel/scripts/show_cheatsheet.sh"),
    { description = "Show Keybinds" }
)

--*================================================================*--
--                    MAGNIFICATION / ZOOM                           --
--        (Ported from awk to native Lua — zero IPC overhead)        --
--*================================================================*--

hl.bind("SUPER + ALT + mouse_down", function()
    local current = hl.get_config("cursor.zoom_factor")
    if current < 1 then
        current = 1
    end
    hl.config({ cursor = { zoom_factor = current * 1.25 } })
end)

hl.bind("SUPER + ALT + mouse_up", function()
    local current = hl.get_config("cursor.zoom_factor")
    if current < 1 then
        current = 1
    end
    local new_zoom = current / 1.25
    if new_zoom < 1 then
        new_zoom = 1.0
    end
    hl.config({ cursor = { zoom_factor = new_zoom } })
end)

-- Reset zoom to 1.0x with mouse side button
hl.bind("SUPER + ALT + mouse:276", function()
    hl.config({ cursor = { zoom_factor = 1.0 } })
end)

--*================================================================*--
--                    SNAPPY TOOLS & WAYSCRIBER                      --
--*================================================================*--

-- Snappy Switcher (Alt+Tab)

-- Alt+Tab (standard MRU)
hl.bind("ALT + Tab", hl.dsp.exec_cmd("snappy-switcher next --mod alt"))

-- Super+Tab (workspace-filtered)
hl.bind("SUPER + TAB", hl.dsp.exec_cmd("snappy-switcher next --workspace --mod super"))

-- Snappy Keys
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("snappy-keys --toggle"), { description = "Snappy Keys Toggle On" })
hl.bind("SUPER + ALT + J", hl.dsp.exec_cmd("snappy-keys --toggle"), { description = "Snappy Keys Force Toggle Off" })

-- Qucikshell (OverView)
hl.bind(
    "ALT + SHIFT + TAB",
    hl.dsp.exec_cmd("qs ipc -c overview call overview toggle"),
    { description = "Qucikshell OverView" }
)
-- Wayscriber
hl.bind("SUPER + D", hl.dsp.exec_cmd("wayscriber --daemon-toggle"), { description = "Wayscriber Toggle" })
