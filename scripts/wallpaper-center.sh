#!/usr/bin/env bash
#
# Wallpaper center. Lists wallpapers in a rofi menu with thumbnail icons
# (rofi row metadata: "name\0icon\x1f/path"). Selecting one calls the
# wallpaper.sh setter. Pure shell -- no python, no GTK.
#
# Usage: wallpaper-center.sh [lock]
#   (no args)  set the desktop wallpaper   -> wallpaper.sh set
#   lock       set the lock screen wallpaper -> wallpaper.sh set-lock


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
THEME="${HYPR_ROFI}/wallpaper.rasi"
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
SET_WALLPAPER="${HYPR_DIR}/scripts/wallpaper.sh"

# Desktop by default; "lock" targets the hyprlock background instead.
if [ "$1" = "lock" ]; then
  PROMPT="Lock Screen Wallpaper"
  SET_ACTION="set-lock"
else
  PROMPT="Wallpaper"
  SET_ACTION="set"
fi

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

# wallpaper.rasi renders a pure-black grid of large image previews with
# filenames hidden. The row still carries the basename as its value, so
# the selection below resolves to the chosen file.
selection=$(list_entries | rofi -dmenu -i -p "$PROMPT" \
  -show-icons -theme "$THEME")
[ -z "$selection" ] && exit 0

setsid -f "$SET_WALLPAPER" "$SET_ACTION" "$WALLPAPER_DIR/$selection" >/dev/null 2>&1
