--//================================================================//
--//                       ENVIRONMENT                              //
--//  Sets env vars BEFORE Hyprland draws the screen.               //
--//================================================================//

-- Cursor (must load early)
hl.env("HYPRCURSOR_THEME", "Bibata-Original-Ice")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Bibata-Original-Ice")
hl.env("XCURSOR_SIZE", "24")

-- Qt / GTK
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")

-- XDG
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
