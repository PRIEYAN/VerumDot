#!/usr/bin/env bash
# Test suite for the shared library.
#
# Deliberately hermetic: every test redirects the XDG trees into a scratch
# directory, so running the suite can never touch the live wallpaper choice,
# fan mode or todo list. Tests that would need real hardware assert on the
# pure logic instead — the parsing, clamping and formatting, which is where
# the bugs actually were.
#
#   tests/run.sh            run everything
#   tests/run.sh markup     run only matching test functions

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/log

PASS=0
FAIL=0
FILTER=${1:-}

# --- assertions ------------------------------------------------------------
check() {
  local label=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    PASS=$(( PASS + 1 ))
    printf '  \033[32mok\033[0m   %s\n' "$label"
  else
    FAIL=$(( FAIL + 1 ))
    printf '  \033[31mFAIL\033[0m %s\n       expected: %q\n       actual:   %q\n' \
      "$label" "$expected" "$actual"
  fi
}

check_true() {
  local label=$1; shift
  if "$@"; then
    PASS=$(( PASS + 1 )); printf '  \033[32mok\033[0m   %s\n' "$label"
  else
    FAIL=$(( FAIL + 1 )); printf '  \033[31mFAIL\033[0m %s (expected success)\n' "$label"
  fi
}

check_false() {
  local label=$1; shift
  if "$@"; then
    FAIL=$(( FAIL + 1 )); printf '  \033[31mFAIL\033[0m %s (expected failure)\n' "$label"
  else
    PASS=$(( PASS + 1 )); printf '  \033[32mok\033[0m   %s\n' "$label"
  fi
}

# --- tests -----------------------------------------------------------------

test_markup_escape() {
  hypr::use ui/markup
  # Bash 5.2 treats `&` in a replacement as "the matched text"; a naive
  # implementation turns <tag> into <lt;tag>gt;.
  check 'escape: ampersand'      'AT&amp;T'              "$(markup::escape 'AT&T')"
  check 'escape: angle brackets' '&lt;b&gt;'             "$(markup::escape '<b>')"
  check 'escape: combined'       'a &amp; &lt;b&gt;'     "$(markup::escape 'a & <b>')"
  check 'escape: already escaped is escaped again' '&amp;amp;' "$(markup::escape '&amp;')"
  check 'escape: empty'          ''                      "$(markup::escape '')"
}

test_markup_clamp_and_repeat() {
  hypr::use ui/markup
  check 'clamp: below'  '0'  "$(markup::clamp -5 0 100)"
  check 'clamp: above'  '100' "$(markup::clamp 150 0 100)"
  check 'clamp: inside' '42' "$(markup::clamp 42 0 100)"
  check 'repeat: zero gives empty' '' "$(markup::repeat 'x' 0)"
  check 'repeat: negative gives empty' '' "$(markup::repeat 'x' -3)"
  check 'repeat: counts'  'xxx' "$(markup::repeat 'x' 3)"
  check 'repeat: multibyte' '━━' "$(markup::repeat '━' 2)"
}

test_markup_duration() {
  hypr::use ui/markup
  check 'duration: seconds'      '0:07'  "$(markup::duration 7)"
  check 'duration: minutes'      '2:05'  "$(markup::duration 125)"
  check 'duration: fractional'   '2:05'  "$(markup::duration 125.84)"
  check 'duration: negative'     '0:00'  "$(markup::duration -3)"
  check 'duration: empty'        '0:00'  "$(markup::duration '')"
  check 'duration: over an hour' '61:01' "$(markup::duration 3661)"
}

test_markup_track() {
  hypr::use ui/markup
  # The old player bar could compute a negative "empty" count and emit a
  # broken row when position exceeded length.
  check 'track: empty at 0'   "$(markup::repeat '─' 10)" "$(markup::track 0 10)"
  check 'track: full at 100'  "$(markup::repeat '━' 10)" "$(markup::track 100 10)"
  check 'track: clamps above 100' "$(markup::repeat '━' 10)" "$(markup::track 150 10)"
  check 'track: half' "$(markup::repeat '━' 5)$(markup::repeat '─' 5)" "$(markup::track 50 10)"
}

