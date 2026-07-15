#!/usr/bin/env bash
#
# Wallpaper center. Lists wallpapers in a rofi menu with thumbnail icons
# (rofi row metadata: "name\0icon\x1f/path"). Selecting one calls the
# wallpaper.sh setter. Pure shell -- no python, no GTK.

THEME=/home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
SET_WALLPAPER="$HOME/.config/hypr/scripts/wallpaper.sh"

[ -d "$WALLPAPER_DIR" ] || exit 0

# Build the rofi input: one line per image, "basename\0icon\x1f/full/path".
# The \x1f (unit separator) tells rofi the icon path for that row.
list_entries() {
  find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    | sort | while IFS= read -r path; do
        name=$(basename "$path")
        printf '%s\0icon\x1f%s\n' "$name" "$path"
      done
}

selection=$(list_entries | rofi -dmenu -i -p "Wallpaper" -show-icons -theme "$THEME")
[ -z "$selection" ] && exit 0

setsid -f "$SET_WALLPAPER" set "$WALLPAPER_DIR/$selection" >/dev/null 2>&1
