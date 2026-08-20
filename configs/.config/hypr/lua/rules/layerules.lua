--//================================================================//
--//                      LAYER RULES                               //
--//  Selection tool, snappy-switcher blur rules.                   //
--//================================================================//

-- ── Disable animation for region-selection overlays ──
hl.layer_rule({
	name = "no-anim-for-selection",
	match = { namespace = "selection" },
	no_anim = true,
})

-- ── Snappy Dock GTK — blur & Shadow fix --
--hl.layer_rule({
--	match = { namespace = "snappy-dock-gtk" },
--	blur = true,
--	ignore_alpha = 0.01,
-- })

-- ── Snappy Switcher — blur behind the switcher UI ──
-- Uncomment when you enable snappy-switcher blur:
-- hl.layer_rule({
--     match        = { namespace = "snappy-switcher" },
--     blur         = true,
--     ignore_alpha = 0.01,
-- })
