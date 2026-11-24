--//================================================================//
--//                     SMART SPLIT (The Toggle Fix)               //
--//  A simple flip-flop state to bounce windows back and forth.    //
--//================================================================//

local M = {}

-- State variables to remember the next direction
local k_right = true
local j_down = true

function M.shuffle(direction)
	if direction == "k" then
		-- Move Right if true, Left if false
		hl.dispatch(hl.dsp.window.move({ direction = k_right and "r" or "l" }))

		-- Flip the switch for the next time you press K
		k_right = not k_right
	elseif direction == "j" then
		-- Move Down if true, Up if false
		hl.dispatch(hl.dsp.window.move({ direction = j_down and "d" or "u" }))

		-- Flip the switch for the next time you press J
		j_down = not j_down
	end
end

return M
