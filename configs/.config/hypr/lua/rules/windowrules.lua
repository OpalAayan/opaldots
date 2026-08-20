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

-- ── Alacritty ──
hl.window_rule({
    match = { class = "Alacritty" },
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
    size = "900 550",
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

-- ── Alacritty — Active: Bright Orange | Inactive: Burnt Orange ──
hl.window_rule({
    match = { class = "^Alacritty$" },
    border_color = "rgba(ff9900ff) rgb(995c00)",
})

-- ── Kitty — Active: Light Pink/Purple | Inactive: Teal ──
hl.window_rule({
    match = { class = "^kitty$" },
    border_color = "rgb(F7AFFF) rgb(8FBCBB)",
})

-- ── Ghostty — Active: Purple | Inactive: Dim ──
hl.window_rule({
    match = { class = "^com\\.mitchellh\\.ghostty$" },
    border_color = "rgb(9d7cd8) rgb(5a5f7a)",
})

-- ── Brave — Active: Purple | Inactive: Dim Pink ──
hl.window_rule({
    match = { class = "^brave-browser$" },
    border_color = "rgb(9d7cd8) rgb(eab8d1)",
})

-- ── Firefox — Active: Purple | Inactive: Soft Pink ──
hl.window_rule({
    match = { class = "^(firefox)$" },
    border_color = "rgba(a78bfaff) rgb(dcadf0)",
})

-- ── Btop Floating — Gradient Active/Inactive: Purple→Pink→Red 180deg ──
hl.window_rule({
    match = { class = "^btop-floating$" },
    border_color =
    "rgba(7c3aedff) rgba(cba6f7ff) rgba(b4befeff) rgba(d20f39ff) 180deg rgba(9333eaff) rgba(cba6f7ff) rgba(b4befeff) rgba(c01c28ff) 180deg",
})

-- ── Nmtui Floating — Gradient Active/Inactive ──
hl.window_rule({
    match = { class = "^(nmtui-floating)$" },
    border_color =
    "rgba(4c1d95ff) rgba(4c1d95ff) rgba(a78bfaff) rgba(f472b6ff) rgba(a78bfaff) 180deg rgba(4c1d95ff) rgba(a78bfaff) rgba(f472b6ff) rgba(a78bfaff) 180deg",
})

-- ── Kitty Fruity — Tropical Gradient Active/Inactive Border ──
hl.window_rule({
    match = { class = "^(kitty-fruity)$" },
    -- Format: active_gradient inactive_gradient
    -- Using Watermelon -> Mango -> Mint
    --border_color = "rgba(ff897dff) rgba(ffd0b5ff) rgba(6cdad1ff) 45deg rgba(533d4fff) rgba(322530ff) 45deg",
    border_color = "rgba(ff897dff) rgba(1e1e28ff)",
})

-- --- Waypaper ---
hl.window_rule({
    match = { class = "waypaper" },
    border_color = "rgba(ffffffff)",
})

-- --- Nautilus ---
hl.window_rule({
    match = { class = "org.gnome.Nautilus" },
    border_color = "rgba(fcfbfcff)"
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
