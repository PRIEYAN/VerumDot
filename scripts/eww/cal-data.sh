#!/usr/bin/env bash
# Calendar data for the eww panel.
#
#   cal-data.sh <offset>     offset = months from now, negative for the past
#
# Emits {"label": "November 2024", "weeks": [[{d, today}, ...], ...]}.
#
# Built with jq rather than by printf-ing JSON a character at a time. The
# previous version tracked cell indices to decide where to place each comma
# and each "],[" week break — correct, but the kind of correct that one
# edit undoes silently. jq now owns the structure and the quoting.
#
# Sunday-first, matching the eww panel's own header row. (lib/ui/calendar.sh
# is Monday-first for the rofi panel; the two are deliberately independent.)

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli

readonly WEEK_LENGTH=7

offset=${1:-0}
[[ $offset =~ ^-?[0-9]+$ ]] || log::usage '<offset-in-months>'

# Fold the offset into a concrete year/month by counting in absolute months.
total=$(( ($(date +%Y) * 12 + ($(date +%-m) - 1)) + offset ))
year=$(( total / 12 ))
month=$(( total % 12 + 1 ))

label=$(date -d "${year}-${month}-01" +'%B %Y')
lead=$(date -d "${year}-${month}-01" +%w)                     # 0=Sun..6=Sat
days=$(date -d "${year}-${month}-01 +1 month -1 day" +%-d)

today_day=0
[[ $year == $(date +%Y) && $month == $(date +%-m) ]] && today_day=$(date +%-d)

# Trailing blanks that round the grid out to whole weeks.
trail=$(( (WEEK_LENGTH - (lead + days) % WEEK_LENGTH) % WEEK_LENGTH ))

# One cell per line — empty for padding — and let jq group them into weeks,
# tag today, and do the quoting.
{
  for (( i = 0; i < lead; i++ ));  do printf '\n'; done
  for (( d = 1; d <= days; d++ )); do printf '%s\n' "$d"; done
  for (( i = 0; i < trail; i++ )); do printf '\n'; done
} | jq -cRn --arg label "$label" --argjson today "$today_day" --argjson week "$WEEK_LENGTH" '
  [inputs]
  | map({d: ., today: (. != "" and (. | tonumber) == $today)})
  | {label: $label, weeks: [range(0; length; $week) as $i | .[$i : $i + $week]]}'
