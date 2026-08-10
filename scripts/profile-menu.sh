#!/usr/bin/env bash
#
# Profile dropdown — rofi only, no eww.
# Shows identity, live system stats, a todo list, and a stopwatch.
#
# Row selection behaviour:
#   a todo row             -> toggle done/undone
#   "+ add todo"           -> prompts for text, appends
#   timer row               -> start/pause
#   "reset timer"          -> resets to 00:00:00
#   Alt+Return on a todo   -> remove it instead of toggling
#
# Second click on the star icon closes an already-open menu (same toggle
# pattern as calendar-popup.sh).

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
set -uo pipefail

THEME="${HYPR_ROFI}/profile.rasi"
STATS_PY="${HYPR_WAYBAR_SCRIPTS}/profile-stats.py"
TODOS_PY="${HYPR_WAYBAR_SCRIPTS}/profile-todos.py"
TIMER_PY="${HYPR_WAYBAR_SCRIPTS}/profile-timer.py"

STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hypr"
mkdir -p "$STATE_DIR"

# Toggle: second invocation while open closes it.
if pgrep -f "rofi.*apps/rofi/profile.rasi" >/dev/null 2>&1; then
  pkill -f "rofi.*apps/rofi/profile.rasi" >/dev/null 2>&1 || true
  exit 0
fi

# Flat two-tone meter: solid line throughout, filled portion full-bright,
# remainder dimmed. Avoids stippled/checkerboard glyphs like ░ at small sizes.
bar() {
  local pct=$1 color=$2 width=10 filled empty filled_str empty_str
  filled=$(( pct * width / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  empty=$(( width - filled ))
  filled_str=$(printf '%0.s━' $(seq 1 "$filled") 2>/dev/null)
  empty_str=$(printf '%0.s━' $(seq 1 "$empty") 2>/dev/null)
  printf '<span foreground="%s">%s</span><span foreground="%s" alpha="25%%">%s</span>' \
    "$color" "$filled_str" "$color" "$empty_str"
}

# Alert thresholds: temp > 75C, any other meter > 90%.
stat_rows() {
  "$STATS_PY" | while read -r key pct label unit; do
    local limit=90 color="#ffffff"
    [ "$unit" = "temp" ] && limit=75
    if (( pct > limit )); then
      color="#ff0000"
      printf '<span foreground="%s">%-4s %s %s</span>\n' "$color" "$key" "$(bar "$pct" "$color")" "$label"
    else
      printf '%-4s %s %s\n' "$key" "$(bar "$pct" "$color")" "$label"
    fi
  done
}

todo_rows() {
  "$TODOS_PY" list
}

# Rows before the todo block: N stat rows, separator.
rows_before_todos() {
  local n_stats
  n_stats=$(stat_rows | wc -l)
  echo $(( n_stats + 1 ))
}

build_menu() {
  local timer_line
  timer_line=$("$TIMER_PY" status)

  {
    stat_rows
    echo "---"
    todo_rows
    echo "+ add todo"
    echo "---"
    printf '⏱  %s\n' "$timer_line"
    echo "reset timer"
  }
}

prompt_text() {
  printf '' | rofi -dmenu -p "$1" -theme "$THEME" -lines 0
}

while true; do
  before=$(rows_before_todos)
  n_todos=$(todo_rows | wc -l)
  # 0-based indices within the full menu:
  add_todo_idx=$(( before + n_todos ))
  timer_idx=$(( add_todo_idx + 2 ))
  reset_idx=$(( timer_idx + 1 ))

  set +e
  sel=$(build_menu | rofi -dmenu -markup-rows -p "Profile" -mesg "$(whoami)" \
    -theme "$THEME" \
    -no-custom \
    -kb-custom-1 "Alt+Return" \
    -format i)
  code=$?
  set -e

  [ -z "$sel" ] && exit 0

  # Alt+Return only ever means "remove" and only applies to todo rows.
  if [ "$code" = "10" ]; then
    if (( sel >= before && sel < before + n_todos )); then
      "$TODOS_PY" remove $(( sel - before )) >/dev/null
    fi
    continue
  fi

  if (( sel >= before && sel < before + n_todos )); then
    "$TODOS_PY" toggle $(( sel - before )) >/dev/null
  elif (( sel == add_todo_idx )); then
    new_todo=$(prompt_text "New todo")
    [ -n "$new_todo" ] && "$TODOS_PY" add "$new_todo" >/dev/null
  elif (( sel == timer_idx )); then
    "$TIMER_PY" toggle >/dev/null
  elif (( sel == reset_idx )); then
    "$TIMER_PY" reset >/dev/null
  fi
done
