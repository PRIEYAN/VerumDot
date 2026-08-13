#!/usr/bin/env bash
#
#   VerumDot — one command, fresh machine.
#
#     bash <(curl -fsSL https://github.com/PRIEYAN/VerumDot/raw/main/install.sh)
#
#   Clones the rice, then hands over to setup.sh, which installs every package
#   and deploys the config. Any flag you pass is forwarded:
#
#     bash <(curl -fsSL .../install.sh) --auto      # zero questions
#     bash <(curl -fsSL .../install.sh) --dry-run   # show the plan only
#
set -uo pipefail

REPO="https://github.com/PRIEYAN/VerumDot.git"
SRC="${XDG_DATA_HOME:-$HOME/.local/share}/VerumDot"

# ── style (same grammar as setup.sh: black canvas, white ink, red glow) ──
COLOR=1; [[ -t 1 && -z "${NO_COLOR:-}" ]] || COLOR=0
TRUECOLOR=0; case "${COLORTERM:-}" in truecolor|24bit) TRUECOLOR=1 ;; esac
_fg() {
  (( COLOR )) || return 0
  if (( TRUECOLOR )); then printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"
  else printf '\033[38;5;%dm' $(( 16 + 36*($1*5/255) + 6*($2*5/255) + ($3*5/255) )); fi
}
if (( COLOR )); then
  RST=$'\033[0m'; BOLD=$'\033[1m'
  INK="$(_fg 255 255 255)"; GREY="$(_fg 138 138 138)"; VOID="$(_fg 74 74 74)"
  RED="$(_fg 224 27 27)"; RED_HOT="$(_fg 255 59 48)"
else
  RST=""; BOLD=""; INK=""; GREY=""; VOID=""; RED=""; RED_HOT=""
fi

BANNER=(
"█   █ █████ ████  █   █ █   █ ████   ███  █████"
"█   █ █     █   █ █   █ ██ ██ █   █ █   █   █  "
"█   █ ████  ████  █   █ █ █ █ █   █ █   █   █  "
" █ █  █     █  █  █   █ █   █ █   █ █   █   █  "
"  █   █████ █   █  ███  █   █ ████   ███    █  "
)

banner() {
  local cols pad row line
  cols="$(tput cols 2>/dev/null || echo 80)"; (( cols > 100 )) && cols=100
  pad=$(( (cols - 47) / 2 )); (( pad < 0 )) && pad=0
  printf '\n'
  printf '%*s%s%s%s\n' "$pad" '' "$(_fg 60 6 6)" "${BANNER[0]//█/▄}" "$RST"
  for row in 0 1 2 3 4; do
    case $row in
      0|4) line="$(_fg 190 18 18)" ;;
      1|3) line="$(_fg 232 32 28)" ;;
      *)   line="$(_fg 255 62 52)" ;;
    esac
    printf '%*s%s%s%s\n' "$pad" '' "$line" "${BANNER[row]}" "$RST"
  done
  printf '%*s%s%s%s\n' "$pad" '' "$(_fg 60 6 6)" "${BANNER[4]//█/▀}" "$RST"
  local sub="T R U T H   I N   B L A C K .   N O T H I N G   E L S E ."
  pad=$(( (cols - ${#sub}) / 2 )); (( pad < 0 )) && pad=0
  printf '%*s%s%s%s\n\n' "$pad" '' "$GREY" "$sub" "$RST"
}

log()  { printf '   %s→%s %s%s%s\n' "$RED_HOT" "$RST" "$GREY" "$*" "$RST"; }
ok()   { printf '   %s✓%s %s%s%s\n' "$RED_HOT" "$RST" "$INK" "$*" "$RST"; }
die()  { printf '\n   %s✗ %s%s\n\n' "$RED" "$*" "$RST" >&2; exit 1; }

# curl | bash still deserves a keyboard
if [[ ! -t 0 ]] && { : </dev/tty; } 2>/dev/null; then exec </dev/tty; fi

clear 2>/dev/null
banner

[[ "$(id -u)" -eq 0 ]] && die "do not run as root — setup.sh asks for sudo only where it needs it"
command -v pacman >/dev/null 2>&1 || die "VerumDot targets Arch and derivatives (pacman not found)"

if ! command -v git >/dev/null 2>&1; then
  log "git is missing — installing it first"
  sudo pacman -Sy --needed --noconfirm git || die "could not install git"
fi

if [[ -d "$SRC/.git" ]]; then
  log "updating existing clone at ${SRC/#$HOME/\~}"
  git -C "$SRC" pull --ff-only || log "pull failed — using the checkout as it is"
else
  log "cloning VerumDot → ${SRC/#$HOME/\~}"
  rm -rf "$SRC"
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 "$REPO" "$SRC" || die "clone failed — check your network"
fi
ok "source ready"

chmod +x "$SRC/setup.sh" 2>/dev/null
printf '\n   %shanding over to setup.sh%s\n' "$VOID" "$RST"
exec "$SRC/setup.sh" "$@"
