--//================================================================//
--//                       VARIABLES                                //
--//  Shared locals used across binds, utils, and lifecycle files.  //
--//================================================================//

local M            = {}

-- ── Programs ──
M.terminal         = "kitty"
M.file_mgr         = "nautilus"
M.menu             = "fuzzel"
M.main_mod         = "SUPER"

-- ── Paths ──
M.home             = os.getenv("HOME")
M.config_home      = os.getenv("XDG_CONFIG_HOME") or (M.home .. "/.config")
M.hypr_dir         = M.config_home .. "/hypr"
M.script_dir       = M.hypr_dir .. "/scripts"

-- ── Screenshot ──
M.screenshot_dir   = M.home .. "/Pictures/Hyprshots"
M.screenshot_sound = "/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"

-- ── Script Paths (kept as bash — they talk to system daemons) ──
M.ctl_script       = M.script_dir .. "/brigthervolume.sh"

return M
