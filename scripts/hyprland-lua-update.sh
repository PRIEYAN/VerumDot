#!/usr/bin/env bash
# One command: update Hyprland and move this rice onto the Lua config.
#
#   scripts/hyprland-lua-update.sh               upgrade + verify + switch
#   scripts/hyprland-lua-update.sh --no-upgrade  skip the package upgrade
#   scripts/hyprland-lua-update.sh --check       verify only, change nothing
#   scripts/hyprland-lua-update.sh --rollback    back to hyprland.conf
#
# Steps, each one gating the next:
#   1. upgrade the Hyprland stack (pacman -Syu: Arch has no partial upgrades)
#   2. confirm the installed Hyprland has the Lua config engine
#   3. Hyprland --verify-config on hyprland.lua (and every config/ module)
#   4. run the keybind tests (Lua cheat sheet == legacy cheat sheet)
#   5. switch the live session: `hyprctl reload full-reset`
#   6. only once Lua is live, park the legacy hyprlang files in legacy/
#   7. reload waybar (new workspace on-click) and restart hypridle (new dpms hook)
#
# Nothing is deleted: --rollback moves legacy/ back and disables hyprland.lua.
# See LUA_MIGRATION.md.

set -uo pipefail

HYPR_HOME=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
LEGACY_DIR="$HYPR_HOME/legacy"
LEGACY_FILES=(hyprland.conf hypr.conf workspaces.conf)
LUA_ENTRY="$HYPR_HOME/hyprland.lua"
STACK=(hyprland hyprlock hypridle hyprpaper hyprcursor hyprutils hyprlang aquamarine
       xdg-desktop-portal-hyprland hyprpolkitagent lua)

if [[ -t 1 ]]; then B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' D=$'\e[2m' N=$'\e[0m'
else B="" G="" Y="" R="" D="" N=""; fi
step() { printf '\n%s==>%s %s%s%s\n' "$B" "$N" "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '  %s✗%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() { sed -n '2,8s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }

UPGRADE=1 MODE=migrate
for a in "$@"; do
  case $a in
    --no-upgrade) UPGRADE=0 ;;
    --check)      MODE=check; UPGRADE=0 ;;
    --rollback)   MODE=rollback ;;
    -h|--help)    usage; exit 0 ;;
    *)            usage >&2; die "unknown option: $a" ;;
  esac
done

