--//================================================================//
--//                       APP BINDS                                //
--//  Kitty, Fuzzel, Ghostty, browsers, file manager, wallpaper,    //
--//  quickshell, emoji picker, calculator.                         //
--//================================================================//

local v = require("lua.core.variables")

--*================================================================*--
--                     APP LAUNCHERS                                  --
--*================================================================*--

hl.bind("CTRL + ALT + K", hl.dsp.exec_cmd(v.terminal),
    { description = "Launch Terminal (Kitty)" })

hl.bind("SUPER + E", hl.dsp.exec_cmd(v.file_mgr),
    { description = "Launch File Manager" })

hl.bind("SUPER + R", hl.dsp.exec_cmd("fuzzel"),
    { description = "Launch App Menu (Fuzzel)" })

hl.bind("CTRL + SUPER + space", hl.dsp.exec_cmd(v.home .. "/.config/fuzzel/scripts/fuzzel-emoji.sh"),
    { description = "Emoji Picker (Fuzzel)" })

hl.bind("XF86Search", hl.dsp.exec_cmd("rofi -show drun -show-icons"),
    { description = "Rofi Menu" })

--*================================================================*--
--                       BROWSERS                                    --
--*================================================================*--

hl.bind("CTRL + ALT + B", hl.dsp.exec_cmd("brave"),
    { description = "Launch Brave" })

hl.bind("CTRL + ALT + F", hl.dsp.exec_cmd("firefox"),
    { description = "Launch Firefox" })

--*================================================================*--
--                      TERMINALS                                    --
--*================================================================*--

hl.bind("CTRL + ALT + A", hl.dsp.exec_cmd("alacritty"),
    { description = "Launch Alacritty" })

hl.bind("CTRL + ALT + G", hl.dsp.exec_cmd(
    "env MESA_GL_VERSION_OVERRIDE=4.6 MESA_GLSL_VERSION_OVERRIDE=460 ghostty"
), { description = "Launch Ghostty" })

--*================================================================*--
--                    CALCULATOR                                     --
--*================================================================*--

hl.bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator"),
    { description = "Calculator" })

--*================================================================*--
--                     WALLPAPER                                     --
--*================================================================*--

hl.bind("SUPER + W", hl.dsp.exec_cmd(v.script_dir .. "/wallpaper.sh"),
    { description = "Change Wallpaper" })

hl.bind("SUPER + CTRL + W", hl.dsp.exec_cmd(v.script_dir .. "/livewallpaper.sh"),
    { description = "Toggle Live Wallpaper" })

hl.bind("SUPER + ALT + W", hl.dsp.exec_cmd("waypaper"),
    { description = "Launch Waypaper (Wallpaper Manager)" })

--*================================================================*--
--                     QUICKSHELL                                    --
--*================================================================*--

hl.bind("SUPER + T", hl.dsp.exec_cmd(
    "env QT_SCALE_FACTOR=1 QT_AUTO_SCREEN_SCALE_FACTOR=0 quickshell -c QuickSnip -n"
), { description = "Quickshell QuickSnip" })
