-- Keybindings.
--
-- The SUPER+I cheat sheet reads this file (scripts/keybinds-dump.py runs it
-- against a recording stub of `hl`), so every bind here shows up there.

local settings = require("config.settings")
local hypr     = os.getenv("HOME") .. "/.config/hypr"
local scripts  = hypr .. "/scripts"
local eww      = "eww -c " .. hypr .. "/apps/eww"

local exec = hl.dsp.exec_cmd
local menu = scripts .. "/app-launcher.sh"

-- Flags for the old bindel / bindl variants.
local held_locked = { locked = true, repeating = true }   -- bindel
local locked      = { locked = true }                     -- bindl

-- Hidden workspace.
hl.bind("SUPER + CTRL + SHIFT + up",   exec(scripts .. "/hidden-workspace-open.sh"))
hl.bind("SUPER + CTRL + SHIFT + down", exec(scripts .. "/hidden-workspace-close.sh"))

-- Application shortcuts
hl.bind("SUPER + T",      exec(settings.terminal))
hl.bind("SUPER + Return", exec(settings.terminal))
hl.bind("SUPER + C",      exec(settings.editor))
hl.bind("SUPER + W",      exec(settings.browser))
hl.bind("SUPER + E",      exec(settings.files))
hl.bind("SUPER + SHIFT + W",        exec(scripts .. "/wallpaper-selector.sh"))
hl.bind("SUPER + CTRL + SHIFT + W", exec(scripts .. "/lockscreen-wallpaper-selector.sh"))
hl.bind("SUPER + R",     exec(menu))
hl.bind("SUPER + Space", exec(menu))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("XF86PowerOff", exec(scripts .. "/power-menu.sh menu"))
hl.bind("SUPER + S", exec("spotify"))
-- Keybinding cheat sheet — every bind in this config, read live from it.
hl.bind("SUPER + I", exec(scripts .. "/qs-toggle.sh keybinds keybinds"))

hl.bind("SUPER + L", exec("hyprlock"))

-- Cycle CPU power mode: normal → performance → battery → normal
-- The waybar battery glyph shows which one is active
-- (red = performance, green = battery saver, white = balanced).
hl.bind("SUPER + P", exec(hypr .. "/apps/waybar/scripts/performance-mode.sh toggle"))

-- Screenshots
-- Print        → full screen (no area picker)
-- Shift+Print  → select a region
hl.bind("Print",         exec(scripts .. "/screenshot.sh full"))
hl.bind("SHIFT + Print", exec(scripts .. "/screenshot.sh selection"))

-- Notification controls (mako)
hl.bind("SUPER + N",         exec("makoctl dismiss"))
hl.bind("SUPER + SHIFT + N", exec("makoctl dismiss --all"))
hl.bind("SUPER + CTRL + N",  exec("makoctl mode -t do-not-disturb"))

-- Brightness / volume / mute: Fn+media keys only (not bare F-keys)
hl.bind("XF86MonBrightnessDown", exec(scripts .. "/brightness-control.sh down"), held_locked)
hl.bind("XF86MonBrightnessUp",   exec(scripts .. "/brightness-control.sh up"),   held_locked)
-- The wpctl -> pamixer -> pactl fallback chain, the 5% step and the 150%
-- boost limit all live in lib/domain/audio.sh rather than being repeated
-- across three bindings and the eww panel.
hl.bind("XF86AudioLowerVolume", exec(scripts .. "/volume-control.sh down"), held_locked)
hl.bind("XF86AudioRaiseVolume", exec(scripts .. "/volume-control.sh up"),   held_locked)
hl.bind("XF86AudioMute",        exec(scripts .. "/volume-control.sh mute"), held_locked)

-- Lid close → lock + blank panel. Logind must NOT suspend/hibernate
-- (HandleLidSwitch=ignore via apps/systemd/10-lid-lock.conf).
hl.bind("switch:on:Lid Switch",  exec(scripts .. "/lid-close.sh"),       locked)
-- Lid open → revive the panel; keep / show the lock screen.
hl.bind("switch:off:Lid Switch", exec(scripts .. "/display-restore.sh"), locked)

-- Calendar submap: active only while the eww calendar panel is open.
-- Left/Right change the month; Escape (or Enter) closes and leaves the map.
hl.define_submap("calendar", function()
    hl.bind("left",  exec(scripts .. "/eww-cal.sh prev"))
    hl.bind("right", exec(scripts .. "/eww-cal.sh next"))
    local function close()
        hl.dispatch(exec(eww .. " close calendar"))
        hl.dispatch(hl.dsp.submap("reset"))
    end
    hl.bind("escape", close)
    hl.bind("return", close)
end)

-- Basic workspace switching. SUPER+0 is workspace 10.
-- SUPER+CTRL+SHIFT+<n> carries the active window along (old movetoworkspace).
for i = 1, 10 do
    hl.bind("SUPER + " .. (i % 10), hl.dsp.focus({ workspace = tostring(i) }))
end
for i = 1, 10 do
    hl.bind("SUPER + CTRL + SHIFT + " .. (i % 10), hl.dsp.window.move({ workspace = tostring(i), follow = true }))
end
hl.bind("SUPER + TAB",         hl.dsp.window.cycle_next())
hl.bind("SUPER + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }))
-- Directional navigation uses +1/-1, not e+1/e-1: the `e` variants only cycle
-- through workspaces that already exist and wrap 9 -> 1, so you could never
-- reach a tenth. Plain +1 walks to the next number and creates it on arrival.
hl.bind("SUPER + mouse_up",     hl.dsp.focus({ workspace = "-1" }))
hl.bind("SUPER + mouse_down",   hl.dsp.focus({ workspace = "+1" }))
hl.bind("SUPER + CTRL + right", hl.dsp.focus({ workspace = "+1" }))
hl.bind("SUPER + CTRL + left",  hl.dsp.focus({ workspace = "-1" }))
hl.bind("SUPER + CTRL + SHIFT + R", exec("hyprctl reload && notify-send \"✎﹏﹏﹏﹏\""))
