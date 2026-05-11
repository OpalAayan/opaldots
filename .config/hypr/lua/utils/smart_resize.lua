--//================================================================//
--//                    SMART RESIZE                                //
--//  Ported from smart_resize.sh — zero IPC overhead.              //
--//                                                                //
--//  Logic:                                                        //
--//   Detects if the window is touching a monitor edge.            //
--//   If at edge → shrink (invert direction).                      //
--//   Otherwise  → grow (normal direction).                        //
--//                                                                //
--//  This makes resizing "just work" regardless of window          //
--//  position — you always push outward from center.               //
--//================================================================//

local M = {}

-- Threshold for edge detection (pixels).
-- Accounts for gaps and borders.
local GAP = 20

--- Resize the active window in a given direction.
--- @param direction string "l"|"r"|"u"|"d" (left, right, up, down)
--- @param step number Pixel step size (default 20)
function M.resize(direction, step)
    step = step or 20

    local w = hl.get_active_window()
    if not w then return end

    local m = hl.get_active_monitor()
    if not m then return end

    -- Window bounds
    local box_x = w.at[1]
    local box_y = w.at[2]
    local box_w = w.size[1]
    local box_h = w.size[2]

    -- Monitor bounds
    local mon_x = m.x
    local mon_y = m.y
    local mon_w = m.width
    local mon_h = m.height

    -- Edge coordinates
    local win_r = box_x + box_w   -- window right edge
    local win_b = box_y + box_h   -- window bottom edge
    local mon_r = mon_x + mon_w   -- monitor right edge
    local mon_b = mon_y + mon_h   -- monitor bottom edge

    local dx, dy = 0, 0

    if direction == "l" or direction == "left" then
        -- LEFT KEY
        -- Touching left edge? → shrink (pull right border left)
        if (box_x - GAP) <= mon_x then
            dx = -step
        else
            -- Otherwise → grow (push left border left)
            dx = step
        end
        hl.dispatch(hl.dsp.window.resize({ x = dx, y = 0, relative = true }))

    elseif direction == "r" or direction == "right" then
        -- RIGHT KEY
        -- Touching right edge? → shrink
        if (win_r + GAP) >= mon_r then
            dx = -step
        else
            -- Otherwise → grow
            dx = step
        end
        hl.dispatch(hl.dsp.window.resize({ x = dx, y = 0, relative = true }))

    elseif direction == "u" or direction == "up" then
        -- UP KEY
        -- Touching top edge? → shrink
        if (box_y - GAP) <= mon_y then
            dy = -step
        else
            -- Otherwise → grow
            dy = step
        end
        hl.dispatch(hl.dsp.window.resize({ x = 0, y = dy, relative = true }))

    elseif direction == "d" or direction == "down" then
        -- DOWN KEY
        -- Touching bottom edge? → shrink
        if (win_b + GAP) >= mon_b then
            dy = -step
        else
            -- Otherwise → grow
            dy = step
        end
        hl.dispatch(hl.dsp.window.resize({ x = 0, y = dy, relative = true }))
    end
end

return M
