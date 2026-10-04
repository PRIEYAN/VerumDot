#!/usr/bin/env bash
# ui/rofi.sh — every rofi interaction in the rice.
#
# The wifi and bluetooth modules each carried their own near-identical
# `rmenu`/`rinput`/`rpass` helpers; the calendar, profile and spotify popups
# each spelled out their own long rofi command line. The differences between
# them were accidental rather than deliberate, which is exactly the kind of
# drift a facade prevents.

hypr::use core/log core/guard core/paths os/proc

readonly ROFI_CONFIG="${HYPR_ROFI}/config.rasi"

# rofi::available — rofi is a hard dependency of every menu, but a caller may
# want to degrade (app-launcher prefers quickshell and only falls back here).
rofi::available() { guard::has rofi; }

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------
# rofi::menu <theme> <prompt> [extra-args...] — read rows on stdin, print the
# chosen row. Empty output means the user dismissed it.
rofi::menu() {
  local theme=$1 prompt=$2; shift 2
  rofi -dmenu -i -theme "$(rofi::theme_path "$theme")" -p "$prompt" "$@"
}

# rofi::menu_index <theme> <prompt> [extra-args...] — as above but prints the
# zero-based index of the chosen row.
#
# `-format i` is documented to return the index, but older rofi builds hand
# back the row text instead. Callers used to each re-implement a fallback
# that searched the row list; rofi::resolve_index below does it once.
rofi::menu_index() {
  local theme=$1 prompt=$2; shift 2
  rofi -dmenu -i -format i -theme "$(rofi::theme_path "$theme")" -p "$prompt" "$@"
}

# rofi::resolve_index <selection> <row>... — turn whatever rofi returned into
# a zero-based index, or return 1 if it matches nothing.
#
# Guessing is not acceptable for the power menu, where every branch is
# destructive, so an unresolved selection must fail rather than default.
rofi::resolve_index() {
  local selection=$1 i; shift
  if [[ $selection =~ ^[0-9]+$ ]] && (( selection < $# )); then
    printf '%s' "$selection"
    return 0
  fi
  for (( i = 1; i <= $#; i++ )); do
    if [[ $selection == *"${!i}"* ]]; then
      printf '%s' "$(( i - 1 ))"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Text entry
# ---------------------------------------------------------------------------
# A prompt with no list is still a dmenu, with the listview switched off.
readonly _ROFI_NO_LIST='listview { enabled: false; }'

rofi::input() {
  local theme=$1 prompt=$2; shift 2
  printf '' | rofi -dmenu -theme "$(rofi::theme_path "$theme")" -p "$prompt" \
    -theme-str "$_ROFI_NO_LIST" "$@"
}

rofi::password() {
  local theme=$1 prompt=$2; shift 2
  printf '' | rofi -dmenu -password -theme "$(rofi::theme_path "$theme")" -p "$prompt" \
    -theme-str "$_ROFI_NO_LIST" "$@"
}

# rofi::confirm <theme> <question> — yes/no, exit status is the answer.
rofi::confirm() {
  local theme=$1 question=$2 answer
  answer=$(printf 'Yes\nNo\n' | rofi::menu "$theme" "$question" -no-custom)
  [[ $answer == Yes ]]
}

# ---------------------------------------------------------------------------
# Themes
# ---------------------------------------------------------------------------
# rofi::theme_path <name-or-path> — accept either a bare theme name
# ("power", "calendar") or an absolute path, so callers need not know where
# the .rasi files live.
rofi::theme_path() {
  case $1 in
    /*) printf '%s' "$1" ;;
    *)  paths::rofi_theme "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Toggling
# ---------------------------------------------------------------------------
# Popups bound to a bar button must close on a second click. Every one of
# them did this with `pgrep -f "rofi.*foo.rasi"` followed by a matching
# `pkill -f`, which matches on a command line: a shell whose arguments
# happen to contain that text is killed too, and the pattern breaks silently
# the moment a theme is renamed.
#
# rofi::toggle runs the body under a named lock instead. Returns 1 when it
# dismissed an already-open instance, so callers `|| exit 0`.
rofi::toggle() {
  local name=$1; shift
  if proc::held "rofi-$name"; then
    proc::kill_group "rofi-$name"
    return 1
  fi
  proc::lock "rofi-$name" || return 1
  proc::register "rofi-$name"
  return 0
}

# ---------------------------------------------------------------------------
# Row construction
# ---------------------------------------------------------------------------
# rofi::icon_row <label> <icon-path> — rofi carries a per-row icon in a
# NUL/unit-separator encoding that is easy to get wrong by hand.
rofi::icon_row() { printf '%s\0icon\x1f%s\n' "$1" "$2"; }

# rofi::divider <label> — a non-selectable-looking separator row. Callers
# must still ignore it on selection; rofi::is_divider says whether to.
rofi::divider() { printf '─────  %s  ─────\n' "$1"; }
rofi::is_divider() { [[ $1 == ─────* ]]; }
