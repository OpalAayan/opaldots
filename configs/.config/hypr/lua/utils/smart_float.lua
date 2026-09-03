--//================================================================//
--//                     SMART FLOAT                                //
--//  Ported from smart_float.sh — zero IPC overhead.               //
--//                                                                //
--//  Logic:                                                        //
--//   1. If window is fullscreen → unset fullscreen & float it     //
--//   2. If already floating → toggle back to tiled                //
--//   3. If tiled → float + check float_sizes table                //
--//   4. If custom size found → resize exact + center              //
--//================================================================//

local M = {}

-- ── Custom Float Sizes ──
-- Format: ["window_class"] = { width, height }
-- To find a window's class: hyprctl clients | grep "class:"
local float_sizes = {
    -- Terminals
    ["kitty"] = { 986, 576 },
    ["Alacritty"] = { 900, 510 },
    -- Browsers
    ["brave-browser"] = { 1000, 540 },
    ["firefox"] = { 1000, 550 },
    -- File Managers
    ["org.gnome.Nautilus"] = { 900, 550 },
    ["org.gnome.baobab"] = { 900, 550 },
    -- Apps
    ["code"] = { 1200, 600 },
    ["steam"] = { 940, 500 },
    ["org.gnome.Calculator"] = { 100, 200 },
    ["blueberry.py"] = { 600, 500 },
    ["virt-manager"] = { 900, 500 },
    ["com.mitchellh.ghostty"] = { 986, 546 },
    ["bluej.Boot$App"] = { 900, 600 },
    ["org.gnome.TextEditor"] = { 700, 600 },
}

--- Toggle smart float for the active window.
--- If the window is fullscreen, it exits fullscreen and enters float mode.
--- If the window has a custom size in float_sizes, it will be resized and centered.
function M.toggle()
    local w = hl.get_active_window()
    if not w then
        return
    end

    -- Handles both boolean and integer representations of fullscreen mode
    local is_fullscreen = w.fullscreen and (w.fullscreen == true or w.fullscreen > 0)

    if is_fullscreen then
        -- 1. Fullscreen -> Exit fullscreen and force floating
        hl.dispatch(hl.dsp.window.fullscreen({ action = "unset" }))
        hl.dispatch(hl.dsp.window.float({ action = "on" }))
    elseif w.floating then
        -- 2. Already floating -> Return to tiled
        hl.dispatch(hl.dsp.window.float({ action = "off" }))
        return
    else
        -- 3. Tiled -> Float
        hl.dispatch(hl.dsp.window.float({ action = "on" }))
    end

    -- Apply custom size and center if defined
    local custom = float_sizes[w.class]
    if custom then
        local width = custom[1]
        local height = custom[2]
        hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false }))
        hl.dispatch(hl.dsp.window.center())
    end
end

return M
