-- Look and feel: borders, gaps, glass, animations.

-- Minimal, barely-there glass edges. waybar is docked to the top edge; gaps_out
-- keeps a 4px seam between it and the windows below.
hl.config({
    general = {
        gaps_in     = 2,   -- per window, so 4px between two windows (matches the seam under the bar)
        -- No outer gap at the sides, so window borders sit on the screen
        -- edge in line with the waybar's left/right outline; 4px top and
        -- bottom keep the seam under the bar.
        gaps_out    = { top = 4, right = 0, bottom = 4, left = 0 },
        border_size = 1,
        -- Same grey the waybar outline shows. The bar is a 0.7px #888888 line,
        -- which antialiases to #646464 on screen; window borders are whole
        -- pixels, so they use #646464 directly to look identical.
        col = {
            active_border   = "rgba(646464ff)",
            inactive_border = "rgba(646464ff)",
        },
    },

    -- macOS Sonoma glass. Deep, multi-pass blur is what separates real frosted
    -- glass from flat transparency — the panels themselves are only 60% opaque
    -- and rely on this to stay readable.
    decoration = {
        rounding = 2,

        blur = {
            enabled           = true,
            size              = 10,
            passes            = 4,
            new_optimizations = true,
            xray              = false,
            ignore_opacity    = true,
            -- Vibrancy: pull a little saturation and light out of what sits
            -- behind the glass, the way macOS materials do.
            vibrancy          = 0.20,
            vibrancy_darkness = 0.25,
            -- A dark material darkens its backdrop before tinting it — without
            -- this the wallpaper reads straight through the panel and white
            -- text loses contrast.
            brightness        = 0.85,
            contrast          = 1.0,
            -- Fine grain. macOS materials are dithered; without it a 4-pass
            -- blur over a smooth gradient bands visibly.
            noise             = 0.02,
        },

        -- Soft shadow only, no hard outline.
        shadow = {
            enabled      = true,
            range        = 20,
            render_power = 3,
            color        = "rgba(00000055)",
        },

        active_opacity   = 0.97,
        inactive_opacity = 0.92,
    },

    animations = {
        enabled = true,
    },

    -- Disable experimental color management to restore full physical screen
    -- brightness (prevents SDR clamping to 80 nits).
    render = {
        cm_enabled = false,
    },
})

-- Smooth animations.
--
-- Sonoma easing: decelerate into place, never overshoot. `speed` is in
-- deciseconds (1 = 100ms), the same unit the old `animation =` lines used.
local function bezier(name, x1, y1, x2, y2)
    hl.curve(name, { type = "bezier", points = { { x1, y1 }, { x2, y2 } } })
end

bezier("sonoma",    0.22, 1.0, 0.36, 1.0)
bezier("sonomaOut", 0.4,  0.0, 0.2,  1.0)
-- Snappy workspace switch: fast out, quick settle.
bezier("snap",      0.2,  0.9, 0.2,  1.0)

local function anim(leaf, speed, curve, style)
    hl.animation({ leaf = leaf, enabled = true, speed = speed, bezier = curve, style = style })
end

anim("windows",     2,  "sonoma",    "popin 96%")
anim("windowsIn",   2,  "sonoma",    "popin 96%")
anim("windowsOut",  2,  "sonomaOut", "popin 96%")
anim("windowsMove", 2,  "sonoma")
anim("border",      3,  "sonoma")
anim("borderangle", 30, "sonoma")
anim("fade",        2,  "sonoma")
anim("fadeIn",      2,  "sonoma")
anim("fadeOut",     2,  "sonomaOut")
-- Workspace switching (keys, SUPER+scroll, 3-finger swipe): Hyprland's stock
-- transition, copied from /usr/share/hypr/hyprland.lua — a short fade on the
-- almostLinear curve. The hidden special workspace keeps its vertical slide.
bezier("almostLinear", 0.5, 0.5, 0.75, 1)
anim("workspaces",    1.94, "almostLinear", "fade")
anim("workspacesIn",  1.21, "almostLinear", "fade")
anim("workspacesOut", 1.94, "almostLinear", "fade")
anim("specialWorkspace", 3, "snap", "slidevert")
anim("layers",      2,  "sonoma",    "fade")
anim("layersIn",    2,  "sonoma",    "fade")
anim("layersOut",   2,  "sonomaOut", "fade")
