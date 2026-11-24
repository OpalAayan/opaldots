--//================================================================//
--//                      WINDOW RULES                              //
--//  Float/size/center, border colors, BlueJ unblur.               //
--//================================================================//

--*================================================================*--
--                    FLOATING WINDOW RULES                          --
--*================================================================*--

-- ── Btop Floating ──
hl.window_rule({
	match = { class = "btop-floating" },
	float = true,
	size = "1220 600",
	center = true,
})

-- ── Nmtui Floating ──
hl.window_rule({
	match = { class = "nmtui-floating" },
	float = true,
	size = "900 550",
	center = true,
})

-- ── Waypaper ──
hl.window_rule({
	match = { class = "waypaper" },
	float = true,
	size = "800 550",
	center = true,
})

-- ── kitty-fruity ──
hl.window_rule({
	match = { class = "kitty-fruity" },
	float = true,
	size = "900 550",
	center = true,
})

-- ── Proton VPN ──
hl.window_rule({
	match = { class = "protonvpn-app" },
	float = true,
	size = "100 500",
	center = true,
})

-- ── Gnome Calculator ──
hl.window_rule({
	match = { class = "org.gnome.Calculator" },
	float = true,
	size = "100 200",
	center = true,
})

-- ── Gnome Calendar ──
hl.window_rule({
	match = { class = "org.gnome.Calendar" },
	float = true,
	size = "880 580",
	center = true,
})

-- ── Nautilus ──
hl.window_rule({
	match = { class = "org.gnome.Nautilus" },
	float = true,
	size = "1000 650",
	center = true,
})

-- --- TextEditor ---
hl.window_rule({
	match = { class = "org.gnome.TextEditor" },
	float = true,
	size = "700 600",
	center = true,
})

-- ── Baobab (Disk Usage) ──
hl.window_rule({
	match = { class = "org.gnome.baobab" },
	float = true,
	size = "900 550",
	center = true,
})

-- ── Blueberry (Bluetooth) ──
hl.window_rule({
	match = { class = "blueberry.py" },
	float = true,
	size = "500 500",
	center = true,
})

-- ── Virt-Manager ──
hl.window_rule({
	match = { class = "virt-manager" },
	float = true,
	size = "900 500",
	center = true,
})

-- ── XDG Desktop Portal GTK ──
hl.window_rule({
	match = { class = "xdg-desktop-portal-gtk" },
	float = true,
	size = "900 600",
	center = true,
})

-- ── Emoji Picker ──
hl.window_rule({
	match = { class = "org.gnome.Characters" },
	float = true,
	size = "800 500",
	center = true,
})

-- --- Pavucontrol ---
hl.window_rule({
	match = { class = "org.pulseaudio.pavucontrol" },
	float = true,
	size = "900 600",
	center = true,
})

--*================================================================*--
--                      BORDER COLORS                                --
--*================================================================*--

-- ── Alacritty ──
hl.window_rule({
	match = { class = "Alacritty", focus = true },
	border_color = "rgba(ff9900ff)",
})
hl.window_rule({
	match = { class = "Alacritty", focus = false },
	border_color = "rgb(995c00)",
})

-- ── Kitty ──
hl.window_rule({
	match = { class = "kitty", focus = true },
	border_color = "rgb(F7AFFF)",
})
hl.window_rule({
	match = { class = "kitty", focus = false },
	border_color = "rgb(8FBCBB)",
})

-- ── Ghostty ──
hl.window_rule({
	match = { class = "^com\\.mitchellh\\.ghostty$", focus = true },
	border_color = "rgb(9d7cd8)",
})
hl.window_rule({
	match = { class = "^com\\.mitchellh\\.ghostty$", focus = false },
	border_color = "rgb(5a5f7a)",
})

-- ── Brave ──
hl.window_rule({
	match = { class = "brave-browser", focus = true },
	border_color = "rgb(9d7cd8)",
})
hl.window_rule({
	match = { class = "brave-browser", focus = false },
	border_color = "rgb(eab8d1)",
})

-- ── Firefox ──
hl.window_rule({
	match = { class = "firefox", focus = true },
	border_color = "rgba(a78bfaff)",
})
hl.window_rule({
	match = { class = "firefox", focus = false },
	border_color = "rgb(dcadf0)",
})

-- ── Btop Floating ──
hl.window_rule({
	match = { class = "btop-floating", focus = true },
	border_color = {
		colors = { "rgba(7c3aedff)", "rgba(cba6f7ff)", "rgba(b4befeff)", "rgba(d20f39ff)" },
		angle = 180,
	},
})
hl.window_rule({
	match = { class = "btop-floating", focus = false },
	border_color = {
		colors = { "rgba(9333eaff)", "rgba(cba6f7ff)", "rgba(b4befeff)", "rgba(c01c28ff)" },
		angle = 180,
	},
})

-- ── Nmtui Floating ──
hl.window_rule({
	match = { class = "nmtui-floating", focus = true },
	border_color = {
		colors = { "rgba(4c1d95ff)", "rgba(a78bfaff)", "rgba(f472b6ff)", "rgba(a78bfaff)" },
		angle = 180,
	},
})
hl.window_rule({
	match = { class = "nmtui-floating", focus = false },
	border_color = {
		colors = { "rgba(4c1d95ff)", "rgba(a78bfaff)", "rgba(f472b6ff)", "rgba(a78bfaff)" },
		angle = 180,
	},
})

-- ── Kitty Fruity ──
hl.window_rule({
	match = { class = "kitty-fruity", focus = true },
	border_color = "rgba(ff897dff)",
})
hl.window_rule({
	match = { class = "kitty-fruity", focus = false },
	border_color = "rgba(1e1e28ff)",
})

-- --- Waypaper ---
hl.window_rule({
	match = { class = "waypaper" },
	border_color = "rgba(ffffffff)",
})

-- --- Nautilus ---
hl.window_rule({
	match = { class = "org.gnome.Nautilus" },
	border_color = "rgba(fcfbfcff)",
})

-- Antigravity --
hl.window_rule({
	match = { class = "antigravity" },
	border_color = "rgba(ffc799ff)",
})

-- ── Mission Center ──
hl.window_rule({
	match = { class = "io.missioncenter.MissionCenter", focus = true },
	border_color = {
		colors = { "rgba(3584e4ff)", "rgba(b4befeff)", "rgba(cba6f7ff)" },
		angle = 135,
	},
})
hl.window_rule({
	match = { class = "io.missioncenter.MissionCenter", focus = false },
	border_color = {
		colors = { "rgba(264b7aff)", "rgba(5a5f7aff)", "rgba(6b538cff)" },
		angle = 135,
	},
})

--*================================================================*--
--                      SPECIAL RULES                                --
--*================================================================*--

-- ── BlueJ IDE — unblur floating menus ──
hl.window_rule({
	name = "unblur-bluej-menus",
	match = { class = "^(bluej\\.Boot\\$App)$", float = true },
	no_blur = true,
})

-- ── Quickshell Widget Editor ──
hl.window_rule({
	match = { title = "^(WidgetEdit_.*)$" },
	float = true,
	pin = true,
	border_color = { colors = { "rgba(cba6f7ff)", "rgba(f38ba8ff)" }, angle = 45 },
})

-- ── Disable Wobble for Heavy Apps ──
hl.window_rule({
	name = "no-wobble-firefox",
	match = { class = "firefox" },
	no_wobble = true,
})
