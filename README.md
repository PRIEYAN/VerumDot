# Hyprland rice (portable)

## Install on a new machine

```bash
# from this folder (clone or USB copy)
chmod +x setup.sh
./setup.sh
```

Flags:
- `./setup.sh --packages` — install deps only
- `./setup.sh --config` — deploy config only (skip pacman/AUR)

This copies the rice to `~/.config/hypr`, links Waybar, installs the glass GTK/Qt theme, and pulls packages from `packages.txt`.

## Migrate

Copy or `git clone` this directory anywhere, then run `./setup.sh` again. Paths resolve via `$HOME` / `~/.config/hypr` and `scripts/_paths.sh` — nothing is hardcoded to a username.

## Layout

| Path | Role |
|------|------|
| `hyprland.conf` | entrypoint (sources `./hypr.conf`) |
| `hypr.conf` | binds, decoration, window rules |
| `scripts/` | helpers (wallpaper, waybar modules, eww) |
| `apps/` | waybar, rofi, eww, hyprlock, theme, … |
| `setup.sh` | package + deploy installer |
| `current-wallpaper` | symlink maintained by `wallpaper.sh` (used by hyprlock) |

Wallpapers live in `~/Pictures/Wallpapers/`. Replace the placeholder `suf.png` after install.
