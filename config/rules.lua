-- Window rules for application placement and opacity.

-- A floating "Center" popup pinned under the bar. `move` takes monitor-local
-- expressions: `monitor_w-window_w-10` is the old `100%-w-10` (right edge,
-- 10px in). Matched on class, and on title where the app sets one.
local LEFT  = "10 48"
local RIGHT = "monitor_w-window_w-10 48"

local function center(match, size, move)
    hl.window_rule({
        match     = match,
        float     = true,
        size      = size,
        move      = move,
        animation = "slide top",
    })
end

-- Calendar Center (Top Left)
center({ class = "^(.*CalendarCenter.*)$" }, "380 400", LEFT)
center({ title = "^(Calendar Center)$" },    "380 400", LEFT)

-- Wallpaper Center (Top Right)
center({ class = "^(.*WallpaperCenter.*)$" }, "560 480", RIGHT)

-- Network Center (Top Right)
center({ class = "^(.*[Nn]etwork.*[Cc]enter.*)$" }, "420 560", RIGHT)
center({ title = "^(Network Center)$" },            "420 560", RIGHT)

-- Power Center (Top Right)
center({ class = "^(.*PowerCenter.*)$" }, "380 280", RIGHT)
center({ title = "^(Power Center)$" },    "380 280", RIGHT)

-- Spotify Center (Top Left, under the now-playing module)
center({ class = "^(.*SpotifyCenter.*)$" }, "340 470", LEFT)
center({ title = "^(Spotify Center)$" },    "340 470", LEFT)


-- AnyDesk: themed via GTK (see scripts/anydesk-launch.sh and
-- apps/theme/gtk-3.0/gtk.css). Keep a thin border so the top edge still reads
-- as a window boundary against the black waybar strip. Blur comes from the
-- global decoration.blur block — there is no per-window blur effect.
-- The old two-colour `border_color active inactive` is now two rules split
-- on the `focus` prop.
hl.window_rule({
    match       = { class = "^(anydesk)$" },
    border_size = 2,
    opacity     = "0.90 override 0.85 override 1.0 override",
})
hl.window_rule({ match = { class = "^(anydesk)$", focus = true },  border_color = "rgba(ffffffcc)" })
hl.window_rule({ match = { class = "^(anydesk)$", focus = false }, border_color = "rgba(2a2a2a88)" })

-- Dolphin: Kvantum PureBlackGlass supplies the window's alpha; keep the
-- compositor opacity at 1.0 so it isn't dimmed twice, and let the global
-- blur block frost the wallpaper behind the translucent surface.
hl.window_rule({ match = { class = "^(org.kde.dolphin)$" }, opacity = "1.0 1.0" })

-- Kitty: same reasoning. The terminal draws its own glass (background_opacity
-- plus the per-pane transparent_background_colors in apps/kitty/kitty.conf),
-- so the compositor stays at 1.0 — otherwise the Neovim editor panes get
-- dimmed twice and the code stops being readable over a bright wallpaper.
hl.window_rule({ match = { class = "^(kitty)$" }, opacity = "1.0 1.0" })

-- Wi-Fi / Bluetooth live in the quickshell control centre (top-right hot
-- corner). blueman-manager / nm-connection-editor are only opened as the
-- "Advanced" fallback; float them so they don't tile. (GTK apps self-position
-- at map time and ignore static move rules, so the scripts place them.)
hl.window_rule({ match = { class = "^(.*[Bb]lueman.*)$" }, float = true, animation = "slide top" })
hl.window_rule({ match = { class = "^(.*[Nn]m-.*)$" },     float = true, animation = "slide top" })

-- Spotify app: translucent glass — blur (ignore_opacity) frosts the
-- wallpaper through the Electron surface. `override` sets absolute opacity
-- (not multiplied by decoration active/inactive_opacity). Fullscreen stays solid.
hl.window_rule({
    match   = { class = "^(spotify)$" },
    opacity = "0.80 override 0.70 override 1.0 override",
})
