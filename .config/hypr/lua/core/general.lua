--//================================================================//
--//                    GENERAL SETTINGS                            //
--//  Gaps, decoration, quirks, render, input, layouts, misc.       //
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

		-- ── Window Wobble ──
		wobble = {
			enabled = true,
			-- Tunables (defaults shown):
			mesh = 8, -- Vertex subdivisions per edge [2 - 32]
			stiffness = 180, -- Spring stiffness [0.0001 - 1000]
			damping = 14, -- Spring resistance/bounce decay [0 - 1000]
			mass = 1.0, -- Inertial mass [0.0001 - 1000]
			intensity = 0.2, -- Impulse multiplier on mouse movement [0 - 3]
		},
	},

	-- ── Quirks (Fixes Kitty EGLConfigs on Ivy Bridge HD 4000) ──
	--quirks = {
	--   skip_non_kms_dmabuf_formats = false,
	--},

	-- ── Render (Fixes broken blur & disables heavy FP16 workbuffers) ──
	--render = {
	--  use_fp16 = 0,
	--use_shader_blur_blend = true,
	--},

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
		scroll_event_delay = 0,
	},
})
