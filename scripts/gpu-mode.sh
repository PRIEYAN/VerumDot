#!/usr/bin/env bash
# GPU-mode module for eww. Drives supergfxctl to switch between:
#   Integrated  -> only the Intel iGPU is powered; the NVIDIA dGPU is off
#   Hybrid      -> Intel iGPU + NVIDIA dGPU (PRIME render-offload available)
#
# Subcommands:
#   (none)      emit JSON {text,tooltip,class,mode} for the bar/poll
#   get         print the raw current mode (Integrated|Hybrid|...)
#   set <mode>  request a switch to Integrated|Hybrid, then push_eww + notify
#   init        seed the eww gpu_* vars at startup (no poll-interval lag)
#
# Switching modes with supergfxctl requires ending the graphical session, so
# `set` only asks the daemon and tells the user to log out — it never forces it.
# If supergfxd/supergfxctl is missing we degrade gracefully to an "n/a" state.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/json.sh"

# Nerd Font glyphs (printf'd from UTF-8 bytes so the Private-Use-Area chars
# survive editing/encoding round-trips, matching performance-mode.sh):
#   chip     U+F0EE0 (integrated / single GPU)
#   expansion U+F08AE (hybrid / dual GPU)
G_IGPU=$(printf '\xf3\xb0\xbb\xa0')
G_HYBRID=$(printf '\xf3\xb0\xa2\xae')

have_supergfx() { command -v supergfxctl >/dev/null 2>&1; }

# Current mode as reported by the daemon; empty if unavailable.
get_mode() {
  have_supergfx || return 1
  supergfxctl -g 2>/dev/null | tr -d '[:space:]'
}

# emit <text> <tooltip> <class> <mode>
emit() {
  printf '{"text":%s,"tooltip":%s,"class":%s,"mode":%s}\n' \
    "$(json_str "$1")" "$(json_str "$2")" "$(json_str "$3")" "$(json_str "$4")"
}

status_json() {
  local mode
  mode=$(get_mode) || { emit "$G_IGPU" "GPU switching unavailable (supergfxctl not found)" "na" "na"; return; }
  case "$mode" in
    Integrated)
      emit "$G_IGPU" "GPU: Integrated only (Intel)" "integrated" "Integrated" ;;
    Hybrid)
      emit "$G_HYBRID" "GPU: Hybrid (Intel + NVIDIA)" "hybrid" "Hybrid" ;;
    ""|*)
      # AsusMux / Dedicated / Vfio / Egpu or unknown — surface it honestly.
      emit "$G_HYBRID" "GPU: ${mode:-unknown}" "hybrid" "${mode:-unknown}" ;;
  esac
}

# Push current state into eww's gpu_* vars so the bar reflects it instantly.
push_eww() {
  local json
  json=$(status_json)
  eww update \
    "gpu_text=$(printf '%s' "$json" | jq -r '.text // ""')" \
    "gpu_class=$(printf '%s' "$json" | jq -r '.class // ""')" \
    "gpu_tooltip=$(printf '%s' "$json" | jq -r '.tooltip // ""')" \
    "gpu_mode=$(printf '%s' "$json" | jq -r '.mode // ""')" \
    >/dev/null 2>&1
}

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send "$1" "$2" 2>/dev/null
}

case "$1" in
  get)
    get_mode
    ;;
  set)
    target="$2"
    case "$target" in
      Integrated|Hybrid) : ;;
      *) echo "usage: gpu-mode.sh set Integrated|Hybrid" >&2; exit 2 ;;
    esac
    if ! have_supergfx; then
      notify "GPU switch failed" "supergfxctl is not installed"
      exit 1
    fi
    current=$(get_mode)
    if [ "$current" = "$target" ]; then
      notify "GPU mode" "Already in ${target} mode"
      push_eww
      exit 0
    fi
    # supergfxctl returns the action needed (e.g. "reboot"/"logout"/"none").
    # It requires no sudo when supergfxd is running; on some setups the user
    # must be in the appropriate group. Capture stderr for the notification.
    if out=$(supergfxctl -m "$target" 2>&1); then
      case "$target" in
        Integrated) msg="Switched to Integrated (Intel only). Log out to apply." ;;
        Hybrid)     msg="Switched to Hybrid (Intel + NVIDIA). Log out to apply." ;;
      esac
      notify "GPU mode → ${target}" "$msg"
      push_eww
    else
      notify "GPU switch failed" "${out:-supergfxctl error}"
      exit 1
    fi
    ;;
  init)
    push_eww
    ;;
  *)
    status_json
    ;;
esac
