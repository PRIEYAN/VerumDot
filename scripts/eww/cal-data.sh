#!/usr/bin/env bash
#
# Calendar data backend for the eww panel. Pure shell.
#   cal-data.sh <offset>
# Emits JSON: {"label":"November 2024","weeks":[[{d,today},...],...]}
# offset = months relative to the current month (negative = past).

offset=${1:-0}

year=$(date +%Y)
month=$(date +%-m)
today_y=$year
today_m=$month
today_d=$(date +%-d)

# Shift month by offset into a valid year/month.
total=$(( (year * 12 + (month - 1)) + offset ))
y=$(( total / 12 ))
m=$(( total % 12 + 1 ))

label=$(date -d "$y-$m-01" +"%B %Y")
first_dow=$(date -d "$y-$m-01" +%w)                       # 0=Sun..6=Sat
days_in_month=$(date -d "$y-$m-01 +1 month -1 day" +%-d)

# Emit one cell; prefixes a comma unless it is the first cell of its row.
emit_cell() {
  cell=$1; d=$2; today=$3
  if [ "$(( cell % 7 ))" -ne 0 ]; then printf ','; fi
  printf '{"d":"%s","today":%s}' "$d" "$today"
}

printf '{"label":"%s","weeks":[[' "$label"

cell=0

# Leading blanks before day 1.
i=0
while [ "$i" -lt "$first_dow" ]; do
  emit_cell "$cell" "" false
  i=$(( i + 1 )); cell=$(( cell + 1 ))
done

# Actual days.
day=1
while [ "$day" -le "$days_in_month" ]; do
  if [ "$cell" -ne 0 ] && [ "$(( cell % 7 ))" -eq 0 ]; then printf '],['; fi
  today=false
  if [ "$y" -eq "$today_y" ] && [ "$m" -eq "$today_m" ] && [ "$day" -eq "$today_d" ]; then
    today=true
  fi
  emit_cell "$cell" "$day" "$today"
  day=$(( day + 1 )); cell=$(( cell + 1 ))
done

# Trailing blanks to fill the final week.
while [ "$(( cell % 7 ))" -ne 0 ]; do
  emit_cell "$cell" "" false
  cell=$(( cell + 1 ))
done

printf ']]}\n'
