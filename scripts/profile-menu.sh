#!/usr/bin/env bash
# Profile dropdown: identity, live system stats, a todo list and a stopwatch.
#
#   a todo row            toggle done/undone
#   "+ add todo"          prompt for text and append
#   the timer row         start / pause
#   "reset timer"         back to 00:00:00
#   Alt+Return on a todo  remove it instead of toggling
#
# Row indices are computed from the rendered sections rather than hardcoded,
# because the stats block changes length with the hardware (no GPU row
# without nvidia-smi, no SWAP row without swap).

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli ui/rofi ui/markup ui/theme core/paths

readonly THEME=profile
readonly ADD_TODO_LABEL='+ add todo'
readonly RESET_TIMER_LABEL='reset timer'
readonly SEPARATOR='---'
readonly ALT_RETURN=10          # rofi's -kb-custom-1 exit code

readonly STATS="${HYPR_WAYBAR_SCRIPTS}/profile-stats.sh"
readonly TODOS="${HYPR_WAYBAR_SCRIPTS}/profile-todos.sh"
readonly TIMER="${HYPR_WAYBAR_SCRIPTS}/profile-timer.sh"

rofi::available || log::die 'rofi is not installed'
rofi::toggle profile || exit 0

# A stats line is "key percent label unit"; temperature alerts earlier than
# the others, which is why the unit is carried through.
stat_rows() {
  local key pct label unit limit color
  while read -r key pct label unit; do
    [[ $unit == temp ]] && limit=$THEME_TEMP_WARN || limit=$THEME_LOAD_DANGER
    if (( pct > limit )); then
      color=$THEME_ALERT
      printf '%s\n' "$(markup::span "$(printf '%-4s %s %s' "$key" "$(markup::meter "$pct" "$color")" "$label")" "$color")"
    else
      printf '%-4s %s %s\n' "$key" "$(markup::meter "$pct" "$THEME_FG")" "$label"
    fi
  done < <("$STATS")
}

todo_rows() { "$TODOS" list; }

build_menu() {
  stat_rows
  printf '%s\n' "$SEPARATOR"
  todo_rows
  printf '%s\n' "$ADD_TODO_LABEL"
  printf '%s\n' "$SEPARATOR"
  printf '⏱  %s\n' "$("$TIMER" status)"
  printf '%s\n' "$RESET_TIMER_LABEL"
}

while :; do
  # Recomputed each pass: adding or removing a todo shifts everything below.
  stat_count=$(stat_rows | wc -l)
  todo_count=$(todo_rows | wc -l)
  todos_start=$(( stat_count + 1 ))               # stats, then one separator
  add_todo_index=$(( todos_start + todo_count ))
  timer_index=$(( add_todo_index + 2 ))           # + separator
  reset_index=$(( timer_index + 1 ))

  selection=$(build_menu | rofi -dmenu -markup-rows \
    -p 'Profile' -mesg "$(whoami)" \
    -theme "$(rofi::theme_path "$THEME")" \
    -no-custom -format i -kb-custom-1 'Alt+Return')
  code=$?

  [[ -z $selection ]] && exit 0

  # Alt+Return only ever means "remove", and only on a todo row.
  if (( code == ALT_RETURN )); then
    (( selection >= todos_start && selection < add_todo_index )) \
      && "$TODOS" remove $(( selection - todos_start )) >/dev/null
    continue
  fi

  if (( selection >= todos_start && selection < add_todo_index )); then
    "$TODOS" toggle $(( selection - todos_start )) >/dev/null
  elif (( selection == add_todo_index )); then
    new_todo=$(rofi::input "$THEME" 'New todo' -lines 0)
    [[ -n $new_todo ]] && "$TODOS" add "$new_todo" >/dev/null
  elif (( selection == timer_index )); then
    "$TIMER" toggle >/dev/null
  elif (( selection == reset_index )); then
    "$TIMER" reset >/dev/null
  fi
done
