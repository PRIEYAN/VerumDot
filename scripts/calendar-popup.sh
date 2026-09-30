#!/usr/bin/env bash
#
# Rofi calendar dropdown under the waybar clock.
# Left/Right = month, Up/Down = year, Return = today, Esc = close.
# Click the clock again while open to dismiss.


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
set -euo pipefail

THEME="${HYPR_ROFI}/calendar.rasi"
TMPDIR=${XDG_RUNTIME_DIR:-/tmp}
DAYS_FILE="$TMPDIR/rofi-cal-days.$$"
SEL_FILE="$TMPDIR/rofi-cal-sel.$$"

cleanup() { rm -f "$DAYS_FILE" "$SEL_FILE"; }
trap cleanup EXIT

# Toggle: second click closes an open calendar.
if pgrep -f "rofi.*apps/rofi/calendar.rasi" >/dev/null 2>&1; then
  pkill -f "rofi.*apps/rofi/calendar.rasi" >/dev/null 2>&1 || true
  exit 0
fi

year=$(date +%Y)
month=$(date +%-m)

shift_month() {
  local delta=$1
  month=$((month + delta))
  while (( month > 12 )); do
    month=$((month - 12))
    year=$((year + 1))
  done
  while (( month < 1 )); do
    month=$((month + 12))
    year=$((year - 1))
  done
}

emit_days() {
  # Pure shell: `date` does the calendar arithmetic, so this has no python
  # dependency. Output is byte-identical to the previous python version.
  local muted='#666666'
  local today_y today_m today_d first_dow lead days_in_month prev_days
  local idx d n selected first_in_month

  today_y=$(date +%Y); today_m=$(date +%-m); today_d=$(date +%-d)

  first_dow=$(date -d "$year-$month-01" +%u)                 # 1=Mon .. 7=Sun
  lead=$(( first_dow - 1 ))                                  # cells before the 1st
  days_in_month=$(date -d "$year-$month-01 +1 month -1 day" +%-d)
  prev_days=$(date -d "$year-$month-01 -1 day" +%-d)         # length of prev month

  # Weekday names live in the grid itself so they sit exactly above their
  # column. They are the first row and are marked urgent by rofi (-u 0..6),
  # which styles them muted and keeps them out of the selection.
  printf 'Mo\nTu\nWe\nTh\nFr\nSa\nSu\n' > "$DAYS_FILE"

  first_in_month=$(( 7 + lead ))
  selected=$first_in_month

  for (( d = lead; d > 0; d-- )); do          # tail of the previous month
    printf '<span foreground="%s">%s</span>\n' "$muted" "$(( prev_days - d + 1 ))"
  done >> "$DAYS_FILE"

  for (( d = 1; d <= days_in_month; d++ )); do
    printf '%s\n' "$d"
    if [[ $year -eq $today_y && $month -eq $today_m && $d -eq $today_d ]]; then
      selected=$(( 7 + lead + d - 1 ))
    fi
  done >> "$DAYS_FILE"

  idx=$(( 7 + lead + days_in_month ))
  n=1                                          # head of the next month
  while (( idx < 49 )); do                     # pad to a full 6-week grid
    printf '<span foreground="%s">%s</span>\n' "$muted" "$n"
    n=$(( n + 1 )); idx=$(( idx + 1 ))
  done >> "$DAYS_FILE"

  printf '%s' "$selected" > "$SEL_FILE"
}

while true; do
  header=$(date -d "$year-$month-01" +"%B %Y")
  emit_days
  selected=$(cat "$SEL_FILE")

  set +e
  # Clear defaults that own Left/Right/Up/Down/Return before rebinding them.
  rofi \
    -dmenu \
    -markup-rows \
    -theme "$THEME" \
    -p "$header" \
    -u "0,1,2,3,4,5,6" \
    -selected-row "$selected" \
    -no-custom \
    -kb-move-char-back "Control+b" \
    -kb-move-char-forward "Control+f" \
    -kb-row-up "Control+p" \
    -kb-row-down "Control+n" \
    -kb-accept-entry "" \
    -kb-custom-1 "Left,h" \
    -kb-custom-2 "Right,l" \
    -kb-custom-3 "Up,k" \
    -kb-custom-4 "Down,j" \
    -kb-custom-5 "Return,KP_Enter" \
    < "$DAYS_FILE" \
    >/dev/null
  code=$?
  set -e

  case $code in
    10) shift_month -1 ;;
    11) shift_month  1 ;;
    12) year=$((year - 1)) ;;
    13) year=$((year + 1)) ;;
    14)
      year=$(date +%Y)
      month=$(date +%-m)
      ;;
    *)  exit 0 ;;
  esac
done
