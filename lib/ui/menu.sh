#!/usr/bin/env bash
# ui/menu.sh — the "live list" dropdown shared by Wi-Fi and Bluetooth.
#
# Both menus have the same shape and the same problem: the thing being
# listed (an AP scan, a bluetoothd device query) can take seconds, and a
# dropdown that only appears once the list is ready feels broken.
#
# Both solved it by *streaming* into rofi, which paints as soon as the first
# rows land on its stdin — so the menu is on screen immediately and fills in
# underneath. Each had its own copy of that logic, with different timeouts,
# different placeholder handling and different bugs. It lives here now.
#
# Rows are "key<TAB>label": rofi shows the label, and menu::selected_key
# recovers the key. The old versions rendered a label and then *reverse
# parsed* it with a regex to recover the identity, which broke on any name
# containing the separator and on two devices sharing a name.

hypr::use core/log os/proc ui/rofi

readonly MENU_SEP=$'\t'

# menu::row <key> <label> — emit one selectable row.
menu::row() { printf '%s%s%s\n' "$1" "$MENU_SEP" "$2"; }

# menu::labels — strip keys, for feeding rofi.
menu::labels() { cut -d"$MENU_SEP" -f2-; }

# menu::key_for <label> <rows...> — recover the key whose label matches.
menu::key_for() {
  local wanted=$1 row; shift
  for row in "$@"; do
    [[ ${row#*"$MENU_SEP"} == "$wanted" ]] && { printf '%s' "${row%%"$MENU_SEP"*}"; return 0; }
  done
  return 1
}

# menu::stream <producer> <retries> <delay> <placeholder> <empty-label> <footer...>
#
# Writes rows to stdout for rofi to consume, in two phases:
#   1. whatever <producer> can answer immediately, or <placeholder> if it has
#      nothing yet, followed by the footer actions — rofi paints here;
#   2. up to <retries> further passes <delay> apart, appending only rows not
#      already shown.
#
# A write to a closed pipe (the user has already chosen) ends the function,
# which is the intended way out.
menu::stream() {
  local producer=$1 retries=$2 delay=$3 placeholder=$4 empty_label=$5; shift 5
  local -a footer=("$@")
  local seen="" fresh new started_cold=0 appended=0 pass

  fresh=$("$producer")
  if [[ -n $fresh ]]; then
    printf '%s\n' "$fresh"
    seen=$fresh
  else
    printf '%s\n' "$placeholder"
    started_cold=1
  fi
  printf '%s\n' "${footer[@]}"

  for (( pass = 0; pass < retries; pass++ )); do
    sleep "$delay"
    fresh=$("$producer")
    [[ -z $fresh ]] && continue
    new=$(comm -23 <(sort <<<"$fresh") <(sort <<<"$seen"))
    [[ -z $new ]] && continue
    printf '%s\n' "$new"
    seen=$(printf '%s\n%s' "$seen" "$new")
    appended=1
  done

  # Started with nothing and found nothing: retire the placeholder with a
  # real answer rather than leaving "Scanning…" on screen forever.
  (( started_cold && ! appended )) && printf '%s\n' "$empty_label"
  return 0
}
