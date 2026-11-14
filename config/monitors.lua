-- Monitor setup (explicit output name + scale, from config/settings.lua).
local settings = require("config.settings")

hl.monitor({
    output   = settings.monitor_output,
    mode     = settings.monitor_mode,
    position = settings.monitor_position,
    scale    = settings.monitor_scale,
})

-- Workspace layout.
--
-- No workspace is persistent: Hyprland creates a numbered workspace the
-- moment something navigates to it and destroys it again once it is empty
-- and unfocused. That is what makes the 3-finger swipe skip empty
-- workspaces — the swipe only walks workspaces that exist, and only the ones
-- with windows do. SUPER+scroll / SUPER+CTRL+arrows still step one number at
-- a time (+1/-1, see config/binds.lua); SUPER+<n> and the waybar buttons
-- reach any number, which is created on arrival.
--
-- The hidden workspace is `special:hidden` -- a special workspace with no
-- numeric id -- so it never collides with the numbered range.
