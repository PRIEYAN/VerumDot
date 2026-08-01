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
  python3 - "$year" "$month" "$DAYS_FILE" "$SEL_FILE" <<'PY'
import calendar, sys
from datetime import date

year, month = int(sys.argv[1]), int(sys.argv[2])
days_path, sel_path = sys.argv[3], sys.argv[4]
today = date.today()
cal = calendar.Calendar(firstweekday=calendar.MONDAY)
weeks = cal.monthdatescalendar(year, month)

while len(weeks) < 6:
    last = weeks[-1][-1]
    weeks.append([date.fromordinal(last.toordinal() + i) for i in range(1, 8)])

selected = 0
first_in_month = 0
i = 0
muted = "#666666"
lines = []
for week in weeks:
    for d in week:
        label = f"{d.day}"
        if d.month != month:
            lines.append(f'<span foreground="{muted}">{label}</span>')
        else:
            lines.append(label)
            if first_in_month == 0 and d.day == 1:
                first_in_month = i
            if d == today:
                selected = i
        i += 1

if not (year == today.year and month == today.month):
    selected = first_in_month

with open(days_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
with open(sel_path, "w", encoding="utf-8") as f:
    f.write(str(selected))
PY
}

weekdays=$'Mo  Tu  We  Th  Fr  Sa  Su'

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
    -mesg "$weekdays" \
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
