#!/usr/bin/env bash
# Long-running process for eww's (deflisten cal_data ...). Emits one JSON
# line per month whenever calendar-nav.sh signals a change via the FIFO,
# and once immediately on startup so the calendar has initial data.

state_dir="/tmp/eww-calendar-center"
fifo="$state_dir/nav.fifo"
state_file="$state_dir/state"
mkdir -p "$state_dir"
[ -p "$fifo" ] || mkfifo "$fifo"
[ -f "$state_file" ] || printf '%s %s\n' "$(date +%Y)" "$(date +%-m)" > "$state_file"

emit() {
  read -r year month < "$state_file" 2>/dev/null
  if [ -z "$year" ]; then
    year=$(date +%Y)
    month=$(date +%-m)
    printf '%s %s\n' "$year" "$month" > "$state_file"
  fi
  /home/prieyan/.config/hypr/scripts/calendar-data.sh "$year" "$month"
}

emit

while read -r cmd < "$fifo"; do
  read -r year month < "$state_file"
  case "$cmd" in
    next)
      month=$((month + 1))
      if [ "$month" -gt 12 ]; then month=1; year=$((year + 1)); fi
      ;;
    prev)
      month=$((month - 1))
      if [ "$month" -lt 1 ]; then month=12; year=$((year - 1)); fi
      ;;
    today)
      year=$(date +%Y)
      month=$(date +%-m)
      ;;
  esac
  printf '%s %s\n' "$year" "$month" > "$state_file"
  emit
done
