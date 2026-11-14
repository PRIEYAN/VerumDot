-- Autostart: the old `exec-once` lines. hyprland.start fires once per
-- session, so a `hyprctl reload` does not spawn duplicates.
local settings = require("config.settings")

local hypr    = os.getenv("HOME") .. "/.config/hypr"
local scripts = hypr .. "/scripts"
local qs      = hypr .. "/apps/quickshell"

hl.on("hyprland.start", function()
    if settings.session_env then
        hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprpolkitagent.service")
    end

    -- eww daemon for the popup panels (wifi/bluetooth/power/volume/calendar);
    -- skipped quietly when eww is not installed.
    hl.exec_cmd("command -v eww >/dev/null && eww -c " .. hypr .. "/apps/eww daemon")
    -- Spotify dropdown daemon (waybar now-playing module clicks toggle it over IPC).
    hl.exec_cmd("qs -p " .. qs .. "/spotify -n")
    -- App launcher daemon (SUPER+R / SUPER+Space / the waybar ⌖ module toggle it).
    hl.exec_cmd("qs -p " .. qs .. "/launcher -n")
    -- Control centre + its top-right hot corner.
    hl.exec_cmd("qs -p " .. qs .. "/controlcenter -n")
    -- Keybinding cheat sheet (SUPER+I).
    hl.exec_cmd("qs -p " .. qs .. "/keybinds -n")

    -- Boot splash: pure black overlay with assets/splash.mp4 centred on it,
    -- held for up to 850ms after QML loads while services start behind it. The
    -- launcher bounds startup and decoder cleanup too, so a splash that fails
    -- to play or refuses to exit can never keep the desktop hidden.
    -- NOT `qs -p ... -n` directly: this surface is a one-shot, not a daemon.
    hl.exec_cmd(scripts .. "/splash.sh")

    -- Instantly refresh the battery/charger icon on plug/unplug (pokes waybar).
    hl.exec_cmd(scripts .. "/battery-watch.sh")
    hl.exec_cmd(scripts .. "/battery-alert.sh")
    -- Wallpaper. wallpaper.sh starts hyprpaper itself and waits for its socket.
    hl.exec_cmd(scripts .. "/wallpaper.sh init")
    -- hypridle daemon for locking and sleep management.
    hl.exec_cmd("hypridle")
    -- Notification daemon (top-right).
    hl.exec_cmd("mako --config " .. hypr .. "/apps/mako/config")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
    -- Waybar, supervised: retries a bar that loses the startup race instead
    -- of leaving it missing for the whole session.
    hl.exec_cmd(scripts .. "/waybar-start.sh")
end)