test_waybar_json() {
  hypr::use ui/waybar
  # The hand-rolled emitters broke on any value containing a quote — an SSID
  # or a track title is user-controlled text that very much can.
  check 'waybar: quotes survive' \
    'My"Net' "$(waybar::emit 'My"Net' t | jq -r .text)"
  check 'waybar: backslash survives' \
    'a\b' "$(waybar::emit 'a\b' t | jq -r .text)"
  check 'waybar: empty classes are dropped' \
    'null' "$(waybar::emit x y '' '' | jq -r '.class // "null"')"
  check 'waybar: classes kept in order' \
    'one two' "$(waybar::emit x y one two | jq -r '.class | join(" ")')"
  check 'waybar: output is a single line' \
    '1' "$(waybar::emit 'a' 'b' c | wc -l)"
  check 'waybar: percentage is a number not a string' \
    'number' "$(waybar::emit_pct a b 55 | jq -r '.percentage | type')"
  check_true 'waybar: emit is always valid JSON' \
    bash -c "source lib/bootstrap.sh; hypr::use ui/waybar; waybar::emit 'a\"b\\\\c' 'x' | jq -e . >/dev/null"
}

# in_sandbox <script> — run a snippet in a child shell whose XDG trees point
# at a fresh scratch directory. The rice's paths are readonly by design, so
# they cannot be reassigned in-process; overriding XDG_* before bootstrap is
# both the only way and the more honest test, since it exercises the real
# path-resolution code.
in_sandbox() {
  local sandbox; sandbox=$(mktemp -d)
  XDG_STATE_HOME="$sandbox/state" XDG_DATA_HOME="$sandbox/data" \
  XDG_CACHE_HOME="$sandbox/cache" XDG_RUNTIME_DIR="$sandbox/run" \
  HYPR_LOG_LEVEL=silent \
    bash -c "source '${HYPR_HOME}/lib/bootstrap.sh'; $1"
  rm -rf "$sandbox"
}

test_state() {
  local sandbox; sandbox=$(mktemp -d)

  check 'state: missing key gives default' 'fallback' \
    "$(in_sandbox 'hypr::use os/state; state::get nope fallback')"
  check 'state: roundtrip' 'hello' \
    "$(in_sandbox 'hypr::use os/state; state::set probe hello; state::get probe other')"
  check 'state: exists after set' 'yes' \
    "$(in_sandbox 'hypr::use os/state; state::set p v; state::exists p && echo yes')"
  check 'state: absent key does not exist' 'no' \
    "$(in_sandbox 'hypr::use os/state; state::exists nope || echo no')"
  check 'state: invalid value falls back' '1.0' \
    "$(in_sandbox 'hypr::use os/state; state::set n garbage; state::get n 1.0 state::is_number')"
  check 'state: valid number kept' '1.25' \
    "$(in_sandbox 'hypr::use os/state; state::set n 1.25; state::get n 1.0 state::is_number')"
  check 'state: enum rejects an unknown value' 'auto' \
    "$(in_sandbox 'hypr::use os/state; state::set m sideways; state::get_enum m auto auto normal max')"
  check 'state: enum accepts a known value' 'max' \
    "$(in_sandbox 'hypr::use os/state; state::set m max; state::get_enum m auto auto normal max')"
  check 'state: latch fires once then stops' 'fired-then-quiet' \
    "$(in_sandbox 'hypr::use os/state; state::latch x && printf fired; state::latch x || printf -- -then-quiet')"
  check 'state: latch rearms after unlatch' 'rearmed' \
    "$(in_sandbox 'hypr::use os/state; state::latch x; state::unlatch x; state::latch x && printf rearmed')"

  rm -rf "$sandbox"
}

test_guard() {
  hypr::use core/guard
  check_true  'guard: existing command'  guard::has bash
  check_false 'guard: missing command'   guard::has definitely-not-installed-xyz
  check_false 'guard: any missing fails' guard::has bash definitely-not-installed-xyz
  check 'guard: one_of accepts'  'max' "$(guard::one_of max auto normal max)"
  check_false 'guard: one_of rejects' guard::one_of sideways auto normal max
}

