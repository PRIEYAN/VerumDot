#!/usr/bin/env bash
# ui/theme.sh — the colour tokens shell-rendered markup uses.
#
# These are the same semantic roles the .rasi themes and the quickshell
# Theme singleton define. Keeping the shell copy in one file means a palette
# change is three edits (here, the rasi tokens, the QML singleton) rather
# than a hunt through every script that happened to hardcode '#9ece6a'.
#
# Thresholds live here too, for the same reason: "what counts as hot" was
# previously spelled out separately in profile-menu.sh (>75) and
# battery-status.sh (>=85), so the two panels disagreed about when to turn
# a reading red.

readonly THEME_DIM='#6f7488'
readonly THEME_FG='#ffffff'
readonly THEME_OK='#9ece6a'
readonly THEME_WARN='#e0af68'
readonly THEME_DANGER='#f7768e'
readonly THEME_ALERT='#ff0000'

# Load thresholds, in percent.
readonly THEME_LOAD_WARN=60
readonly THEME_LOAD_DANGER=85
# Temperature thresholds, in Celsius.
readonly THEME_TEMP_WARN=70
readonly THEME_TEMP_DANGER=85

# theme::load_color <percent> — the colour a utilisation reading should take.
# An empty reading is "unknown", not "zero", and is dimmed rather than green.
theme::load_color() {
  local pct=${1:-}
  if   [[ -z $pct ]];                   then printf '%s' "$THEME_DIM"
  elif (( pct >= THEME_LOAD_DANGER ));  then printf '%s' "$THEME_DANGER"
  elif (( pct >= THEME_LOAD_WARN ));    then printf '%s' "$THEME_WARN"
  else                                       printf '%s' "$THEME_OK"
  fi
}

theme::temp_color() {
  local temp=${1:-}
  if   [[ -z $temp ]];                  then printf '%s' "$THEME_DIM"
  elif (( temp >= THEME_TEMP_DANGER )); then printf '%s' "$THEME_DANGER"
  elif (( temp >= THEME_TEMP_WARN ));   then printf '%s' "$THEME_WARN"
  else                                       printf '%s' "$THEME_OK"
  fi
}
