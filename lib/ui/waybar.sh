#!/usr/bin/env bash
# ui/waybar.sh — the waybar custom-module protocol, in one place.
#
# A custom module is a program whose stdout is a JSON object with `text`,
# `tooltip`, `class` and `percentage` fields. The old scripts emitted that
# three different ways:
#
#     echo '{"text":"'$icon'","tooltip":"Click to toggle"}'     # mic
#     printf '{"text":"%s","tooltip":"Wi-Fi · %s"}' ...    # wifi
#     jq -nc --arg t "$text" '{text:$t}'                        # volume
#
# The first two break the moment a value contains a quote or a backslash —
# and an SSID or a track title is user-controlled text that very much can.
# One SSID named `My"Net` produced invalid JSON and a blank bar module.
#
# Everything now goes through jq, which cannot emit malformed JSON.

hypr::use core/guard

# waybar::emit <text> [tooltip] [class...] — print one module object.
#
# Classes are variadic and empty ones are dropped, so a caller can pass a
# conditionally-empty variable without building the surrounding JSON array
# by hand (the old brightness module did that with nested
# `${EYE_CLASS:+,\"$EYE_CLASS\"}` substitutions).
waybar::emit() {
  local text=${1-} tooltip=${2-}
  (( $# > 2 )) && shift 2 || set --
  local class classes=()
  for class in "$@"; do
    [[ -n $class ]] && classes+=("$class")
  done
  printf '%s\n' "${classes[@]+"${classes[@]}"}" \
    | jq -cRn --arg t "$text" --arg tt "$tooltip" \
        '[inputs | select(length > 0)] as $c
         | {text: $t, tooltip: $tt} + (if ($c | length) > 0 then {class: $c} else {} end)'
}

# waybar::emit_pct <text> <tooltip> <percentage> [class...] — as above plus
# the `percentage` field, which drives waybar's built-in progress styling.
waybar::emit_pct() {
  local text=${1-} tooltip=${2-} pct=${3-0}; shift 3
  local class classes=()
  for class in "$@"; do
    [[ -n $class ]] && classes+=("$class")
  done
  printf '%s\n' "${classes[@]+"${classes[@]}"}" \
    | jq -cRn --arg t "$text" --arg tt "$tooltip" --argjson p "${pct:-0}" \
        '[inputs | select(length > 0)] as $c
         | {text: $t, tooltip: $tt, percentage: $p}
           + (if ($c | length) > 0 then {class: $c} else {} end)'
}

# waybar::unavailable <glyph> <reason> — the standard "this module cannot
# work on this machine" output. Previously each script invented its own
# wording and half of them forgot a tooltip, leaving a bare glyph with no
# explanation of why the module was dead.
waybar::unavailable() {
  waybar::emit "$1 n/a" "$2" unavailable
}

# ---------------------------------------------------------------------------
# Repainting
# ---------------------------------------------------------------------------
# waybar reloads a custom module when it receives RTMIN+<signal>. The numbers
# are an interface shared with apps/waybar/config.jsonc, so they are named
# here instead of appearing as bare integers at the call sites.
#
# Naming them found two live bugs. scripts/eww/vol-action.sh poked RTMIN+1
# after changing the volume — that is the *brightness* module, so the volume
# reading never refreshed. scripts/spotify-center.sh poked RTMIN+10 after a
# track change, which is *battery*; the spotify module had no signal at all
# and relied on its 2s poll. Both are obvious as names and invisible as
# integers.
declare -Ag WAYBAR_SIGNAL=(
  [brightness]=1
  [volume]=2
  [mic]=3
  [wifi]=8
  [bluetooth]=9
  [battery]=10
  [stay_awake]=11
  [spotify]=12
)

# waybar::refresh <module>... — repaint the named modules at once.
waybar::refresh() {
  local module signal
  for module in "$@"; do
    signal=${WAYBAR_SIGNAL[$module]:-}
    if [[ -z $signal ]]; then
      log::warn "no waybar signal registered for module '$module'"
      continue
    fi
    pkill "-RTMIN+${signal}" waybar >/dev/null 2>&1 || true
  done
}
