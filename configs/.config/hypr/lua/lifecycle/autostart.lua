--//================================================================//
--//                      AUTOSTART                                 //
--//  exec-once equivalents — runs once on Hyprland start.          //
--//================================================================//

local v = require("lua.core.variables")

hl.on("hyprland.start", function()
    -- ── System Services ──
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")

    -- ── Force GTK/Gnome Settings ──
    hl.exec_cmd('gsettings set org.gnome.desktop.interface gtk-theme "Rosepine-Dark"')
    hl.exec_cmd('gsettings set org.gnome.desktop.interface icon-theme "Tela-dracula"')
    hl.exec_cmd('gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Original-Ice"')
    hl.exec_cmd('gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"')

    -- ── Cursor ──
    hl.exec_cmd("hyprctl setcursor Bibata-Original-Ice 24")

    -- ── Notification Daemon ──
    hl.exec_cmd("dunst")

    -- ── Wallpaper ──
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("awww img " .. v.home .. "/Pictures/Wallpaper/kjj.png")

    -- ── Night Light Daemon ──
    hl.exec_cmd("wl-gammarelay-rs")

    -- ── Status Bar ──
    --hl.exec_cmd("waybar")

    -- ── Clipboard Manager ──
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- ── Dock ──
    hl.exec_cmd("snappy-dock")

    -- ── Snappy Tools ──
    hl.exec_cmd("snappy-switcher --daemon")
    hl.exec_cmd("snappy-keys --daemon")

    -- ── Wayscriber ──
    hl.exec_cmd("wayscriber --daemon")

    -- ── Custom Sounds ──
    hl.exec_cmd(v.script_dir .. "/usb-sound.sh")
    hl.exec_cmd("aplay -q " .. v.home .. "/.local/share/sounds/Startup.wav")

    -- --- QuickShell (Overview)
    ---  Bar ---
    -- hl.exec_cmd("qs -c bar")
    hl.exec_cmd("waybar")
    -- hl.exec_cmd("qs -c overview")

    -- --- Alt-tab ---
    --hl.exec_cmd("hyprctl plugin load $HOME/GitCrubs/alttab/alttab.so")

    -- --- Steam ---
    -- hl.exec_cmd("steam")
    --
end)
