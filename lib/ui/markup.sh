#!/usr/bin/env bash
# ui/markup.sh — Pango markup, which rofi renders with -markup-rows.
#
# Two things lived here badly before: ad-hoc `sed` escaping (present in the
# spotify popup, absent everywhere else, so a track or SSID containing `&`
# silently broke the row), and three separate hand-rolled progress bars that
# drew the same thing with different characters and different clamping.

# markup::escape <text> — make arbitrary text safe to interpolate.
#
# Two traps, both of which the old inline `sed` version stepped around only
# by luck. The ampersand rule must run first, or it re-escapes the
# ampersands the later rules introduce. And since Bash 5.2 an unescaped `&`
# in a substitution *replacement* means "the text that matched", so the
# replacements are written `\&` — plain `&lt;` turns `<tag>` into `<lt;tag>gt;`.
markup::escape() {
  local s=$1
  s=${s//&/\&amp;}
  s=${s//</\&lt;}
  s=${s//>/\&gt;}
  printf '%s' "$s"
}

# markup::span <text> <color> [alpha-percent] — wrap text in a coloured span.
markup::span() {
  local text=$1 color=$2 alpha=${3:-}
  if [[ -n $alpha ]]; then
    printf '<span foreground="%s" alpha="%s%%">%s</span>' "$color" "$alpha" "$text"
  else
    printf '<span foreground="%s">%s</span>' "$color" "$text"
  fi
}

markup::bold() { printf '<b>%s</b>' "$1"; }

# markup::clamp <value> <min> <max> — shared by every meter below. Written
# once because each of the three old bars clamped differently, and the
# spotify one could produce a negative `empty` count and emit a broken row.
markup::clamp() {
  local value=$1 min=$2 max=$3
  (( value < min )) && value=$min
  (( value > max )) && value=$max
  printf '%s' "$value"
}

# markup::repeat <char> <count> — N copies of a character, without the
# `printf '%0.s━' $(seq 1 "$n")` trick, which spawns a process and misbehaves
# when n is 0.
markup::repeat() {
  local char=$1 count=$2 out=""
  (( count <= 0 )) && { printf ''; return 0; }
  printf -v out '%*s' "$count" ''
  printf '%s' "${out// /$char}"
}

# markup::meter <percent> <color> [width] — a two-tone solid meter: the
# filled portion at full brightness, the remainder of the same glyph dimmed.
#
# Deliberately one glyph throughout rather than a fill/empty pair: stippled
# characters like ░ dither unpredictably at small point sizes.
markup::meter() {
  local pct=$1 color=$2 width=${3:-10} filled empty
  pct=$(markup::clamp "$pct" 0 100)
  filled=$(( pct * width / 100 ))
  empty=$(( width - filled ))
  printf '%s%s' \
    "$(markup::span "$(markup::repeat '━' "$filled")" "$color")" \
    "$(markup::span "$(markup::repeat '━' "$empty")" "$color" 25)"
}

# markup::track <percent> [width] — the player-style variant, where the
# remainder is a lighter rule rather than a dimmed span.
markup::track() {
  local pct=$1 width=${2:-22} filled empty
  pct=$(markup::clamp "$pct" 0 100)
  filled=$(( pct * width / 100 ))
  empty=$(( width - filled ))
  printf '%s%s' "$(markup::repeat '━' "$filled")" "$(markup::repeat '─' "$empty")"
}

# markup::duration <seconds> — m:ss, tolerating the fractional seconds
# playerctl reports and never rendering a negative time.
markup::duration() {
  local seconds=${1%.*}
  seconds=${seconds:-0}
  (( seconds < 0 )) && seconds=0
  printf '%d:%02d' $(( seconds / 60 )) $(( seconds % 60 ))
}
