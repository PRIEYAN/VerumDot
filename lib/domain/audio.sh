#!/usr/bin/env bash
# domain/audio.sh — sink and source control.
#
# Three different backends appear across this machine's tooling (wpctl from
# WirePlumber, pamixer, pactl) and the keybindings chained all three with
# `||`. That chain was duplicated in hypr.conf, vol-action.sh and the
# volume module, each with a slightly different volume step and boost limit.
# The chain is expressed once here, as an ordered list of candidates.

hypr::use core/guard os/proc ui/waybar

readonly AUDIO_MAX_PERCENT=150      # allow boost above 100%
readonly AUDIO_STEP_PERCENT=5

audio::available() { guard::has pamixer || guard::has wpctl || guard::has pactl; }

# ---- queries --------------------------------------------------------------
# pamixer is preferred for reads because it reports the boosted range
# directly; wpctl returns a 0..1.5 float that needs converting.
audio::volume() {
  local v
  if guard::has pamixer && v=$(proc::capture pamixer --get-volume); then
    printf '%s' "$v"; return 0
  fi
  if guard::has wpctl && v=$(proc::capture wpctl get-volume @DEFAULT_AUDIO_SINK@); then
    awk '{ printf "%d", $2 * 100 }' <<<"$v"; return 0
  fi
  return 1
}

audio::muted() {
  local v
  if guard::has pamixer; then
    v=$(proc::capture pamixer --get-mute) && [[ $v == true ]]
    return
  fi
  if guard::has wpctl; then
    proc::capture wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED
    return
  fi
  return 1
}

audio::mic_muted() {
  local v
  if guard::has pamixer; then
    v=$(proc::capture pamixer --default-source --get-mute) \
      || v=$(proc::capture pamixer --get-mute)
    [[ $v == true ]]
    return
  fi
  if guard::has wpctl; then
    proc::capture wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED
    return
  fi
  return 1
}

# ---- commands -------------------------------------------------------------
# Each mutator repaints the matching bar module, so no caller has to
# remember to — forgetting was why the eww volume panel and the bar could
# show different numbers.
audio::set_volume() {
  local pct=$1
  (( pct < 0 )) && pct=0
  (( pct > AUDIO_MAX_PERCENT )) && pct=$AUDIO_MAX_PERCENT
  proc::first_available \
    "pamixer --allow-boost --set-limit $AUDIO_MAX_PERCENT --set-volume $pct" \
    "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ ${pct}%" \
    "pactl set-sink-volume @DEFAULT_SINK@ ${pct}%"
  waybar::refresh volume
}

audio::step_volume() {
  local direction=$1 sign
  [[ $direction == up ]] && sign=+ || sign=-
  proc::first_available \
    "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ ${AUDIO_STEP_PERCENT}%${sign}" \
    "pamixer --allow-boost --set-limit $AUDIO_MAX_PERCENT $([[ $sign == + ]] && printf -- -i || printf -- -d) $AUDIO_STEP_PERCENT" \
    "pactl set-sink-volume @DEFAULT_SINK@ ${sign}${AUDIO_STEP_PERCENT}%"
  waybar::refresh volume
}

audio::toggle_mute() {
  proc::first_available \
    "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" \
    "pamixer -t" \
    "pactl set-sink-mute @DEFAULT_SINK@ toggle"
  waybar::refresh volume
}

audio::toggle_mic() {
  proc::first_available \
    "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle" \
    "pamixer --default-source -t" \
    "pactl set-source-mute @DEFAULT_SOURCE@ toggle"
  waybar::refresh mic
}
