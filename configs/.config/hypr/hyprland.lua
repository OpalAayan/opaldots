--     ▄ ▄  ██  ██ ▄▄ ▄▄ ▄▄▄▄  ▄▄▄▄  ██      ▄▄▄  ▄▄  ▄▄ ▄▄▄▄
--    ▀█▀█▀ ██████ ▀███▀ ██▄█▀ ██▄█▄ ██     ██▀██ ███▄██ ██▀██ ▄▀▀▄  █
--    ▀█▀█▀ ██  ██   █   ██    ██ ██ ██████ ██▀██ ██ ▀██ ████▀ ▀   ▀▀

--//================================================================//
--//  hyprland.lua — The Loader                                     //
--//  Zero logic here. Just require() calls.                        //
--//  Each require() runs in its own error scope.                   //
--//================================================================//

require("lua.core.env")
require("lua.core.monitors")
require("lua.core.variables") -- exports shared locals used by binds/utils
require("lua.core.general")
require("lua.core.animations")

require("lua.rules.windowrules")
require("lua.rules.workspaces")
require("lua.rules.layerules")

require("lua.binds.system")
require("lua.binds.window")
require("lua.binds.apps")

require("lua.lifecycle.autostart")