test_appicons() {
  hypr::use ui/appicons
  # An empty glyph makes waybar hide the module entirely, taking the whole
  # workspace tab with it, so the default must never be empty.
  check_false 'appicons: default is never empty' test -z "$APP_ICON_DEFAULT"
  check 'appicons: unknown class falls back' "$APP_ICON_DEFAULT" "$(appicons::for totally-unknown)"
  check 'appicons: exact match'      "$(appicons::for kitty)"   "$(appicons::for KITTY)"
  check 'appicons: substring match'  "$(appicons::for firefox)" "$(appicons::for firefox-developer-edition)"
  # `|` inside a variable is matched literally by `case`, so the alternatives
  # have to be split and tested one at a time.
  check 'appicons: later alternative in a group still matches' \
    "$(appicons::for alacritty)" "$(appicons::for xterm)"
  check_false 'appicons: never returns empty' test -z "$(appicons::for '')"
}

test_calendar() {
  hypr::use ui/calendar
  check 'calendar: normalise month 13' '2027 1'  "$(calendar::normalize 2026 13)"
  check 'calendar: normalise month 0'  '2025 12' "$(calendar::normalize 2026 0)"
  check 'calendar: normalise far past' '2024 12' "$(calendar::normalize 2026 -12)"
  check 'calendar: grid is a fixed six weeks plus a header' \
    '49' "$(calendar::grid 2026 10 | wc -l)"
  check 'calendar: grid height is stable across months' \
    '49' "$(calendar::grid 2026 2 | wc -l)"
  check 'calendar: leap February' '49' "$(calendar::grid 2024 2 | wc -l)"
  check 'calendar: title' 'October 2026' "$(calendar::title 2026 10)"
}

test_theme() {
  hypr::use ui/theme
  check 'theme: unknown load is dimmed, not green' "$THEME_DIM"    "$(theme::load_color '')"
  check 'theme: light load is ok'                  "$THEME_OK"     "$(theme::load_color 10)"
  check 'theme: heavy load warns'                  "$THEME_WARN"   "$(theme::load_color 70)"
  check 'theme: very heavy load is danger'         "$THEME_DANGER" "$(theme::load_color 95)"
  check 'theme: cool temp is ok'                   "$THEME_OK"     "$(theme::temp_color 40)"
  check 'theme: hot temp is danger'                "$THEME_DANGER" "$(theme::temp_color 90)"
}

test_table() {
  hypr::use ui/table
  # An unknown reading must not render as an empty bar, which reads as "idle".
  check_true 'table: unknown reading draws a dotted rule' \
    bash -c "source lib/bootstrap.sh; hypr::use ui/table; table::meter '' | grep -q '·'"
  check_true 'table: 5% still shows one filled cell (rounds, not truncates)' \
    bash -c "source lib/bootstrap.sh; hypr::use ui/table; table::meter 5 | grep -q '█'"
  check_true 'table: 0% shows no filled cell' \
    bash -c "source lib/bootstrap.sh; hypr::use ui/table; ! table::meter 0 | grep -q '█'"
}

test_rofi_resolve_index() {
  hypr::use ui/rofi
  # Every branch of the power menu is irreversible, so an unresolved
  # selection must fail rather than defaulting to the first row.
  check 'rofi: numeric index passes through' '2' "$(rofi::resolve_index 2 a b c d)"
  check 'rofi: row text resolves to its index' '1' "$(rofi::resolve_index b a b c d)"
  check_false 'rofi: unknown selection fails' rofi::resolve_index zzz a b c
  check_false 'rofi: out-of-range index fails' rofi::resolve_index 9 a b c
}

test_menu_keys() {
  hypr::use ui/menu
  # Rows carry an explicit key so an SSID containing the separator, or two
  # devices sharing a name, still resolve correctly.
  local rows=("$(menu::row 'AA:BB' 'Speaker  ·  paired')" "$(menu::row 'CC:DD' 'Speaker  ·  paired')")
  check 'menu: first duplicate label resolves to its own key' \
    'AA:BB' "$(menu::key_for 'Speaker  ·  paired' "${rows[@]}")"
  local spaced=("$(menu::row 'my net' 'my net  ·  80%')")
  check 'menu: key with a space survives' \
    'my net' "$(menu::key_for 'my net  ·  80%' "${spaced[@]}")"
  check_false 'menu: unknown label fails' menu::key_for 'nope' "${rows[@]}"
}

