--//================================================================//
--//                    WORKSPACE RULES                             //
--//  Default workspace-to-monitor pinning.                         //
--//  (Generated from nwg-displays config)                          //
--//================================================================//

-- Monitor descriptors (from hyprctl monitors)
local laptop   = "desc:AU Optronics 0x303C 0x00000001"
local external = "desc:SANTAK CORP. S2-TEK TV SN-000000001"

-- ── Laptop Monitor (workspaces 1-5) ──
hl.workspace_rule({ workspace = "1",  monitor = laptop })
hl.workspace_rule({ workspace = "2",  monitor = laptop })
hl.workspace_rule({ workspace = "3",  monitor = laptop })
hl.workspace_rule({ workspace = "4",  monitor = laptop })
hl.workspace_rule({ workspace = "5",  monitor = laptop, default = true })

-- ── External Monitor (workspaces 6-10) ──
hl.workspace_rule({ workspace = "6",  monitor = external })
hl.workspace_rule({ workspace = "7",  monitor = external })
hl.workspace_rule({ workspace = "8",  monitor = external })
hl.workspace_rule({ workspace = "9",  monitor = external })
hl.workspace_rule({ workspace = "10", monitor = external, default = true })
