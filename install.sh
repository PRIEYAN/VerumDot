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

# Parse before any package, filesystem or network mutation.
DRYRUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRYRUN=1 ;;
    -h|--help)
      cat <<'HELP'
VerumDot bootstrap — fetch main and run setup.sh as your normal user.
  --auto                 full install without the wizard
  --config               deploy config only
  --packages             install dependencies only
  --dry-run              show bootstrap actions without writing or fetching
  --no-aur               skip AUR packages (including Spotify and VS Code)
  --no-nvim              skip the Neovim overlay
  --no-services          leave services alone
  --no-lid               leave the lid policy alone
  --no-theme             skip GTK / Qt theme setup
  --no-anim --no-color    plain output
Run ./setup.sh --dry-run in a clone to see the complete package/config plan.
HELP
      exit 0 ;;
    --auto|-y|--yes|--config|--config-only|--packages|--packages-only|--no-aur|--no-nvim|--no-services|--no-lid|--no-theme|--no-anim|--no-color) ;;
    *) die "unknown flag: $arg (try --help)" ;;
  esac
done

if (( DRYRUN )); then
  log "would fetch main from $REPO into $SRC, then run setup.sh $*"
  log "no packages, clone, update, or config writes performed"
  exit 0
fi

banner
[[ "$(id -u)" -eq 0 ]] && die "do not run as root — setup.sh asks for sudo only where it needs it"

if ! command -v git >/dev/null 2>&1; then
  command -v pacman >/dev/null 2>&1 || die "pacman is needed to install git"
  command -v sudo >/dev/null 2>&1 || die "install sudo and grant your user sudo access first"
  log "git is missing — upgrading the system and installing it first"
  sudo pacman -Syu --needed --noconfirm git || die "could not install git"
fi

if [[ -d "$SRC/.git" ]]; then
  [[ "$(git -C "$SRC" branch --show-current)" == main ]] || die "$SRC is not on main; move it aside or use its setup.sh directly"
  [[ -z "$(git -C "$SRC" status --porcelain)" ]] || die "$SRC has local changes; save them before updating"
  origin="$(git -C "$SRC" remote get-url origin)" || die "source clone has no origin"
  case "${origin,,}" in
    https://github.com/prieyan/verumdot|https://github.com/prieyan/verumdot.git|git@github.com:prieyan/verumdot.git) ;;
    *) die "$SRC belongs to another repository; move it aside first" ;;
  esac
  log "updating main at ${SRC/#$HOME/\~}"
  git -C "$SRC" fetch origin main || die "fetch failed; existing checkout left in place"
  # Do not silently install local commits that have not reached main.
  git -C "$SRC" merge-base --is-ancestor HEAD FETCH_HEAD || die "local main diverges from origin/main; resolve it before setup"
  git -C "$SRC" merge --ff-only FETCH_HEAD || die "could not fast-forward main"
else
  [[ ! -e "$SRC" && ! -L "$SRC" ]] || die "$SRC already exists and is not a git clone; move it aside first"
  log "cloning main → ${SRC/#$HOME/\~}"
  mkdir -p "$(dirname "$SRC")" || die "cannot create source parent directory"
  git clone --depth 1 --branch main --single-branch "$REPO" "$SRC" || die "clone failed — check your network"
fi
[[ -f "$SRC/setup.sh" ]] || die "setup.sh is missing from the checkout"
ok "source ready"
exec bash "$SRC/setup.sh" "$@"