test_ini() {
  hypr::use os/ini
  local file; file=$(mktemp)
  printf '[General]\nfoo=1\n\n[Appearance]\nstyle=old\nkeep=yes\n' >"$file"
  ini::set "$file" Appearance style kvantum
  check 'ini: replaces in the right section' 'style=kvantum' "$(grep '^style=' "$file")"
  check 'ini: leaves neighbours alone'       'keep=yes'      "$(grep '^keep=' "$file")"
  ini::set "$file" Appearance icon_theme kora
  check 'ini: appends to an existing section' 'icon_theme=kora' "$(grep '^icon_theme=' "$file")"
  ini::set "$file" NewSection key value
  check 'ini: creates a missing section' 'key=value' "$(grep '^key=' "$file")"
  check 'ini: does not duplicate the file' '1' "$(grep -c '^\[General\]' "$file")"
  rm -f "$file"
}

test_jsonstore() {
  check 'jsonstore: missing document gives the default' '[]' \
    "$(in_sandbox "hypr::use os/jsonstore; jsonstore::load probe '[]'")"
  check 'jsonstore: roundtrip' 'a' \
    "$(in_sandbox "hypr::use os/jsonstore; jsonstore::save probe '[{\"text\":\"a\"}]'; jsonstore::load probe '[]' | jq -r '.[0].text'")"
  check 'jsonstore: corrupt document degrades to the default' '[]' \
    "$(in_sandbox "hypr::use os/jsonstore; mkdir -p \"\$HYPR_DATA_DIR\"; printf 'not json' > \"\$HYPR_DATA_DIR/c.json\"; jsonstore::load c '[]'")"
  check 'jsonstore: a refused save leaves the good document intact' 'a' \
    "$(in_sandbox "hypr::use os/jsonstore; jsonstore::save probe '[{\"text\":\"a\"}]'; jsonstore::save probe 'nope{' 2>/dev/null; jsonstore::load probe '[]' | jq -r '.[0].text'")"
}

test_battery_icons() {
  hypr::use domain/battery
  check_false 'battery: icon is never empty at 100' test -z "$(battery::icon 100)"
  check_false 'battery: icon is never empty at 0'   test -z "$(battery::icon 0)"
  check 'battery: full and high share an icon' "$(battery::icon 100)" "$(battery::icon 81)"
  check_false 'battery: the 80 boundary changes icon' \
    test "$(battery::icon 80)" = "$(battery::icon 81)"
}

test_cal_data_shape() {
  # The eww calendar backend builds JSON with jq now; it used to place every
  # comma by hand. Structure is what matters here.
  local out; out=$(./scripts/eww/cal-data.sh 0)
  check_true 'cal-data: valid JSON' bash -c "printf '%s' '$out' | jq -e . >/dev/null"
  check 'cal-data: whole weeks only' 'true' \
    "$(jq -r '[.weeks[] | length] | all(. == 7)' <<<"$out")"
  check 'cal-data: exactly one day is today' '1' \
    "$(jq -r '[.weeks[][] | select(.today)] | length' <<<"$out")"
  check 'cal-data: a distant month has no today' '0' \
    "$(./scripts/eww/cal-data.sh 6 | jq -r '[.weeks[][] | select(.today)] | length')"
}

# --- runner ----------------------------------------------------------------
main() {
  local name
  printf '\nlibrary tests\n\n'
  for name in $(declare -F | awk '{print $3}' | grep '^test_' | sort); do
    [[ -n $FILTER && $name != *"$FILTER"* ]] && continue
    printf '\033[1m%s\033[0m\n' "${name#test_}"
    "$name"
  done
  printf '\n  %d passed, %d failed\n\n' "$PASS" "$FAIL"
  (( FAIL == 0 ))
}

main
