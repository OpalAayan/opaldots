--//================================================================//
--//                     WINDOW BINDS                               //
--//  Focus, move, resize, float, close, exit, workspace nav,       //
--//  smart_float, smart_split, mouse binds.                        //
--//================================================================//

local smart_float = require("lua.utils.smart_float")
local smart_split = require("lua.utils.smart_split")
--local smart_resize = require("lua.utils.smart_resize")

--*================================================================*--
--                    WINDOW MANAGEMENT                               --
--*================================================================*--

-- Close / Exit
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close Active Window" })
hl.bind("SUPER + M", hl.dsp.exit(), { description = "Exit Hyprland Session" })

-- Toggle floating (basic — use SUPER+V for smart float)
hl.bind("SUPER + ALT + space", hl.dsp.window.float(), { description = "Toggle Floating" })

-- Smart Float (native Lua, no IPC)
hl.bind("SUPER + V", function()
	smart_float.toggle()
end, { description = "Toggle Smart Float" })

-- Smart Float with mouse middle-click
hl.bind("mouse:274", function()
	smart_float.toggle()
end, { description = "Smart Float with Mouse (Scroll Button)" })

-- Smart Split / Shuffle

hl.bind("SUPER + J", function()
	smart_split.shuffle("j")
end, { description = "Shuffle Vertical" })
hl.bind("SUPER + K", function()
	smart_split.shuffle("k")
end, { description = "Shuffle Horizontal" })
--*================================================================*--
--                       FOCUS MOVEMENT                              --
--*================================================================*--

hl.bind("SUPER + left", hl.dsp.focus({ direction = "l" }), { description = "Focus Left" })
hl.bind("SUPER + right", hl.dsp.focus({ direction = "r" }), { description = "Focus Right" })
hl.bind("SUPER + up", hl.dsp.focus({ direction = "u" }), { description = "Focus Up" })
hl.bind("SUPER + down", hl.dsp.focus({ direction = "d" }), { description = "Focus Down" })

--*================================================================*--
--                     NATIVE SMOOTH RESIZING                        --
--  Hold the key to resize smoothly. Step = 20 pixels.              --
--*================================================================*--

hl.bind(
	"SUPER + CTRL + right",
	hl.dsp.window.resize({ x = 20, y = 0, relative = true }),
	{ description = "Resize Outwards [Right]", repeating = true }
)
hl.bind(
	"SUPER + CTRL + left",
	hl.dsp.window.resize({ x = -20, y = 0, relative = true }),
	{ description = "Resize Inwards [Left]", repeating = true }
)
hl.bind(
	"SUPER + CTRL + up",
	hl.dsp.window.resize({ x = 0, y = -20, relative = true }),
	{ description = "Resize Upwards [Up]", repeating = true }
)
hl.bind(
	"SUPER + CTRL + down",
	hl.dsp.window.resize({ x = 0, y = 20, relative = true }),
	{ description = "Resize Downwards [Down]", repeating = true }
)

--*================================================================*--
--                    WORKSPACE NAVIGATION                           --
--*================================================================*--

-- Relative navigation
hl.bind("CTRL + ALT + right", hl.dsp.focus({ workspace = "r+1" }), { description = "Workspace Next" })
hl.bind("CTRL + ALT + left", hl.dsp.focus({ workspace = "r-1" }), { description = "Workspace Previous" })

-- Switch workspaces with SUPER + [0-9]
for i = 1, 10 do
	local key = i % 10
	hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = tostring(i) }), { description = "Go to Workspace " .. i })
	hl.bind(
		"SUPER + SHIFT + " .. key,
		hl.dsp.window.move({ workspace = tostring(i) }),
		{ description = "Move to Workspace " .. i }
	)
end

--*================================================================*--
--                       MOUSE BINDS                                 --
--*================================================================*--

-- Scroll through workspaces
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "r+1" }))
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "r-1" }))

-- Move/resize with mouse side buttons
hl.bind("SUPER + mouse:276", hl.dsp.window.drag(), { mouse = true })
hl.bind("mouse:276", hl.dsp.window.drag(), { mouse = true, description = "Move Active Window (Mouse Side Button)" })
hl.bind("mouse:275", hl.dsp.window.resize(), { mouse = true, description = "Resize Active Window (Mouse Side Button)" })
