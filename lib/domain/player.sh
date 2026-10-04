#!/usr/bin/env bash
# domain/player.sh — MPRIS playback, via playerctl.

hypr::use core/guard core/paths os/proc ui/waybar ui/markup

readonly PLAYER_NAME="${PLAYER_NAME:-spotify}"
readonly PLAYER_ART_CACHE="${HYPR_CACHE_DIR}/player-art.jpg"
readonly PLAYER_ART_URL_FILE="${PLAYER_ART_CACHE}.url"
readonly PLAYER_ART_FALLBACK="${HYPR_ROFI}/spotify-fallback.png"

player::available() { guard::has playerctl; }

player::_meta() { proc::capture playerctl -p "$PLAYER_NAME" metadata "$1"; }

player::status()   { proc::capture_or Stopped playerctl -p "$PLAYER_NAME" status; }
player::playing()  { [[ $(player::status) == Playing ]]; }
player::active()   { local s; s=$(player::status); [[ -n $s && $s != Stopped ]]; }

player::title()  { proc::capture_or Unknown playerctl -p "$PLAYER_NAME" metadata xesam:title; }
player::artist() { proc::capture_or Unknown playerctl -p "$PLAYER_NAME" metadata xesam:artist; }

# player::length — track length in whole seconds, never zero (callers divide
# by it to compute a progress percentage).
player::length() {
  local micros; micros=$(proc::capture_or 0 playerctl -p "$PLAYER_NAME" metadata mpris:length)
  [[ $micros =~ ^[0-9]+$ ]] || micros=0
  local seconds=$(( micros / 1000000 ))
  (( seconds < 1 )) && seconds=1
  printf '%s' "$seconds"
}

player::position() {
  local pos; pos=$(proc::capture_or 0 playerctl -p "$PLAYER_NAME" position)
  printf '%s' "${pos%.*}"
}

player::progress_percent() {
  local pos=$(( $(player::position) )) len=$(( $(player::length) ))
  printf '%s' "$(markup::clamp $(( pos * 100 / len )) 0 100)"
}

# ---- transport ------------------------------------------------------------
# Each repaints the bar, so no caller has to remember which signal to poke —
# which is how the old spotify popup ended up poking the battery module.
player::_do() { proc::quiet playerctl -p "$PLAYER_NAME" "$@"; waybar::refresh spotify; }
player::play_pause() { player::_do play-pause; }
player::next()       { player::_do next; }
player::previous()   { player::_do previous; }

# ---- cover art ------------------------------------------------------------
# player::art — a local path to the current cover, or the fallback.
#
# Never blocks on the network. A cache miss returns whatever art is already
# on disk and fetches the new one in the background, so the correct cover is
# ready the next time the popup opens. The old inline curl stalled the whole
# popup for its full --max-time on every miss.
player::art() {
  local url; url=$(player::_meta mpris:artUrl)

  case $url in
    file://*)
      local src=${url#file://}
      [[ -f $src ]] && { printf '%s' "$src"; return 0; }
      ;;
    http://*|https://*)
      local cached; cached=$(proc::capture_or '' cat "$PLAYER_ART_URL_FILE")
      if [[ $cached != "$url" || ! -s $PLAYER_ART_CACHE ]]; then
        player::_fetch_art "$url" &
        disown 2>/dev/null || true
      fi
      [[ -s $PLAYER_ART_CACHE ]] && { printf '%s' "$PLAYER_ART_CACHE"; return 0; }
      ;;
  esac

  player::_ensure_fallback
  printf '%s' "$PLAYER_ART_FALLBACK"
}

player::_fetch_art() {
  local url=$1 tmp="${PLAYER_ART_CACHE}.$$.tmp"
  mkdir -p -- "$HYPR_CACHE_DIR"
  if curl -fsSL --max-time 5 "$url" -o "$tmp" 2>/dev/null && [[ -s $tmp ]]; then
    mv -f -- "$tmp" "$PLAYER_ART_CACHE"
    printf '%s' "$url" >"$PLAYER_ART_URL_FILE"
  else
    rm -f -- "$tmp"
  fi
}

# A 1x1 dark PNG, so the popup's icon slot is never empty (rofi draws a
# broken-image box for a missing file).
player::_ensure_fallback() {
  [[ -s $PLAYER_ART_FALLBACK ]] && return 0
  printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' \
    | base64 -d >"$PLAYER_ART_FALLBACK" 2>/dev/null || true
}
