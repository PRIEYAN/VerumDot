#!/usr/bin/env bash
# Fan control for hp-wmi laptops (HP Victus).
#
# The hardware gives us two fan states and no duty cycle:
#   pwm1_enable = 2   BIOS automatic curve. How hard that curve pushes follows
#                     the ACPI platform profile, which power-profiles-daemon
#                     sets from the power mode (quiet / balanced / performance).
#   pwm1_enable = 0   both fans pinned at maximum.
#
# At idle all three BIOS curves settle at the same RPM, so the profile alone is
# not a perceptible fan control — pinning is what you actually hear. Hence the
# setting here is three-way:
#
#   auto     follow the power mode — battery and normal run the BIOS curve,
#            performance pins the fans at max
#   normal   always the BIOS curve, even in performance mode
#   max      always pinned at max, even in battery mode
#
# The choice persists across reboots; `apply` re-asserts it and is what the
# power-mode switch and the control centre call after changing modes.
#
# Usage: fan-control.sh get | set <auto|normal|max> | cycle | apply | status

set -uo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/hypr"
state_file="${state_dir}/fan-mode"
mode_file=/tmp/waybar-performance-mode

# The hwmon number is assigned at probe time and moves between boots, so match
# on the driver name rather than hardcoding hwmon4.
find_pwm() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    [[ -r "$h/name" ]] || continue
    [[ "$(<"$h/name")" == "hp" ]] || continue
    [[ -e "$h/pwm1_enable" ]] || continue
    printf '%s' "$h/pwm1_enable"
    return 0
  done
  return 1
}

fan_setting() {
  local m
  m=$(cat "$state_file" 2>/dev/null) || m=auto
  case "$m" in auto|normal|max) printf '%s' "$m" ;; *) printf 'auto' ;; esac
}

# power-profiles-daemon is the source of truth: SUPER+P, the control centre and
# GNOME-style tools all drive it, whereas /tmp/waybar-performance-mode is only a
# cache waybar paints from and can go stale. Fall back to it when ppd is absent.
power_mode() {
  local p m
  if p=$(powerprofilesctl get 2>/dev/null); then
    case "$p" in
      performance) printf 'performance'; return ;;
      power-saver) printf 'battery';     return ;;
      balanced)    printf 'normal';      return ;;
    esac
  fi
  m=$(cat "$mode_file" 2>/dev/null) || m=normal
  case "$m" in normal|performance|battery) printf '%s' "$m" ;; *) printf 'normal' ;; esac
}

# The pwm1_enable value the current (fan setting, power mode) pair resolves to.
target_pwm() {
  case "$(fan_setting)" in
    max)    printf '0' ;;
    normal) printf '2' ;;
    *)      [[ "$(power_mode)" == "performance" ]] && printf '0' || printf '2' ;;
  esac
}

write_pwm() {
  local want=$1 pwm
  pwm=$(find_pwm) || {
    echo "fan-control: no hp-wmi fan node — this machine has no supported fan control" >&2
    return 1
  }
  # Writing the value it already holds still round-trips through WMI, which is
  # slow and occasionally noisy; skip it.
  [[ "$(cat "$pwm" 2>/dev/null)" == "$want" ]] && return 0
  # Brace-wrap the redirect: a failed redirection is reported by the shell, not
  # by printf, so `printf ... 2>/dev/null` alone still leaks "Permission denied".
  if { printf '%s' "$want" >"$pwm"; } 2>/dev/null; then
    return 0
  fi
  echo "fan-control: $pwm is not writable — install apps/udev/99-hp-fan.rules" >&2
  return 1
}

case "${1:-status}" in
  get)
    fan_setting; echo
    ;;

  set)
    want="${2:-}"
    case "$want" in
      auto|normal|max) ;;
      *) echo "usage: fan-control.sh set <auto|normal|max>" >&2; exit 2 ;;
    esac
    mkdir -p "$state_dir"
    printf '%s' "$want" >"$state_file"
    write_pwm "$(target_pwm)" || exit 1
    if command -v notify-send >/dev/null 2>&1; then
      case "$want" in
        max)    msg="Fan · max" ;;
        normal) msg="Fan · normal" ;;
        auto)   msg="Fan · auto ($(power_mode))" ;;
      esac
      notify-send -t 1500 -h string:x-canonical-private-synchronous:fan-mode "$msg"
    fi
    ;;

  cycle)
    case "$(fan_setting)" in
      auto)   next=normal ;;
      normal) next=max ;;
      *)      next=auto ;;
    esac
    exec "$0" set "$next"
    ;;

  apply)
    # Re-assert the saved setting — called after a power-mode change and at
    # login, since pwm1_enable resets to the BIOS default on every boot.
    write_pwm "$(target_pwm)" || exit 1
    ;;

  status)
    pwm=$(find_pwm) || { echo "unsupported"; exit 1; }
    rpm1=0; rpm2=0
    [[ -r "${pwm%/*}/fan1_input" ]] && rpm1=$(<"${pwm%/*}/fan1_input")
    [[ -r "${pwm%/*}/fan2_input" ]] && rpm2=$(<"${pwm%/*}/fan2_input")
    printf 'setting=%s mode=%s pwm1_enable=%s rpm=%s/%s\n' \
      "$(fan_setting)" "$(power_mode)" "$(cat "$pwm" 2>/dev/null)" "$rpm1" "$rpm2"
    ;;

  *)
    echo "usage: fan-control.sh get | set <auto|normal|max> | cycle | apply | status" >&2
    exit 2
    ;;
esac
