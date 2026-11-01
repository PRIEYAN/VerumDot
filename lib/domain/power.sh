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

hypr::use core/guard core/log core/paths os/proc os/state ui/notify ui/waybar domain/powerprofile domain/fan

# Public lookup consumed by the Waybar entry point.
# shellcheck disable=SC2034
declare -Ag POWER_GLYPH=([normal]=$'' [performance]=$'' [battery]=$'')
declare -Ag POWER_TOAST=([normal]='ツ' [performance]='(ᗒᗣᗕ)՞' [battery]='(˶ᵔ ᵕ ᵔ˶)')

# Keep the public entry point stable for Waybar and menu callers.
power::mode() { powerprofile::mode; }

# power::set_mode <mode> — apply, cache, and tell everything that cares.
power::set_mode() {
  local mode=$1
  powerprofile::set "$mode" || return $?

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
