#!/usr/bin/env bash
# ui/calendar.sh — month grid construction.
#
# Pure date arithmetic and formatting, with no rofi and no eww in it, so the
# same grid serves both panels and can be tested directly. `date` does all
# the calendar maths, which is why this needs no python.

hypr::use ui/markup ui/theme

readonly CALENDAR_COLUMNS=7
readonly CALENDAR_ROWS=6
readonly CALENDAR_CELLS=$(( CALENDAR_COLUMNS * CALENDAR_ROWS ))
readonly -a CALENDAR_WEEKDAYS=(Mo Tu We Th Fr Sa Su)

# calendar::normalize <year> <month> — fold an out-of-range month into the
# neighbouring year, printing "year month". Lets callers just add or
# subtract and hand the result back.
calendar::normalize() {
  local year=$1 month=$2
  while (( month > 12 )); do month=$(( month - 12 )); year=$(( year + 1 )); done
  while (( month < 1 ));  do month=$(( month + 12 )); year=$(( year - 1 )); done
  printf '%s %s' "$year" "$month"
}

calendar::title() { date -d "$1-$2-01" +'%B %Y'; }

# calendar::_lead_days — blank cells before the 1st, Monday-first.
calendar::_lead_days() { printf '%s' $(( $(date -d "$1-$2-01" +%u) - 1 )); }
calendar::_days_in_month() { date -d "$1-$2-01 +1 month -1 day" +%-d; }
calendar::_days_in_prev_month() { date -d "$1-$2-01 -1 day" +%-d; }

# calendar::grid <year> <month> — the full grid, one cell per line:
# the weekday header row, then six weeks of days with the leading and
# trailing cells dimmed. Padding to a fixed six rows keeps the panel from
# changing height as the user pages through months.
calendar::grid() {
  local year=$1 month=$2 lead days prev day index
  lead=$(calendar::_lead_days "$year" "$month")
  days=$(calendar::_days_in_month "$year" "$month")
  prev=$(calendar::_days_in_prev_month "$year" "$month")

  printf '%s\n' "${CALENDAR_WEEKDAYS[@]}"

  for (( day = lead; day > 0; day-- )); do
    markup::span "$(( prev - day + 1 ))" "$THEME_DIM"; echo
  done

  for (( day = 1; day <= days; day++ )); do printf '%s\n' "$day"; done

  index=$(( CALENDAR_COLUMNS + lead + days ))
  day=1
  while (( index < CALENDAR_CELLS + CALENDAR_COLUMNS )); do
    markup::span "$day" "$THEME_DIM"; echo
    day=$(( day + 1 )); index=$(( index + 1 ))
  done
}

# calendar::selected_row <year> <month> — the grid row today occupies, or
# the 1st of the month when the grid is not showing the current month.
# Offset by the weekday header row.
calendar::selected_row() {
  local year=$1 month=$2 lead first
  lead=$(calendar::_lead_days "$year" "$month")
  first=$(( CALENDAR_COLUMNS + lead ))
  if [[ $year == $(date +%Y) && $month == $(date +%-m) ]]; then
    printf '%s' $(( first + $(date +%-d) - 1 ))
  else
    printf '%s' "$first"
  fi
}
