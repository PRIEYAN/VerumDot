#!/usr/bin/env bash
# Emits JSON describing one calendar month for eww's Calendar Center.
# Usage: calendar-data.sh <year> <month>
#
# Weeks are Monday-first and padded with the leading/trailing days of the
# adjacent months so every row has 7 cells (a standard month grid with
# Monday as the first weekday).

year="$1"
month="$2"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/json.sh"

# Zero-pad month for GNU date.
printf -v mm '%02d' "$month"

# First day of the requested month, and today (for the "today" flag).
first="${year}-${mm}-01"
today=$(date +%Y-%m-%d)

# Title / subtitle, upper/lower to match the previous output.
title=$(date -d "$first" +'%B %Y' | tr '[:lower:]' '[:upper:]')
subtitle=$(date -d "$today" +'%a %d %b %Y' | tr '[:upper:]' '[:lower:]')

# Grid start: back up from the 1st to the preceding Monday.
# date %u → 1(Mon)..7(Sun); step back (dow-1) days.
dow=$(date -d "$first" +%u)
start=$(date -d "$first -$(( dow - 1 )) days" +%Y-%m-%d)

# Emit whole weeks until we pass the end of the target month — a variable
# 4–6 week count with no trailing all-muted week. Cap at 6 weeks as a
# safety bound.
weeks_json=""
cur=$start
for (( w=0; w<6; w++ )); do
  week_json=""
  week_has_month=false
  for (( d=0; d<7; d++ )); do
    day=$(date -d "$cur" +%-d)
    cur_month=$(date -d "$cur" +%-m)
    muted=false; [ "$cur_month" -ne "$month" ] && muted=true
    [ "$cur_month" -eq "$month" ] && week_has_month=true
    istoday=false; [ "$cur" = "$today" ] && istoday=true
    cell=$(printf '{"day":%d,"muted":%s,"today":%s}' "$day" "$muted" "$istoday")
    if [ -z "$week_json" ]; then week_json="$cell"; else week_json="$week_json,$cell"; fi
    cur=$(date -d "$cur +1 day" +%Y-%m-%d)
  done
  # A week with no day of the target month means we've spilled fully into the
  # next month, so stop (don't render an all-muted trailing week).
  [ "$week_has_month" = false ] && break
  wk="[$week_json]"
  if [ -z "$weeks_json" ]; then weeks_json="$wk"; else weeks_json="$weeks_json,$wk"; fi
done

printf '{"title":%s,"subtitle":%s,"weeks":[%s]}\n' \
  "$(json_str "$title")" "$(json_str "$subtitle")" "$weeks_json"
