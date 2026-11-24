--//================================================================//
--//                      LAYER RULES                               //
--//  Selection tool, launcher, snappy-switcher blur rules.         //
--//================================================================//

-- ── Disable animation for region-selection overlays ──
hl.layer_rule({
    name = "no-anim-for-selection",
    match = { namespace = "selection" },
    no_anim = true,
})

-- ── Fuzzel Launcher — blur fix ──
hl.layer_rule({
    name = "fuzzel-blur",
    match = { namespace = "launcher" },
    blur = true,
    ignore_alpha = 0.2,
})

-- ── Snappy Dock GTK — blur & shadow ──
-- hl.layer_rule({
-- 	match = { namespace = "snappy-dock-gtk" },
-- 	blur = true,
-- 	ignore_alpha = 0.01,
-- })

-- ── Snappy Switcher — blur behind switcher UI ──
-- hl.layer_rule({
--     match        = { namespace = "snappy-switcher" },
--     blur         = true,
--     ignore_alpha = 0.01,
-- })
