--//================================================================//
--//                     SMART FLOAT                                //
--//  Ported from smart_float.sh — zero IPC overhead.               //
--//                                                                //
--//  Logic:                                                        //
--//   1. If window is floating → toggle back to tiled              //
--//   2. If tiled → look up class in float_sizes table             //
--//   3. If custom size found → float + resize exact + center      //
--//   4. If no custom size → just toggle float                     //
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
--- If the window has a custom size in float_sizes, it will be resized and centered.
function M.toggle()
    local w = hl.get_active_window()
    if not w then
        return
    end

    -- Already floating? Toggle back to tiled.
    if w.floating then
        hl.dispatch(hl.dsp.window.float())
        return
    end

    -- Tiled → float it
    hl.dispatch(hl.dsp.window.float())

    -- Look up custom size
    local custom = float_sizes[w.class]
    if custom then
        local width = custom[1]
        local height = custom[2]
        hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false }))
        hl.dispatch(hl.dsp.window.center())
    end
end

return M
