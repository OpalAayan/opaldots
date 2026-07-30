--//================================================================//
--//                    GENERAL SETTINGS                            //
--//  Gaps, decoration, input, layouts, misc, binds config.         //
--//================================================================//

hl.config({

	-- ── General ──
	general = {
		gaps_in = 3,
		gaps_out = 4,
		border_size = 2,
		col = {
			active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
			inactive_border = "rgba(595959aa)",
		},
		layout = "dwindle",
	},

	-- ── Decoration ──
	decoration = {
		rounding = 11,
		rounding_power = 2.0,
		active_opacity = 1.0,
		inactive_opacity = 0.8,
		0,
		blur = {
			enabled = true,
			size = 5,
			passes = 2,
			new_optimizations = true,
			ignore_opacity = true,
			xray = false,
		},
		shadow = {
			enabled = false,
		},
	},

	-- ── Dwindle Layout ──
	dwindle = {

		preserve_split = true,
	},

	-- ── Input ──
	input = {
		kb_layout = "us",
		follow_mouse = 1,
		touchpad = {
			natural_scroll = false,
		},
	},

	-- ── Misc ──
	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = false,
		disable_splash_rendering = true,
		initial_workspace_tracking = 0,
	},

	-- ── Binds ──
	binds = {
		scroll_event_delay = 0, -- snappy zooming
	},

	-- ── Plugin Settings ──
	--	plugin = {
	--		alttab = {
	--			powersave = true,
	--			dim = true,
	--			dim_amount = 0.3,
	--			blur = true,
	--			carousel = {
	--				size = 0.5,
	--			},
	--		},
	--	},
})
