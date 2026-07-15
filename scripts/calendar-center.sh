#!/usr/bin/env bash
#
# Calendar center. Shows a month grid via `cal` inside a rofi menu.
# Navigate with the "prev"/"next"/"today" entries; today is highlighted
# by cal itself. Pure shell -- no python, no GTK.

THEME=/home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi
STATE=/tmp/calendar-center.offset

# Month offset relative to the current month (negative = past).
read_offset() {
  [ -f "$STATE" ] && cat "$STATE" 2>/dev/null || printf '0'
}

# Print `cal` output for the current month plus `offset` months.
render_month() {
  offset=$1
  year=$(date +%Y)
  month=$(date +%-m)
  # Shift month by offset, normalising into the 1..12 range.
  total=$(( (year * 12 + (month - 1)) + offset ))
  y=$(( total / 12 ))
  m=$(( total % 12 + 1 ))
  cal "$m" "$y"
}

show() {
  offset=$(read_offset)
  header=$(render_month "$offset")
  choice=$(printf '%s\n' \
    "$header" \
    "" \
    "  prev" \
    "  today" \
    "  next" \
    "  close" \
    | rofi -dmenu -p "Calendar" -theme "$THEME")

  case "$choice" in
    *prev*)  printf '%s' "$(( offset - 1 ))" > "$STATE"; show ;;
    *next*)  printf '%s' "$(( offset + 1 ))" > "$STATE"; show ;;
    *today*) printf '0' > "$STATE"; show ;;
    *close*) rm -f "$STATE"; exit 0 ;;
    *)       rm -f "$STATE"; exit 0 ;;
  esac
}

show