running()  { [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl -j version >/dev/null 2>&1; }
live_lua() { [[ "$(hyprctl eval 'return nil' 2>/dev/null | tr -d '[:space:]')" == ok ]]; }

# verify_lua — Hyprland's own parser over the whole Lua tree. Prints the
# verdict; returns non-zero unless it is exactly "config ok".
verify_lua() {
  local out verdict
  out=$(timeout 60 Hyprland --verify-config -c "$LUA_ENTRY" 2>&1)
  verdict=$(sed -n '/Config parsing result/,$p' <<<"$out" | tail -n +2 | sed '/^$/d')
  [[ -n $verdict ]] || verdict=$(tail -n 5 <<<"$out")
  if [[ $verdict == "config ok" ]]; then ok "hyprland.lua: config ok"; return 0; fi
  printf '%s\n' "$verdict" | sed 's/^/    /' >&2
  return 1
}

restart_helpers() {
  if pgrep -x waybar >/dev/null; then
    pkill -SIGUSR2 -x waybar && ok "waybar reloaded"
  fi
  if pgrep -x hypridle >/dev/null; then
    pkill -x hypridle; sleep 0.3
    setsid -f hypridle >/dev/null 2>&1 && ok "hypridle restarted"
  fi
}

# ---------------------------------------------------------------------------
rollback() {
  step "Rolling back to the hyprlang config"
  local f moved=0
  for f in "${LEGACY_FILES[@]}"; do
    if [[ -f "$LEGACY_DIR/$f" ]]; then
      [[ -e "$HYPR_HOME/$f" ]] && die "$HYPR_HOME/$f already exists; refusing to overwrite it"
      mv -- "$LEGACY_DIR/$f" "$HYPR_HOME/$f" && moved=1
    fi
  done
  (( moved )) && ok "restored ${LEGACY_FILES[*]}"
  rmdir "$LEGACY_DIR" 2>/dev/null || true
  [[ -f "$HYPR_HOME/hyprland.conf" ]] || die "no hyprland.conf to roll back to"
  if [[ -f $LUA_ENTRY ]]; then
    mv -- "$LUA_ENTRY" "$LUA_ENTRY.disabled" && ok "hyprland.lua → hyprland.lua.disabled"
  fi
  if running; then
    hyprctl reload full-reset >/dev/null && ok "live session switched back to hyprland.conf"
    restart_helpers
  fi
  printf '\n%sRe-run without --rollback to switch to Lua again.%s\n' "$D" "$N"
}

# ---------------------------------------------------------------------------
migrate() {
  cd "$HYPR_HOME" || die "cannot enter $HYPR_HOME"
  # A previous rollback leaves the entry disabled; bring it back.
  if [[ ! -f $LUA_ENTRY && -f "$LUA_ENTRY.disabled" ]]; then
    mv -- "$LUA_ENTRY.disabled" "$LUA_ENTRY" && ok "re-enabled hyprland.lua"
  fi
  [[ -f $LUA_ENTRY ]] || die "$LUA_ENTRY is missing — pull the latest rice first"

  if (( UPGRADE )); then
    step "1/7  Upgrading the Hyprland stack"
    command -v pacman >/dev/null || die "pacman not found; upgrade Hyprland with your package manager, then use --no-upgrade"
    printf '  %s%s%s\n' "$D" "sudo pacman -Syu --needed ${STACK[*]}" "$N"
    sudo pacman -Syu --needed "${STACK[@]}" || die "package upgrade failed — nothing else was changed"
    ok "packages up to date"
  else
    step "1/7  Package upgrade skipped"
  fi

  step "2/7  Checking the installed Hyprland"
  command -v Hyprland >/dev/null || die "Hyprland is not installed"
  ok "$(Hyprland --version 2>/dev/null | head -n 1)"
  if ! grep -qaF 'Using lua config found at' "$(readlink -f "$(command -v Hyprland)")"; then
    die "this Hyprland build has no Lua config engine — upgrade it (drop --no-upgrade)"
  fi
  ok "Lua config engine present"
  [[ -d /usr/share/hypr/stubs ]] && ok "editor stubs: /usr/share/hypr/stubs (wired up by .luarc.json)"

  step "3/7  Verifying hyprland.lua"
  verify_lua || die "hyprland.lua has errors — fix them (the live session was not touched)"

  step "4/7  Running the keybind tests"
  if command -v python3 >/dev/null; then
    python3 -m unittest -q "$HYPR_HOME/tests/test_keybinds.py" 2>&1 | tail -n 3 | sed 's/^/    /'
    (( PIPESTATUS[0] == 0 )) || die "keybind tests failed"
    ok "cheat sheet reads the Lua config"
  else
    warn "python3 not found; skipped"
  fi

  if [[ $MODE == check ]]; then
    printf '\n%sCheck passed. Nothing was changed.%s\n' "$G" "$N"
    return 0
  fi

  step "5/7  Switching the live session"
  if running; then
    if live_lua; then
      hyprctl reload >/dev/null && ok "already on Lua; reloaded"
    else
      hyprctl reload full-reset >/dev/null
      sleep 0.5
      if live_lua; then
        ok "live session now runs hyprland.lua"
      else
        warn "the running compositor did not switch engines (likely an older binary"
        warn "still in memory). Log out and back in, then re-run this script."
        warn "Legacy files left in place so the current session keeps working."
        return 0
      fi
    fi
  else
    ok "Hyprland not running — hyprland.lua is used at the next login"
  fi

  step "6/7  Parking the legacy hyprlang files"
  local f parked=()
  mkdir -p "$LEGACY_DIR"
  for f in "${LEGACY_FILES[@]}"; do
    if [[ -f "$HYPR_HOME/$f" ]]; then
      [[ -e "$LEGACY_DIR/$f" ]] && die "$LEGACY_DIR/$f already exists; refusing to overwrite it"
      mv -- "$HYPR_HOME/$f" "$LEGACY_DIR/$f" && parked+=("$f")
    fi
  done
  if (( ${#parked[@]} )); then ok "moved ${parked[*]} → legacy/"; else ok "already parked"; fi
  rmdir "$LEGACY_DIR" 2>/dev/null || true

  step "7/7  Reloading helpers"
  if running; then restart_helpers; else ok "nothing running"; fi

  printf '\n%sDone.%s Hyprland now reads %s (modules in config/).\n' "$G$B" "$N" "$LUA_ENTRY"
  printf '%sEdit config/settings.lua for apps/monitor; see LUA_MIGRATION.md. Undo: %s --rollback%s\n' \
    "$D" "${BASH_SOURCE[0]}" "$N"
}

case $MODE in
  rollback) rollback ;;
  *)        migrate ;;
esac
