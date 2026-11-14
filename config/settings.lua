-- Per-machine choices. setup.sh rewrites the values in this file (one
-- `key = value` per line, so a sed can find each one); everything else in
-- config/ reads from here instead of hard-coding them.

return {
    -- Apps bound to SUPER+T / SUPER+Return, SUPER+W, SUPER+E, SUPER+C.
    terminal = "kitty",
    browser  = "firefox",
    files    = "nautilus",
    editor   = "code",

    -- Primary output. Replace `eDP-1` with yours if different
    -- (`hyprctl -j monitors`); an empty output applies to any display.
    monitor_output   = "eDP-1",
    monitor_mode     = "preferred",
    monitor_position = "auto",
    monitor_scale    = "1.0",

    -- Exports __GLX_VENDOR_LIBRARY_NAME=nvidia. setup.sh turns this off on
    -- Intel/AMD machines.
    nvidia = true,

    -- setup.sh turns this on: pushes the session environment into systemd
    -- and starts hyprpolkitagent at login.
    session_env = false,

    -- Custom wallpaper folder for the wallpaper scripts; nil keeps their
    -- default.
    wallpaper_dir = nil,
}
