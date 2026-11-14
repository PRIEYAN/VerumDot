#!/usr/bin/env bash
# domain/powerprofile.sh — power backend and cached mode, without UI or fan policy.
# Both the fan policy and the power workflow depend on this module.

hypr::use core/guard core/log os/proc os/state

readonly -a POWER_MODES=(normal performance battery)
readonly POWER_STATE_KEY=power-mode

# Mode -> power-profiles-daemon profile / cpupower governor
declare -Ag POWER_PROFILE=([normal]=balanced [performance]=performance [battery]=power-saver)
declare -Ag POWER_GOVERNOR=([normal]=ondemand [performance]=performance [battery]=powersave)
# powerprofile::mode — the current mode, from ppd when available.
powerprofile::mode() {
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

# Update the cache only after the backend accepts the requested mode.
# proc::* and state::* form the replaceable system boundary for tests.
powerprofile::set() {
  local mode=$1
  guard::one_of "$mode" "${POWER_MODES[@]}" >/dev/null \
    || { log::error "unknown power mode: $mode"; return 2; }

  if guard::has powerprofilesctl; then
    proc::quiet powerprofilesctl set "${POWER_PROFILE[$mode]}" || {
      log::error "power-profiles-daemon refused mode: $mode"
      return 1
    }
  elif guard::has cpupower; then
    proc::quiet sudo cpupower frequency-set -g "${POWER_GOVERNOR[$mode]}" || {
      log::error "cpupower refused mode: $mode"
      return 1
    }
  else
    log::error "no power profile backend (install power-profiles-daemon)"
    return 1
  fi
  state::set "$POWER_STATE_KEY" "$mode"
}
