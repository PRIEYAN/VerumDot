#!/usr/bin/env bash
# domain/power.sh — CPU power profile, and the session actions.
#
# power-profiles-daemon is the source of truth. The cached copy exists only
# so the bar can paint without a D-Bus round trip; it is never consulted
# when ppd can answer, because SUPER+P, the control centre and GNOME-style
# tools all drive ppd directly and the cache goes stale the moment one of
# them is used.
#
# The cache used to live at a fixed /tmp/waybar-performance-mode — a
# predictable path in a world-writable directory, and the wrong tree for
# something meant to survive a reboot. It is now ordinary state.

hypr::use core/guard core/log core/paths os/proc os/state ui/notify ui/waybar domain/fan

readonly -a POWER_MODES=(normal performance battery)
readonly POWER_STATE_KEY=power-mode

# Mode -> (ppd profile | cpupower governor | glyph | toast)
declare -Ag POWER_PROFILE=([normal]=balanced [performance]=performance [battery]=power-saver)
declare -Ag POWER_GOVERNOR=([normal]=ondemand [performance]=performance [battery]=powersave)
declare -Ag POWER_GLYPH=([normal]=$'' [performance]=$'' [battery]=$'')
declare -Ag POWER_TOAST=([normal]='ツ' [performance]='(ᗒᗣᗕ)՞' [battery]='(˶ᵔ ᵕ ᵔ˶)')

# power::mode — the current mode, from ppd when available.
power::mode() {
  local profile
  if guard::has powerprofilesctl && profile=$(proc::capture powerprofilesctl get); then
    case $profile in
      performance) printf 'performance'; return 0 ;;
      power-saver) printf 'battery';     return 0 ;;
      balanced)    printf 'normal';      return 0 ;;
    esac
  fi
  state::get_enum "$POWER_STATE_KEY" normal "${POWER_MODES[@]}"
}

# power::set_mode <mode> — apply, cache, and tell everything that cares.
power::set_mode() {
  local mode=$1
  guard::one_of "$mode" "${POWER_MODES[@]}" >/dev/null \
    || { log::error "unknown power mode: $mode"; return 2; }

  state::set "$POWER_STATE_KEY" "$mode"

  if guard::has powerprofilesctl; then
    proc::quiet powerprofilesctl set "${POWER_PROFILE[$mode]}"
  elif guard::has cpupower; then
    # Needs root, unlike the D-Bus path, so it is the fallback rather than
    # the default — and it fights ppd over the same intel_pstate driver if
    # both are present.
    proc::quiet sudo cpupower frequency-set -g "${POWER_GOVERNOR[$mode]}"
  else
    log::warn "no power profile backend (install power-profiles-daemon)"
  fi

  # The fan setting is expressed relative to the power mode, so a mode change
  # has to re-resolve it. Not an error when the machine has no hp-wmi fan.
  fan::apply || true

  waybar::refresh battery
  notify::transient perf-mode "${POWER_TOAST[$mode]}"
}

# power::next_mode — normal -> performance -> battery -> normal.
power::next_mode() {
  case "$(power::mode)" in
    normal)      printf 'performance' ;;
    performance) printf 'battery' ;;
    *)           printf 'normal' ;;
  esac
}

power::cycle() { power::set_mode "$(power::next_mode)"; }

# ---------------------------------------------------------------------------
# Session actions
# ---------------------------------------------------------------------------
# Named, so that the power menu dispatches on an action rather than on a
# glyph. Every one of these is irreversible, which is why the menu refuses
# to guess at an unrecognised selection.
power::shutdown() { exec systemctl poweroff; }
power::reboot()   { exec systemctl reboot; }
power::logout()   { exec hyprctl dispatch exit; }
power::lock()     { exec hyprlock -c "$HYPR_HYPRLOCK_CONF"; }
