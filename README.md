<div align="center">

# VerumDot

**Truth in black. Nothing else.**

*A Hyprland rice built on absolute contrast — ink-void panels, frosted glass, white type.
No accent rainbow. No noise. Just signal.*

<br/>

<img src="screenshots/desktop.png" alt="VerumDot desktop" width="920"/>

<br/>

`Hyprland` · `Waybar` · `Rofi` · `eww` · `Kitty` · `hyprlock` · `PureBlackGlass`

</div>

---

## Philosophy

VerumDot strips the desktop down to what actually matters: **readability, speed, and presence**.

Black is the canvas. White is the ink. Glass is the depth — wallpaper bleeding through translucent bars, menus, and windows so the machine feels like one surface instead of a stack of chrome boxes. Every dropdown, lock screen, and tile follows the same grammar: sharp edges of meaning, soft edges of light.

Portable by design. Clone it, run `./setup.sh`, and VerumDot is yours — no username baked in, no scavenger hunt across `~/.config`.

---

## Gallery

<p align="center">
  <img src="screenshots/desktop.png" alt="Clean desktop with Waybar" width="100%"/>
  <br/><sub>Desktop — Waybar, wallpaper, Spotify now-playing</sub>
</p>

<p align="center">
  <img src="screenshots/launcher.png" alt="Rofi app launcher" width="100%"/>
  <br/><sub>App launcher — Rofi grid over the glass desktop</sub>
</p>

<table>
  <tr>
    <td width="50%" align="center">
      <img src="screenshots/wifi-menu.png" alt="Wi-Fi dropdown"/><br/>
      <sub>Wi-Fi menu</sub>
    </td>
    <td width="50%" align="center">
      <img src="screenshots/calendar.png" alt="Calendar popup"/><br/>
      <sub>Calendar popup</sub>
    </td>
  </tr>
  <tr>
    <td colspan="2" align="center">
      <img src="screenshots/spotify-widget.png" alt="Spotify widget + terminal"/><br/>
      <sub>Spotify widget · Kitty · btop — translucent tiling</sub>
    </td>
  </tr>
</table>

---

## Overview

VerumDot is a complete Arch + Hyprland environment: dark glass UI, white typography, zero decorative clutter. One folder. One installer. Everything speaks the same language.

| Layer | What you get |
|-------|----------------|
| **Compositor** | Hyprland — blur, rounding, opacity, lid/suspend tuned |
| **Bar** | Waybar — clock, Spotify, workspaces, mic/vol/brightness, Wi-Fi, Bluetooth, battery, power |
| **Menus** | Rofi — launcher, Wi-Fi, Bluetooth, power, wallpapers, Spotify card |
| **Panels** | eww — volume, power, calendar |
| **Lock / idle** | hyprlock + hypridle |
| **Theme** | PureBlackGlass (Kvantum) + matching GTK / portal |
| **Apps** | Kitty, mako, hyprpaper, Firefox, Nautilus |

---

## Quick start

**Requirements:** Arch Linux (or derivative) · `pacman` · `yay` or `paru` (for AUR)

```bash
chmod +x setup.sh
./setup.sh
```

One run will:

1. Install packages from `packages.txt` (`pacman` + AUR)
2. Deploy the rice to `~/.config/hypr`
3. Link Waybar into `~/.config/waybar`
4. Install the PureBlackGlass GTK / Qt / portal theme
5. Create `~/Pictures/Wallpapers/` with a placeholder

### Flags

```bash
./setup.sh              # packages + config (default)
./setup.sh --packages   # dependencies only
./setup.sh --config     # config / theme only
./setup.sh --help
```

### After install

1. Put wallpapers in `~/Pictures/Wallpapers/`
2. Fix your output name in `~/.config/hypr/hypr.conf` (`eDP-1` → your monitor; `hyprctl monitors`)
3. Start a **Hyprland** session
4. Reload anytime: `hyprctl reload`

### Migrate

```bash
# on the new machine, from this folder:
./setup.sh          # full
./setup.sh --config # if packages already installed
```

Live config always lands at `~/.config/hypr`.

---

## Keybinds

| Bind | Action |
|------|--------|
| `SUPER` + `Return` / `T` | Terminal (Kitty) |
| `SUPER` + `Space` / `R` | App launcher |
| `SUPER` + `W` | Firefox |
| `SUPER` + `E` | Files |
| `SUPER` + `C` | VS Code |
| `SUPER` + `L` | Lock |
| `SUPER` + `Q` | Kill window |
| `SUPER` + `F` | Fullscreen |
| `SUPER` + `1`–`0` | Workspaces |
| `SUPER` + `Shift` + `W` | Wallpaper picker |
| `Print` | Full screenshot |
| `Shift` + `Print` | Region screenshot |

Screenshots → `~/Pictures/Screenshots` (+ clipboard).

---

## Tree

```
VerumDot/
├── setup.sh              # installer
├── packages.txt          # pacman + AUR deps
├── hyprland.conf         # entry → ./hypr.conf
├── hypr.conf             # binds, blur, rules
├── screenshots/          # gallery assets
├── scripts/
│   ├── _paths.sh         # portable roots
│   ├── wallpaper.sh
│   ├── screenshot.sh
│   └── theme-install.sh
└── apps/
    ├── waybar/           # bar + scripts
    ├── rofi/             # launcher & menus
    ├── eww/              # panels
    ├── hyprlock/
    ├── hypridle/
    ├── kitty/
    ├── mako/
    └── theme/            # PureBlackGlass
```

---

## Details

- **Wallpapers** — `~/Pictures/Wallpapers/`; active image is symlinked as `current-wallpaper` for hyprlock
- **Theme refresh** — `~/.config/hypr/scripts/theme-install.sh`
- **Glass Spotify** — window opacity rule in `hypr.conf`; center widget via Waybar click
- **NVIDIA / lid** — comments in `hypr.conf` and `apps/hypridle/hypridle.conf`

---

<div align="center">

**VerumDot** — where the desktop stops arguing with itself.

</div>
