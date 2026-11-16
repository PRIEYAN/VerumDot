#!/usr/bin/env bash
#
#   VerumDot — installer
#   Truth in black. Nothing else.
#
#   One command, fresh machine:
#     bash <(curl -fsSL https://raw.githubusercontent.com/PRIEYAN/VerumDot/main/install.sh)
#
#   From a local clone:
#     ./setup.sh              interactive wizard (packages + config)
#     ./setup.sh --auto       no questions, install everything, sane defaults
#     ./setup.sh --update     refresh rice and install missing dependencies
#     ./setup.sh --packages   dependencies only
#     ./setup.sh --config     deploy config / theme only
#     ./setup.sh --dry-run    show the plan, touch nothing
#     ./setup.sh --help
#
#   The rice lives at ~/.config/hypr once installed.
#
set -uo pipefail

VD_VERSION="2.1"
VD_REPO="https://github.com/PRIEYAN/VerumDot"

# ══ paths ══════════════════════════════════════════════════════════════
RICE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET="$XDG_CFG/hypr"
WAYBAR_CFG="$XDG_CFG/waybar"
NVIM_CFG="$XDG_CFG/nvim"
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/verumdot-install-$STAMP.log"

# ══ runtime flags ══════════════════════════════════════════════════════
MODE="wizard"          # wizard | auto | packages | config | update
ANIM=1
COLOR=1
DRYRUN=0
NO_AUR=0
LIST_PACKAGES=0
STEP_N=0
STEP_TOTAL=0

# ══ wizard answers (defaults = what --auto uses) ═══════════════════════
DO_PACKAGES=1
DO_CONFIG=1
SEL_GROUPS=(audio shot net power theme fonts apps aur)
PICK_TERM="kitty"
PICK_BROWSER="firefox"
PICK_FILES="nautilus"
PICK_EDITOR="code"
PICK_MONITOR=""
PICK_SCALE="1.0"
DO_LID=1
DO_THEME=1
DO_SERVICES=1
DO_NVIM=1
DO_AUR_HELPER=1
DO_SHELL=0
EXTRA_PKGS=()

# ══ facts discovered by preflight ══════════════════════════════════════
FACT_DISTRO="unknown"
FACT_PACMAN=0
FACT_AUR=""
FACT_GPU="unknown"
FACT_LAPTOP=0
FACT_NET=0
FACT_EXISTING=0
FACT_INPLACE=0
FACT_HYPR_RUNNING=0

# ══════════════════════════════════════════════════════════════════════
#  colour engine — truecolor when the terminal admits to it, 256 else
# ══════════════════════════════════════════════════════════════════════
COLS=80
_rgb256() { # r g b -> xterm-256 cube index
  printf '%d' $(( 16 + 36*($1*5/255) + 6*($2*5/255) + ($3*5/255) ))
}
_fg() { # r g b
  (( COLOR )) || return 0
  if (( TRUECOLOR )); then printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"
  else printf '\033[38;5;%dm' "$(_rgb256 "$1" "$2" "$3")"; fi
}
_bg() {
  (( COLOR )) || return 0
  if (( TRUECOLOR )); then printf '\033[48;2;%d;%d;%dm' "$1" "$2" "$3"
  else printf '\033[48;5;%dm' "$(_rgb256 "$1" "$2" "$3")"; fi
}

init_style() {
  COLS="$(tput cols 2>/dev/null || echo 80)"
  (( COLS > 100 )) && COLS=100
  (( COLS < 60  )) && COLS=60

  [[ -t 1 ]] || { COLOR=0; ANIM=0; }
  [[ -n "${NO_COLOR:-}" ]] && COLOR=0

  TRUECOLOR=0
  case "${COLORTERM:-}" in truecolor|24bit) TRUECOLOR=1 ;; esac

  if (( COLOR )); then
    RST=$'\033[0m'; BOLD=$'\033[1m'; REV=$'\033[7m'
    C_INK="$(_fg 255 255 255)"
    C_GREY="$(_fg 138 138 138)"
    C_DIM="$(_fg 74 74 74)"
    C_VOID="$(_fg 38 38 38)"
    C_RED="$(_fg 224 27 27)"
    C_RED_HOT="$(_fg 255 59 48)"
    C_RED_LIT="$(_fg 255 143 143)"
    C_RED_DARK="$(_fg 122 10 10)"
    C_OK="$(_fg 255 255 255)"
    C_WARN="$(_fg 255 176 46)"
    B_INK="$(_bg 255 255 255)"; B_VOID="$(_bg 0 0 0)"
    F_BLACK="$(_fg 0 0 0)"
  else
    RST=""; BOLD=""; REV=""
    C_INK=""; C_GREY=""; C_DIM=""; C_VOID=""; C_RED=""; C_RED_HOT=""
    C_RED_LIT=""; C_RED_DARK=""; C_OK=""; C_WARN=""
    B_INK=""; B_VOID=""; F_BLACK=""
  fi
}

hide_cursor() { (( COLOR )) && printf '\033[?25l'; }
show_cursor() { (( COLOR )) && printf '\033[?25h'; }
cleanup() { show_cursor; printf '%s' "$RST"; [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; return 0; }
trap cleanup EXIT
trap 'cleanup; printf "\n%s  aborted.%s\n" "$C_RED" "$RST"; exit 130' INT

# ══════════════════════════════════════════════════════════════════════
#  the red glow — VerumDot wordmark
# ══════════════════════════════════════════════════════════════════════
# 5x5 block glyphs, joined by one space column.
BANNER=(
"█   █ █████ ████  █   █ █   █ ████   ███  █████"
"█   █ █     █   █ █   █ ██ ██ █   █ █   █   █  "
"█   █ ████  ████  █   █ █ █ █ █   █ █   █   █  "
" █ █  █     █  █  █   █ █   █ █   █ █   █   █  "
"  █   █████ █   █  ███  █   █ ████   ███    █  "
)
BANNER_W=47

# glow_color <row> <col> <intensity 0-100> <sweep col or -1>
_glow_at() {
  local row=$1 col=$2 lvl=$3 sweep=$4
  local r g b
  # vertical falloff: rows 0 and 4 sit in the halo, row 2 is the core
  case $row in
    0|4) r=190; g=18;  b=18  ;;
    1|3) r=232; g=32;  b=28  ;;
    *)   r=255; g=62;  b=52  ;;
  esac
  if (( sweep >= 0 )); then
    local d=$(( col - sweep )); (( d < 0 )) && d=$(( -d ))
    if   (( d <= 1 )); then r=255; g=250; b=245
    elif (( d <= 3 )); then r=255; g=190; b=180
    elif (( d <= 6 )); then r=255; g=120; b=105
    fi
  fi
  r=$(( r * lvl / 100 )); g=$(( g * lvl / 100 )); b=$(( b * lvl / 100 ))
  _fg "$r" "$g" "$b"
}

# render_banner <intensity 0-100> <sweep col, -1 for none>
render_banner() {
  local lvl=$1 sweep=$2 pad row col ch out
  pad=$(( (COLS - BANNER_W) / 2 )); (( pad < 0 )) && pad=0
  local indent; printf -v indent '%*s' "$pad" ''

  # upper halo
  local halo="${BANNER[0]//█/▄}"
  out="$indent$(_glow_at 0 -1 $(( lvl * 22 / 100 )) -1)${halo}$RST"$'\n'

  for row in 0 1 2 3 4; do
    out+="$indent"
    for (( col=0; col<BANNER_W; col++ )); do
      ch="${BANNER[row]:col:1}"
      if [[ "$ch" == " " ]]; then out+=" "
      else out+="$(_glow_at "$row" "$col" "$lvl" "$sweep")█"; fi
    done
    out+="$RST"$'\n'
  done

  # lower halo
  halo="${BANNER[4]//█/▀}"
  out+="$indent$(_glow_at 4 -1 $(( lvl * 22 / 100 )) -1)${halo}$RST"$'\n'
  printf '%s' "$out"
}

banner() {
  local lines=7
  printf '\n'
  if (( ANIM )); then
    hide_cursor
    # ignite
    local lvl
    for lvl in 12 26 44 66 88 100; do
      render_banner "$lvl" -1
      printf '\033[%dA' "$lines"
      sleep 0.035
    done
    # white-hot sweep across the wordmark
    local s
    for (( s=-4; s<=BANNER_W+4; s+=5 )); do
      render_banner 100 "$s"
      printf '\033[%dA' "$lines"
      sleep 0.018
    done
    show_cursor
  fi
  render_banner 100 -1

  local sub="T R U T H   I N   B L A C K .   N O T H I N G   E L S E ."
  local pad=$(( (COLS - ${#sub}) / 2 )); (( pad < 0 )) && pad=0
  printf '%*s%s%s%s\n' "$pad" '' "$C_GREY" "$sub" "$RST"
  local tag="v$VD_VERSION"
  pad=$(( (COLS - ${#tag}) / 2 ))
  printf '%*s%s%s%s\n\n' "$pad" '' "$C_VOID" "$tag" "$RST"
  rule
}

# ══════════════════════════════════════════════════════════════════════
#  UI primitives
# ══════════════════════════════════════════════════════════════════════
repeat_ch() { # repeat_ch <count> <char>  — multibyte safe, unlike tr
  local n=$1 ch=$2 s
  (( n < 1 )) && { printf ''; return 0; }
  printf -v s '%*s' "$n" ''
  printf '%s' "${s// /$ch}"
}

rule() {
  local ch="${1:-─}" c="${2:-$C_VOID}"
  printf '%s%s%s\n' "$c" "$(repeat_ch "$COLS" "$ch")" "$RST"
}

headline() { # section header with step counter
  (( STEP_TOTAL > 0 )) && STEP_N=$(( STEP_N + 1 ))
  printf '\n'
  if (( STEP_TOTAL > 0 )); then
    printf '%s▐%s %s%02d%s%s/%02d%s  %s%s%s\n' \
      "$C_RED" "$RST" "$C_RED_HOT" "$STEP_N" "$C_DIM" "$C_DIM" "$STEP_TOTAL" "$RST" \
      "$BOLD$C_INK" "$1" "$RST"
  else
    printf '%s▐%s  %s%s%s\n' "$C_RED" "$RST" "$BOLD$C_INK" "$1" "$RST"
  fi
  printf '%s%s%s\n' "$C_VOID" "$(repeat_ch "$COLS" '─')" "$RST"
}

say()   { printf '   %s%s%s\n' "$C_GREY" "$*" "$RST"; }
ok()    { printf '   %s✓%s %s%s%s\n' "$C_RED_HOT" "$RST" "$C_INK" "$*" "$RST"; }
warn()  { printf '   %s!%s %s%s%s\n' "$C_WARN" "$RST" "$C_GREY" "$*" "$RST"; }
fail()  { printf '   %s✗%s %s%s%s\n' "$C_RED" "$RST" "$C_GREY" "$*" "$RST"; }
skip()  { printf '   %s·%s %s%s%s\n' "$C_DIM" "$RST" "$C_DIM" "$*" "$RST"; }
die()   { printf '\n %s%s ERROR %s%s %s\n\n' "$B_INK" "$F_BLACK$BOLD" "$RST" "$C_GREY" "$*" >&2; exit 1; }

kv() { # key/value row, dotted leader
  local k=$1 v=$2 w max
  v="${v//$HOME/\~}"
  max=$(( COLS - ${#k} - 10 ))
  (( ${#v} > max && max > 6 )) && v="…${v: -$(( max - 1 ))}"
  w=$(( COLS - ${#k} - ${#v} - 8 ))
  (( w < 1 )) && w=1
  printf '   %s%s%s %s%s%s %s%s%s\n' \
    "$C_GREY" "$k" "$RST" "$C_VOID" "$(repeat_ch "$w" '·')" "$RST" \
    "$C_INK" "$v" "$RST"
}

wrap_list() { # dim, indented, wrapped list of words
  local line="" w
  for w in "$@"; do
    if (( ${#line} + ${#w} + 1 > COLS - 8 )); then
      printf '     %s%s%s\n' "$C_DIM" "$line" "$RST"; line="$w"
    else
      line+="${line:+ }$w"
    fi
  done
  [[ -n "$line" ]] && printf '     %s%s%s\n' "$C_DIM" "$line" "$RST"
  return 0
}

bar() { # bar <done> <total> [width]
  local d=$1 t=$2 w=${3:-28} filled i out=""
  (( t == 0 )) && t=1
  filled=$(( d * w / t ))
  for (( i=0; i<w; i++ )); do
    if (( i < filled )); then out+="$C_RED_HOT━"; else out+="$C_VOID━"; fi
  done
  printf '%s%s  %s%d%%%s' "$out" "$RST" "$C_GREY" $(( d * 100 / t )) "$RST"
}

# spinner that tails the live log line of a background job
spin() { # spin <pid> <label> <logfile>
  local pid=$1 label=$2 logf=$3
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 f last width
  width=$(( COLS - ${#label} - 12 )); (( width < 10 )) && width=10
  hide_cursor
  while kill -0 "$pid" 2>/dev/null; do
    f="${frames:$(( i % 10 )):1}"
    last="$(tail -n1 "$logf" 2>/dev/null | tr -d '\r' | tr -cd '[:print:]')"
    printf '\r\033[2K   %s%s%s %s%s%s  %s%s%s' \
      "$C_RED_HOT" "$f" "$RST" "$C_INK" "$label" "$RST" \
      "$C_DIM" "${last:0:$width}" "$RST"
    sleep 0.08; ((i++))
  done
  printf '\r\033[2K'
  show_cursor
}

run_bg() { # run_bg <label> <cmd...>   -> streams to $LOG, spinner + tail
  local label=$1; shift
  if (( DRYRUN )); then skip "$label  (dry-run)"; return 0; fi
  local part; part="$(mktemp)"
  ( "$@" ) >"$part" 2>&1 &
  local pid=$!
  spin "$pid" "$label" "$part"
  wait "$pid"; local rc=$?
  cat "$part" >>"$LOG"; rm -f "$part"
  if (( rc == 0 )); then ok "$label"
  else fail "$label  (exit $rc — see $LOG)"; fi
  return $rc
}

run_fg() { # AUR tools may need to ask for sudo again after a long build.
  local label=$1 rc; shift
  if (( DRYRUN )); then skip "$label  (dry-run)"; return 0; fi
  "$@" 2>&1 | tee -a "$LOG"
  rc=${PIPESTATUS[0]}
  if (( rc == 0 )); then ok "$label"
  else fail "$label  (exit $rc — see $LOG)"; fi
  return "$rc"
}

# ══════════════════════════════════════════════════════════════════════
#  input widgets — pure bash, arrow keys, black-on-white selection
# ══════════════════════════════════════════════════════════════════════
# Arrow keys, as literals. These MUST go through quoted variables in `case`:
# an unquoted $'\e[A' pattern makes bash read "[A]" as a glob character class.
K_UP=$'\e[A';  K_DOWN=$'\e[B'
K_UP2=$'\eOA'; K_DOWN2=$'\eOB'   # application cursor mode

_readkey() {
  local k rest
  IFS= read -rsn1 k 2>/dev/null || return 1
  if [[ "$k" == $'\e' ]]; then
    read -rsn2 -t 0.05 rest 2>/dev/null
    k+="$rest"
  fi
  printf '%s' "$k"
}

_prompt_hint() {
  printf '   %s%s%s\n' "$C_VOID" "$1" "$RST"
}

# ui_select <prompt> <default-index> <label...>  -> echoes chosen index
ui_select() {
  local prompt=$1 cur=$2; shift 2
  local opts=("$@") i key n
  n=${#opts[@]}

  if [[ ! -t 0 ]]; then printf '%s' "$cur"; return 0; fi

  {
    printf '\n   %s%s%s\n' "$C_INK$BOLD" "$prompt" "$RST"
    _prompt_hint "↑/↓ move · enter select"
    hide_cursor
  } >&2

  local first=1
  while :; do
    {
      (( first )) || printf '\033[%dA' "$n"
      for (( i=0; i<n; i++ )); do
        printf '\033[2K'
        if (( i == cur )); then
          printf '   %s▎%s %-*s%s\n' \
            "$C_RED_HOT" "$B_INK$F_BLACK$BOLD" $(( COLS - 8 )) "${opts[i]}" "$RST"
        else
          printf '   %s│%s %s%-*s%s\n' \
            "$C_DIM" "$RST" "$C_GREY" $(( COLS - 8 )) "${opts[i]}" "$RST"
        fi
      done
    } >&2
    first=0
    key="$(_readkey)" || break
    case "$key" in
      "$K_UP"|"$K_UP2"|k)     if (( cur > 0 ));   then cur=$(( cur - 1 )); else cur=$(( n - 1 )); fi ;;
      "$K_DOWN"|"$K_DOWN2"|j) if (( cur < n-1 )); then cur=$(( cur + 1 )); else cur=0; fi ;;
      "")         break ;;
      q|$'\e')    { show_cursor; printf '\n'; } >&2; exit 130 ;;
    esac
  done
  { show_cursor; } >&2
  printf '%s' "$cur"
}

# ui_multi <prompt> <csv of preselected indices> <label...> -> echoes csv of indices
ui_multi() {
  local prompt=$1 pre=$2; shift 2
  local opts=("$@") i key cur=0 n
  n=${#opts[@]}
  local -a on
  for (( i=0; i<n; i++ )); do on[i]=0; done
  local x; IFS=',' read -ra x <<<"$pre"
  for i in ${x[@]+"${x[@]}"}; do [[ -n "$i" ]] && on[i]=1; done

  if [[ ! -t 0 ]]; then printf '%s' "$pre"; return 0; fi

  {
    printf '\n   %s%s%s\n' "$C_INK$BOLD" "$prompt" "$RST"
    _prompt_hint "↑/↓ move · space toggle · a all · enter confirm"
    hide_cursor
  } >&2

  local first=1 mark all
  while :; do
    {
      (( first )) || printf '\033[%dA' "$n"
      for (( i=0; i<n; i++ )); do
        printf '\033[2K'
        (( on[i] )) && mark="✓" || mark=" "
        if (( i == cur )); then
          printf '   %s▎%s %-*s%s\n' \
            "$C_RED_HOT" "$B_INK$F_BLACK$BOLD" $(( COLS - 8 )) "[$mark] ${opts[i]}" "$RST"
        else
          printf '   %s│%s %s[%s]%s %s%-*s%s\n' "$C_DIM" "$RST" \
            "$( (( on[i] )) && printf '%s' "$C_RED_HOT" || printf '%s' "$C_DIM" )" \
            "$mark" "$RST" "$C_GREY" $(( COLS - 12 )) "${opts[i]}" "$RST"
        fi
      done
    } >&2
    first=0
    key="$(_readkey)" || break
    case "$key" in
      "$K_UP"|"$K_UP2"|k)     if (( cur > 0 ));   then cur=$(( cur - 1 )); else cur=$(( n - 1 )); fi ;;
      "$K_DOWN"|"$K_DOWN2"|j) if (( cur < n-1 )); then cur=$(( cur + 1 )); else cur=0; fi ;;
      " ")        on[cur]=$(( 1 - on[cur] )) ;;
      a|A)        all=1; for (( i=0; i<n; i++ )); do (( on[i] )) || all=0; done
                  for (( i=0; i<n; i++ )); do on[i]=$(( 1 - all )); done ;;
      "")         break ;;
      q|$'\e')    { show_cursor; printf '\n'; } >&2; exit 130 ;;
    esac
  done
  { show_cursor; } >&2
  local out=""
  for (( i=0; i<n; i++ )); do (( on[i] )) && out+="${out:+,}$i"; done
  printf '%s' "$out"
}

# ui_yn <question> <default y|n>
ui_yn() {
  local q=$1 def=${2:-y} ans
  [[ ! -t 0 ]] && { [[ "$def" == y ]]; return $?; }
  local hint; [[ "$def" == y ]] && hint="Y/n" || hint="y/N"
  printf '   %s?%s %s%s%s %s[%s]%s ' "$C_RED_HOT" "$RST" "$C_INK" "$q" "$RST" "$C_DIM" "$hint" "$RST"
  read -r ans
  ans="${ans:-$def}"
  [[ "${ans,,}" == y* ]]
}

# ui_text <question> <default>
ui_text() {
  local q=$1 def=$2 ans
  [[ ! -t 0 ]] && { printf '%s' "$def"; return 0; }
  printf '   %s?%s %s%s%s %s[%s]%s ' "$C_RED_HOT" "$RST" "$C_INK" "$q" "$RST" "$C_DIM" "$def" "$RST" >&2
  read -r ans
  printf '%s' "${ans:-$def}"
}

pause_key() {
  [[ -t 0 ]] || return 0
  printf '\n   %spress any key to continue%s' "$C_VOID" "$RST"
  _readkey >/dev/null
  printf '\r\033[2K'
}

# ══════════════════════════════════════════════════════════════════════
#  package catalogue
# ══════════════════════════════════════════════════════════════════════
GROUP_KEYS=(audio shot net power theme fonts apps aur legacy)
GROUP_LABEL=(
  "Audio        pipewire · wireplumber · pamixer · playerctl"
  "Capture      grim · slurp · swappy · wl-clipboard"
  "Network      NetworkManager · bluez · blueman applets"
  "Power        brightnessctl · power-profiles-daemon · upower"
  "Theming      kvantum · qt6ct  (PureBlackGlass targets)"
  "Fonts        JetBrains Mono + Iosevka Nerd · Noto · emoji"
  "Desktop apps your terminal / browser / files / editor picks"
  "AUR extras   spotify · kora-icon-theme"
  "Legacy eww   old volume/power/calendar panels (rofi replaced these)"
)

pkgs_for() { # -> newline separated pacman packages
  case "$1" in
    core)  printf '%s\n' hyprland hyprpaper hypridle hyprlock hyprcursor \
             xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
             waybar rofi quickshell mako jq inotify-tools curl rsync git python lua socat \
             libnotify xdg-utils qt6-declarative qt6-svg qt6-wayland \
             qt6-multimedia qt6-multimedia-ffmpeg qt6-imageformats hyprpolkitagent \
             networkmanager bluez bluez-utils pipewire pipewire-pulse wireplumber upower brightnessctl ;;
    audio) printf '%s\n' pipewire pipewire-pulse pipewire-alsa wireplumber pamixer playerctl ;;
    shot)  printf '%s\n' grim slurp swappy wl-clipboard ;;
    net)   printf '%s\n' networkmanager network-manager-applet bluez bluez-utils blueman ;;
    power) printf '%s\n' brightnessctl power-profiles-daemon upower hyprsunset cpupower lm_sensors ;;
    theme) printf '%s\n' kvantum kvantum-qt5 qt5ct qt6ct ;;
    fonts) printf '%s\n' ttf-jetbrains-mono-nerd ttf-iosevka-nerd ttf-nerd-fonts-symbols \
             noto-fonts noto-fonts-emoji inter-font ;;
    apps)  : ;;   # filled from the user's picks
    aur)   : ;;   # AUR list, see aur_for
    legacy) : ;;
  esac
}

aur_for() {
  case "$1" in
    aur)    printf '%s\n' spotify kora-icon-theme ;;
    legacy) printf '%s\n' eww ;;
  esac
}

# choice -> package name  (aur:<name> marks an AUR package)
pkg_of_term()    { case "$1" in kitty) echo kitty;; alacritty) echo alacritty;; foot) echo foot;;
                                wezterm) echo wezterm;; ghostty) echo ghostty;; *) echo "";; esac; }
pkg_of_browser() { case "$1" in firefox) echo firefox;; chromium) echo chromium;;
                                brave) echo "aur:brave-bin";; zen-browser) echo "aur:zen-browser-bin";; *) echo "";; esac; }
pkg_of_files()   { case "$1" in nautilus) echo nautilus;; thunar) echo "thunar tumbler";;
                                dolphin) echo dolphin;; nemo) echo nemo;; *) echo "";; esac; }
pkg_of_editor()  { case "$1" in code) echo "aur:visual-studio-code-bin";; nvim) echo "neovim ripgrep fd";;
                                zed) echo zed;; *) echo "";; esac; }

has_group() { local g; for g in ${SEL_GROUPS[@]+"${SEL_GROUPS[@]}"}; do [[ "$g" == "$1" ]] && return 0; done; return 1; }

build_pkg_lists() { # fills PACMAN_LIST / AUR_LIST
  PACMAN_LIST=(); AUR_LIST=()
  local g p
  while read -r p; do [[ -n "$p" ]] && PACMAN_LIST+=("$p"); done < <(pkgs_for core)
  for g in ${SEL_GROUPS[@]+"${SEL_GROUPS[@]}"}; do
    while read -r p; do [[ -n "$p" ]] && PACMAN_LIST+=("$p"); done < <(pkgs_for "$g")
    while read -r p; do [[ -n "$p" ]] && AUR_LIST+=("$p"); done < <(aur_for "$g")
  done
  if has_group apps; then
    for p in "$(pkg_of_term "$PICK_TERM")" "$(pkg_of_browser "$PICK_BROWSER")" \
             "$(pkg_of_files "$PICK_FILES")" "$(pkg_of_editor "$PICK_EDITOR")"; do
      [[ -z "$p" ]] && continue
      if [[ "$p" == aur:* ]]; then AUR_LIST+=("${p#aur:}"); else
        local one; for one in $p; do PACMAN_LIST+=("$one"); done
      fi
    done
  fi
  (( DO_NVIM )) && PACMAN_LIST+=(neovim ripgrep fd unzip)
  local e; for e in ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}; do PACMAN_LIST+=("$e"); done
  if (( NO_AUR )); then
    AUR_LIST=()
    DO_AUR_HELPER=0
    [[ "$PICK_EDITOR" == code ]] && PICK_EDITOR=none
    if [[ "$PICK_BROWSER" == brave || "$PICK_BROWSER" == zen-browser ]]; then
      die "the selected browser requires AUR; choose Firefox/Chromium or omit --no-aur"
    fi
  fi
  # dedupe, keep order
  mapfile -t PACMAN_LIST < <(printf '%s\n' ${PACMAN_LIST[@]+"${PACMAN_LIST[@]}"} | awk 'NF && !seen[$0]++')
  mapfile -t AUR_LIST    < <(printf '%s\n' ${AUR_LIST[@]+"${AUR_LIST[@]}"}    | awk 'NF && !seen[$0]++')
}

# ══════════════════════════════════════════════════════════════════════
#  discovery
# ══════════════════════════════════════════════════════════════════════
# Update records are data, never sourced as shell code. Keep them outside the
# deployment so replacing ~/.config/hypr cannot erase the previous manifest.
INSTALL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/verumdot/install.json"
PREVIOUS_PACKAGES=(); PREVIOUS_SERVICES=()
RETIRED_PACKAGES=(); RETIRED_SERVICES=(); MANAGED_SERVICES=()
UPDATE_SETTINGS=''

load_update_state() {
  [[ -f "$INSTALL_STATE" ]] || { warn "No previous install record: establishing a baseline; no removal guesses."; return 0; }
  local records key value
  records=$(python3 - "$INSTALL_STATE" <<'PYLOAD'
import json, re, sys
try:
    data = json.load(open(sys.argv[1]))
    if data.get('version') != 1:
        raise ValueError('unsupported record version')
    profile = data['profile']
    if not isinstance(profile, dict):
        raise ValueError("invalid profile")
    for key, value in profile.items():
        if key in ('SEL_GROUPS', 'EXTRA_PKGS'):
            value = ' '.join(value)
        if not isinstance(value, str) or '\n' in value or '\t' in value:
            raise ValueError('invalid profile value')
        print(key + '\t' + value)
    for field, key in [('packages', 'package'), ('services', 'service')]:
        for value in data[field]:
            pattern = r'(?:user|system):[a-zA-Z0-9@._+-]+' if field == 'services' else r'[a-zA-Z0-9@._+-]+'
            if not isinstance(value, str) or not re.fullmatch(pattern, value) or value.startswith('-'):
                raise ValueError('invalid manifest entry')
            print(key + '\t' + value)
except (OSError, ValueError, KeyError, TypeError) as exc:
    sys.exit('Invalid VerumDot install record: ' + str(exc))
PYLOAD
  ) || die "cannot read $INSTALL_STATE; restore its backup before updating"
  PREVIOUS_PACKAGES=(); PREVIOUS_SERVICES=()
  while IFS=$'\t' read -r key value; do
    case "$key" in
      SEL_GROUPS) read -ra SEL_GROUPS <<<"$value" ;;
      EXTRA_PKGS) read -ra EXTRA_PKGS <<<"$value" ;;
      PICK_TERM|PICK_BROWSER|PICK_FILES|PICK_EDITOR|PICK_MONITOR|PICK_SCALE|WALLPAPER_DIR)
        printf -v "$key" '%s' "$value" ;;
      DO_LID|DO_THEME|DO_SERVICES|DO_NVIM|NO_AUR)
        [[ "$value" == 0 || "$value" == 1 ]] || die "invalid $key in install record"
        printf -v "$key" '%s' "$value" ;;
      package) PREVIOUS_PACKAGES+=("$value") ;;
      service) PREVIOUS_SERVICES+=("$value") ;;
    esac
  done <<<"$records"
}

# Read common app choices from the existing flat settings table, so older
# installations and hand-edited bindings do not pull in default desktop apps.
adopt_update_settings() {
  local key value choices
  choices=$(printf '%s\n' "$UPDATE_SETTINGS" | python3 -c '
import ast, re, shlex, sys
settings = {}
for line in sys.stdin:
    match = re.match(r"\s*([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.*),\s*(?:--.*)?$", line)
    if match:
        try:
            value = ast.literal_eval(match[2])
        except (ValueError, SyntaxError):
            continue
        if isinstance(value, str) and not any(c in value for c in "\n\t\0"):
            settings[match[1]] = value
allowed = dict(terminal="kitty alacritty foot wezterm ghostty", browser="firefox chromium brave zen-browser", files="nautilus thunar dolphin nemo", editor="code nvim zed")
for setting, picks in allowed.items():
    if setting not in settings:
        continue
    try:
        words = shlex.split(settings[setting])
    except ValueError:
        continue
    command = words[0].rsplit("/", 1)[-1] if words else "none"
    if setting == "editor":
        if "nvim" in words:
            command = "nvim"
        elif command == "zeditor":
            command = "zed"
    if command not in picks.split():
        command = "none"
    print("PICK_" + dict(terminal="TERM", browser="BROWSER", files="FILES", editor="EDITOR")[setting] + "\t" + command)
for setting, key in [("monitor_output", "PICK_MONITOR"), ("monitor_scale", "PICK_SCALE"), ("wallpaper_dir", "WALLPAPER_DIR")]:
    if setting in settings:
        print(key + "\t" + settings[setting])
') || die "cannot read existing machine settings"
  while IFS=$'\t' read -r key value; do
    case "$key" in PICK_TERM|PICK_BROWSER|PICK_FILES|PICK_EDITOR|PICK_MONITOR|PICK_SCALE|WALLPAPER_DIR)
      printf -v "$key" '%s' "$value" ;;
    esac
  done <<<"$choices"
}

prepare_update() {
  (( FACT_EXISTING )) || die "no existing rice at $TARGET; choose Full install first"
  (( FACT_INPLACE )) && die "update from the separate source checkout or install.sh, not the deployed configuration"
  load_update_state
  [[ -f "$TARGET/config/settings.lua" ]] && UPDATE_SETTINGS=$(cat "$TARGET/config/settings.lua")
  [[ -n "$UPDATE_SETTINGS" ]] && adopt_update_settings
  DO_PACKAGES=1; DO_CONFIG=1
  say "Update: back up configs, preserve machine settings, install missing dependencies."
  say "Retired packages and services require a separate yes; Enter keeps them."
}

services_for() {
  printf '%s\n' user:pipewire user:pipewire-pulse user:wireplumber
  has_group power && printf '%s\n' system:power-profiles-daemon
  if has_group net; then printf '%s\n' system:NetworkManager system:bluetooth; fi
  return 0
}

plan_retirements() {
  local item
  RETIRED_PACKAGES=(); RETIRED_SERVICES=()
  for item in "${PREVIOUS_PACKAGES[@]}"; do
    if ! printf '%s\n' "${PACMAN_LIST[@]}" "${AUR_LIST[@]}" | grep -Fx -- "$item" >/dev/null; then
      pacman -Qq "$item" >/dev/null 2>&1 && RETIRED_PACKAGES+=("$item")
    fi
  done
  mapfile -t MANAGED_SERVICES < <(services_for)
  for item in "${PREVIOUS_SERVICES[@]}"; do
    if ! printf '%s\n' "${MANAGED_SERVICES[@]}" | grep -Fx -- "$item" >/dev/null; then
      RETIRED_SERVICES+=("$item")
    fi
  done
  if (( ${#RETIRED_PACKAGES[@]} )); then
    say "Previously required packages no longer selected (optional removal):"
    wrap_list "${RETIRED_PACKAGES[@]}"
  fi
  if (( ${#RETIRED_SERVICES[@]} )); then
    say "Previously configured services no longer selected (optional disable):"
    wrap_list "${RETIRED_SERVICES[@]}"
  fi
}

cleanup_retired_services() {
  [[ "$MODE" == update ]] || return 0
  local item scope unit kept=()
  for item in "${RETIRED_SERVICES[@]}"; do
    if (( DO_SERVICES )) && ui_yn "Disable retired service $item?" n; then
      scope=${item%%:*}; unit=${item#*:}
      if [[ "$scope" == user ]]; then
        systemctl --user disable --now "$unit" >>"$LOG" 2>&1 || { warn "Could not disable $item; keeping it in the record."; kept+=("$item"); }
      else
        sudo systemctl disable --now "$unit" >>"$LOG" 2>&1 || { warn "Could not disable $item; keeping it in the record."; kept+=("$item"); }
      fi
    else kept+=("$item"); fi
  done
  RETIRED_SERVICES=("${kept[@]}")
}

cleanup_retired_packages() {
  [[ "$MODE" == update ]] || return 0
  local item kept=()
  for item in "${RETIRED_PACKAGES[@]}"; do
    pacman -Qq "$item" >/dev/null 2>&1 || continue
    if ui_yn "Remove previously required package $item?" n; then
      # Pacman checks reverse dependencies and asks for confirmation itself.
      # Never recursively remove dependencies or force removal.
      run_fg "remove $item" sudo pacman -R -- "$item" || { warn "Could not remove $item; keeping it in the record."; kept+=("$item"); }
    else kept+=("$item"); fi
  done
  RETIRED_PACKAGES=("${kept[@]}")
}

cleanup_retired() {
  cleanup_retired_services
  cleanup_retired_packages
}

save_install_state() {
  local key
  mkdir -p "$(dirname "$INSTALL_STATE")" || die "cannot create installer state directory"
  # Named, whitelisted values only; no eval/source on either side.
  for key in PICK_TERM PICK_BROWSER PICK_FILES PICK_EDITOR PICK_MONITOR PICK_SCALE WALLPAPER_DIR DO_LID DO_THEME DO_SERVICES DO_NVIM NO_AUR; do
    export "VD_SAVE_$key=${!key}"
  done
  export VD_SAVE_SEL_GROUPS="${SEL_GROUPS[*]}" VD_SAVE_EXTRA_PKGS="${EXTRA_PKGS[*]}"
  printf '%s\n' "${PACMAN_LIST[@]}" "${AUR_LIST[@]}" "${RETIRED_PACKAGES[@]}" \
    >"${INSTALL_STATE}.packages.$$" || die "cannot stage package record"
  printf '%s\n' "${MANAGED_SERVICES[@]}" "${RETIRED_SERVICES[@]}" \
    >"${INSTALL_STATE}.services.$$" || die "cannot stage service record"
  python3 - "$INSTALL_STATE" "$$" <<'PYSAVE'
import json, os, sys
from pathlib import Path
path, pid = sys.argv[1:]
profile = {k.removeprefix('VD_SAVE_'): v for k, v in os.environ.items() if k.startswith('VD_SAVE_')}
for key in ('SEL_GROUPS', 'EXTRA_PKGS'):
    profile[key] = profile[key].split()
def entries(kind):
    return list(dict.fromkeys(filter(None, Path(f'{path}.{kind}.{pid}').read_text().splitlines())))
data = dict(version=1, profile=profile, packages=entries('packages'), services=entries('services'))
tmp = Path(f'{path}.tmp.{pid}')
tmp.write_text(json.dumps(data, indent=2) + '\n')
os.chmod(tmp, 0o600)
if Path(path).exists():
    Path(path + '.bak').write_bytes(Path(path).read_bytes())
    os.chmod(path + '.bak', 0o600)
os.replace(tmp, path)
for kind in ('packages', 'services'):
    Path(f'{path}.{kind}.{pid}').unlink()
PYSAVE
  [[ $? == 0 ]] || die "cannot save installer state"
  ok "saved update record: $INSTALL_STATE"
}

restore_update_settings() {
  [[ -n "$UPDATE_SETTINGS" ]] || return 0
  # settings.lua is a flat table with one assignment per line. Copy existing
  # assignments into matching new defaults, keeping newly introduced keys.
  printf '%s\n' "$UPDATE_SETTINGS" | python3 -c '
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
pattern = re.compile(r"^(\s*)([A-Za-z_][A-Za-z_0-9]*)\s*=.*?,\s*(?:--.*)?$")
old = {}
for line in sys.stdin.read().splitlines():
    match = pattern.match(line)
    if match:
        old[match[2]] = line
new = path.read_text().splitlines(keepends=True)
path.write_text("".join(old[m[2]] + "\n" if (m := pattern.match(line.rstrip("\n"))) and m[2] in old else line for line in new))
' "$TARGET/config/settings.lua" || die "cannot restore per-machine settings"
  ok "preserved per-machine settings; new settings retain their defaults"
}

detect_monitors() { # unique, connected output names — one per line
  {
    if command -v hyprctl >/dev/null 2>&1 && hyprctl monitors >/dev/null 2>&1; then
      # "Monitor eDP-1 (ID 0):" — plain output, no jq needed, no workspace names
      hyprctl monitors 2>/dev/null | awk '/^Monitor /{print $2}'
    fi
    local s n
    for s in /sys/class/drm/card*-*/status; do
      [[ -r "$s" ]] || continue
      [[ "$(cat "$s" 2>/dev/null)" == "connected" ]] || continue
      n="${s%/status}"; n="${n##*/}"
      printf '%s\n' "${n#card*-}"
    done
  } | awk 'NF && !seen[$0]++'
}

preflight() {
  headline "Preflight  ·  reading this machine"

  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    FACT_DISTRO="$( . /etc/os-release && printf '%s' "${PRETTY_NAME:-${ID:-unknown}}" )"
  fi
  command -v pacman >/dev/null 2>&1 && FACT_PACMAN=1
  local h; for h in yay paru; do command -v "$h" >/dev/null 2>&1 && { FACT_AUR="$h"; break; }; done

  if lsmod 2>/dev/null | grep -q '^nvidia'; then FACT_GPU="NVIDIA"
  elif [[ -d /sys/module/amdgpu ]]; then FACT_GPU="AMD"
  elif [[ -d /sys/module/i915 || -d /sys/module/xe ]]; then FACT_GPU="Intel"
  fi
  compgen -G "/sys/class/power_supply/BAT*" >/dev/null && FACT_LAPTOP=1

  if (( DRYRUN || ! DO_PACKAGES )); then
    FACT_NET=1  # no network is needed for a plan or config deployment
  elif command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 5 -o /dev/null https://archlinux.org && FACT_NET=1
  elif ping -c1 -W2 archlinux.org >/dev/null 2>&1; then FACT_NET=1
  fi

  [[ -e "$TARGET" || -L "$TARGET" ]] && FACT_EXISTING=1
  [[ "$RICE_SRC" -ef "$TARGET" ]] && FACT_INPLACE=1
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && FACT_HYPR_RUNNING=1

  kv "distribution"  "$FACT_DISTRO"
  kv "pacman"        "$( (( FACT_PACMAN )) && echo present || echo "MISSING" )"
  kv "AUR helper"    "${FACT_AUR:-none — can bootstrap yay}"
  kv "graphics"      "$FACT_GPU"
  kv "chassis"       "$( (( FACT_LAPTOP )) && echo "laptop (battery found)" || echo desktop )"
  kv "network"       "$( (( FACT_NET )) && echo reachable || echo "unverified" )"
  kv "outputs"       "$(detect_monitors | paste -sd' ' - | sed 's/^$/none detected/')"
  kv "existing rice" "$( (( FACT_INPLACE )) && echo "in place — update" \
                        || { (( FACT_EXISTING )) && echo "$TARGET (will back up)" || echo "none"; } )"

  (( FACT_PACMAN )) || {
    printf '\n'
    warn "No pacman. VerumDot targets Arch and derivatives."
    (( DO_PACKAGES )) && die "pacman is required for package installation; use --config for config only"
  }
  (( FACT_NET )) || warn "Could not reach archlinux.org — package install may fail."
}

# ══════════════════════════════════════════════════════════════════════
#  wizard
# ══════════════════════════════════════════════════════════════════════
wizard() {
  headline "Setup  ·  every question already has a sane default"

  local i
  i="$(ui_select "What should this run do?" 0 \
      "Full install      packages + config + theme   (fresh machine)" \
      "Config only       deploy rice, skip packages" \
      "Packages only     install dependencies, leave config alone" \
      "Update existing rice  refresh config + missing dependencies" )"
  case "$i" in
    0) DO_PACKAGES=1; DO_CONFIG=1 ;;
    1) DO_PACKAGES=0; DO_CONFIG=1 ;;
    2) DO_PACKAGES=1; DO_CONFIG=0 ;;
    3) MODE=update; prepare_update; return 0 ;;
  esac
  (( FACT_PACMAN )) || DO_PACKAGES=0

  if (( DO_PACKAGES )); then
    local pre="" k idx=0
    for k in "${GROUP_KEYS[@]}"; do
      [[ "$k" == legacy ]] || pre+="${pre:+,}$idx"
      ((idx++))
    done
    local chosen; chosen="$(ui_multi "Which package groups? (core is always installed)" "$pre" "${GROUP_LABEL[@]}")"
    SEL_GROUPS=()
    local n; IFS=',' read -ra n <<<"$chosen"
    for k in ${n[@]+"${n[@]}"}; do [[ -n "$k" ]] && SEL_GROUPS+=("${GROUP_KEYS[k]}"); done

    if has_group apps; then
      i="$(ui_select "Terminal — bound to SUPER+Return and SUPER+T" 0 \
          "kitty        (default, config ships with the rice)" \
          "alacritty" "foot" "wezterm" "ghostty")"
      local _t=(kitty alacritty foot wezterm ghostty); PICK_TERM="${_t[i]}"

      i="$(ui_select "Browser — bound to SUPER+W" 0 "firefox" "chromium" "brave  (AUR)" "zen-browser  (AUR)")"
      local _b=(firefox chromium brave zen-browser); PICK_BROWSER="${_b[i]}"

      i="$(ui_select "File manager — bound to SUPER+E" 0 "nautilus" "thunar" "dolphin" "nemo")"
      local _f=(nautilus thunar dolphin nemo); PICK_FILES="${_f[i]}"

      i="$(ui_select "Editor — bound to SUPER+C" 0 "VS Code  (AUR)" "neovim" "zed" "none — leave the bind alone")"
      local _e=(code nvim zed none); PICK_EDITOR="${_e[i]}"
    fi

    if [[ -z "$FACT_AUR" ]] && { has_group aur || has_group legacy || [[ "$PICK_EDITOR" == code ]] || [[ "$PICK_BROWSER" == brave || "$PICK_BROWSER" == zen-browser ]]; }; then
      ui_yn "No AUR helper found. Bootstrap yay from source?" y && DO_AUR_HELPER=1 || DO_AUR_HELPER=0
    else
      DO_AUR_HELPER=0
    fi
  else
    DO_AUR_HELPER=0
  fi

  if (( DO_CONFIG )); then
    local mons=() m
    while read -r m; do [[ -n "$m" ]] && mons+=("$m"); done < <(detect_monitors)
    if (( ${#mons[@]} > 0 )); then
      mons+=("automatic output — use any connected display")
      i="$(ui_select "Primary output — written into config/settings.lua" 0 "${mons[@]}")"
      (( i < ${#mons[@]} - 1 )) && PICK_MONITOR="${mons[i]}"
    else
      PICK_MONITOR="$(ui_text "Primary output name (blank = automatic)" "")"
    fi
    if [[ -n "$PICK_MONITOR" ]]; then
      i="$(ui_select "Scale for $PICK_MONITOR" 0 "1.0   native" "1.25" "1.5   HiDPI" "auto")"
      local _s=(1.0 1.25 1.5 auto); PICK_SCALE="${_s[i]}"
    fi

    WALLPAPER_DIR="$(ui_text "Wallpaper folder" "$WALLPAPER_DIR")"
    ui_yn "Install the PureBlackGlass GTK / Qt / portal theme?" y && DO_THEME=1 || DO_THEME=0
    ui_yn "Enable pipewire user services now?" y && DO_SERVICES=1 || DO_SERVICES=0
    if (( FACT_LAPTOP )); then
      ui_yn "Lid close = lock + blank screen, never suspend? (needs sudo once)" y && DO_LID=1 || DO_LID=0
    else
      DO_LID=0
    fi
  fi
}

# ══════════════════════════════════════════════════════════════════════
#  plan
# ══════════════════════════════════════════════════════════════════════
show_plan() {
  build_pkg_lists
  [[ "$MODE" == update ]] && plan_retirements
  headline "Plan  ·  nothing has been touched yet"

  if (( DO_PACKAGES )); then
    kv "pacman packages" "${#PACMAN_LIST[@]}"
    if [[ "$MODE" == update ]]; then
      say "checks installed packages; adds missing ones only (full Arch upgrade when needed)"
    else say "includes a full system upgrade (pacman -Syu) before AUR builds"; fi
    wrap_list ${PACMAN_LIST[@]+"${PACMAN_LIST[@]}"}
    if (( ${#AUR_LIST[@]} )); then
      kv "AUR packages" "${#AUR_LIST[@]}"
      wrap_list "${AUR_LIST[@]}"
    fi
    [[ -n "$FACT_AUR" ]] && kv "AUR helper" "$FACT_AUR" \
      || { (( DO_AUR_HELPER )) && kv "AUR helper" "bootstrap yay-bin"; }
  else
    kv "packages" "skipped"
  fi

  if (( DO_CONFIG )); then
    kv "deploy to" "$TARGET"
    (( FACT_EXISTING && ! FACT_INPLACE )) && kv "backup" "$TARGET.bak.$STAMP"
    kv "waybar links" "$WAYBAR_CFG/{config,style.css,scripts}"
    kv "shell configs" "$XDG_CFG/{hypridle,hyprlock,quickshell}"
    kv "kitty link" "$XDG_CFG/kitty/kitty.conf"
    kv "wallpapers" "$WALLPAPER_DIR"
    [[ -n "$PICK_MONITOR" ]] && kv "monitor line" "$PICK_MONITOR,preferred,auto,$PICK_SCALE"
    has_group apps && kv "binds" "term=$PICK_TERM  web=$PICK_BROWSER  files=$PICK_FILES  edit=$PICK_EDITOR"
    (( DO_NVIM ))     && kv "nvim overlay" "$NVIM_CFG/lua/{verum,plugins/verum.lua}"
    (( DO_THEME ))    && kv "theme" "PureBlackGlass → GTK / Qt / Kvantum / portal"
    (( DO_SERVICES )) && kv "services" "pipewire · pipewire-pulse · wireplumber"
    (( DO_LID ))      && kv "logind" "HandleLidSwitch=ignore (lock, no suspend)"
  else
    kv "config" "skipped"
  fi
  kv "log" "$LOG"

  printf '\n'
  if (( DRYRUN )); then
    rule '─'
    printf '   %sdry run — stopping here.%s\n\n' "$C_RED_HOT" "$RST"
    exit 0
  fi
  if [[ "$MODE" == "wizard" || "$MODE" == update ]]; then
    ui_yn "Execute this plan?" y || { printf '\n   %snothing done.%s\n\n' "$C_GREY" "$RST"; exit 0; }
  fi
}

# ══════════════════════════════════════════════════════════════════════
#  execution
# ══════════════════════════════════════════════════════════════════════
SUDO_KEEPALIVE_PID=""
SUDO_OK=0
sudo_begin() {
  (( DRYRUN )) && return 0
  if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required for the selected package/service/lid actions"
  elif sudo -n true 2>/dev/null; then
    SUDO_OK=1
  else
    printf '   %sroot is needed for pacman, logind and system services:%s\n' "$C_GREY" "$RST"
    sudo -v && SUDO_OK=1
  fi
  if (( SUDO_OK )); then
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 45; done ) >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
  else
    die "sudo authentication failed; no installation was performed"
  fi
}
sudo_end() { [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; SUDO_KEEPALIVE_PID=""; }

backup_path() {
  local p=$1 backup="${1}.bak.${STAMP}" n=0
  if [[ -e "$p" || -L "$p" ]]; then
    while [[ -e "$backup" || -L "$backup" ]]; do
      n=$((n + 1)); backup="${p}.bak.${STAMP}.${n}"
    done
    mv -- "$p" "$backup" || die "cannot back up $p"
    ok "backed up $p → $backup"
  fi
}

link_force() {
  local src=$1 dst=$2
  [[ -e "$src" ]] || die "missing config source: $src"
  mkdir -p -- "$(dirname -- "$dst")" || die "cannot create parent of $dst"
  [[ -L "$dst" && "$(readlink -- "$dst")" == "$src" ]] && return 0
  backup_path "$dst"
  ln -s -- "$src" "$dst" || die "cannot link $dst"
  ok "linked ${dst/#$HOME/\~}"
}

bootstrap_aur_helper() {
  [[ -n "$FACT_AUR" ]] && return 0
  (( DO_AUR_HELPER )) || die "AUR packages selected but no helper is available; install yay/paru or use --no-aur"
  run_bg "build tools (base-devel, git)" sudo pacman -S --needed --noconfirm base-devel git || die "build tools failed"
  local tmp; tmp="$(mktemp -d)" || die "cannot create AUR build directory"
  if run_fg "bootstrapping yay-bin" bash -c '
      git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$1/yay-bin" &&
      cd "$1/yay-bin" && makepkg -si --noconfirm' bash "$tmp"; then
    FACT_AUR="yay"
  else
    rm -rf -- "$tmp"
    die "yay bootstrap failed; see $LOG"
  fi
  rm -rf -- "$tmp"
}

install_packages() {
  headline "Packages  ·  ${#PACMAN_LIST[@]} from the repos, ${#AUR_LIST[@]} from the AUR"
  local repo=("${PACMAN_LIST[@]}") aur=("${AUR_LIST[@]}") p
  if [[ "$MODE" == update ]]; then
    repo=(); aur=()
    for p in "${PACMAN_LIST[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || repo+=("$p"); done
    for p in "${AUR_LIST[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || aur+=("$p"); done
    ok "dependency check: ${#repo[@]} missing repo packages, ${#aur[@]} missing AUR packages"
    # Resolve repo dependencies of new AUR packages against an upgraded system.
    if (( ${#repo[@]} == 0 && ${#aur[@]} == 0 )); then return 0; fi
  fi
  # Arch requires a full upgrade when adding packages, keeping Qt's ABI in sync.
  if [[ "$MODE" == update ]]; then
    # Show pacman's questions, including any package replacements/conflicts.
    run_fg "upgrading system and installing missing repo dependencies" \
      sudo pacman -Syu --needed "${repo[@]}" \
      || die "repo package transaction failed; fix the error in $LOG and rerun setup"
  else
    run_bg "upgrading system and installing repo dependencies" \
      sudo pacman -Syu --needed --noconfirm "${repo[@]}" \
      || die "repo package transaction failed; fix the error in $LOG and rerun setup"
  fi
  if (( ${#aur[@]} )); then
    bootstrap_aur_helper
    for p in "${aur[@]}"; do
      local aur_flags=(--needed --noconfirm)
      [[ "$MODE" == update ]] && aur_flags=(--needed)
      run_fg "aur/$p" "$FACT_AUR" -S "${aur_flags[@]}" "$p" \
        || die "AUR package $p failed; see $LOG (or rerun with --no-aur)"
    done
  fi
}

verify_quickshell() {
  headline "Quickshell  ·  checking the runtime"
  local cmd tmp
  for cmd in qs python3; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd is missing; run setup.sh --packages first"
  done
  qs --version >>"$LOG" 2>&1 || die "Quickshell cannot start; fully upgrade Qt and Quickshell together"
  # Import the actual modules used by the panels without connecting to the
  # compositor or starting any desktop services. This also detects older
  # Quickshell builds without Networking/Bluetooth support.
  tmp="$(mktemp -d)" || die "cannot create runtime check directory"
  cat >"$tmp/shell.qml" <<'QML'
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
Timer { interval: 1; running: true; onTriggered: Qt.exit(0) }
QML
  if ! env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
      timeout 15s qs -p "$tmp" --no-color >>"$LOG" 2>&1; then
    rm -rf -- "$tmp"
    die "Quickshell module check failed; use a current Arch Quickshell (0.3.2+) with matching Qt packages; see $LOG"
  fi
  rm -rf -- "$tmp"
  ok "Quickshell modules and Python are available"
}

# ── config deploy ──────────────────────────────────────────────────────
deploy_files() {
  headline "Deploy  ·  $TARGET"

  if (( FACT_INPLACE )); then
    ok "running from $TARGET — updating in place"
  else
    case "$RICE_SRC/" in "$TARGET/"*) die "source is inside the deployment target; move the clone outside $TARGET first" ;; esac
    (( FACT_EXISTING )) && backup_path "$TARGET"
    mkdir -p "$(dirname "$TARGET")" || die "cannot create deployment directory"
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --exclude '.git' --exclude 'current-wallpaper' --exclude 'lock-wallpaper' --exclude '*.bak.*' \
        "$RICE_SRC/" "$TARGET/" >>"$LOG" 2>&1 || die "config copy failed; see $LOG"
    else
      mkdir -p "$TARGET" || die "cannot create deployment target"
      (cd "$RICE_SRC" && tar --exclude=.git --exclude=current-wallpaper --exclude=lock-wallpaper \
        --exclude='*.bak.*' -cf - .) | tar -xf - -C "$TARGET" >>"$LOG" 2>&1 \
        || die "config copy failed; see $LOG"
    fi
    ok "copied the rice to $TARGET"
  fi

  find "$TARGET/scripts" "$TARGET/apps/waybar/scripts" -type f \
    \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + || die "cannot set script permissions"
  chmod +x "$TARGET/setup.sh" || die "cannot make setup executable"
  ok "scripts made executable"

  link_force "$TARGET/apps/waybar/config.jsonc" "$WAYBAR_CFG/config"
  link_force "$TARGET/apps/waybar/config.jsonc" "$WAYBAR_CFG/config.jsonc"
  link_force "$TARGET/apps/waybar/style.css" "$WAYBAR_CFG/style.css"
  link_force "$TARGET/apps/waybar/scripts" "$WAYBAR_CFG/scripts"
  local app
  for app in hypridle hyprlock; do
    link_force "$TARGET/apps/$app/$app.conf" "$XDG_CFG/$app/$app.conf"
  done
  link_force "$TARGET/apps/mako/config" "$XDG_CFG/mako/config"
  link_force "$TARGET/apps/rofi/config.rasi" "$XDG_CFG/rofi/config.rasi"
  local surface
  for surface in launcher controlcenter spotify keybinds; do
    # Repair archives/checkouts which lost the relative directory symlinks.
    if [[ ! "$TARGET/apps/quickshell/$surface/shared" -ef "$TARGET/apps/quickshell/shared" ]]; then
      backup_path "$TARGET/apps/quickshell/$surface/shared"
      ln -s ../shared "$TARGET/apps/quickshell/$surface/shared" || die "cannot link shared QML"
    fi
    [[ -f "$TARGET/apps/quickshell/$surface/shared/Theme.qml" ]] || die "shared QML is missing"
    link_force "$TARGET/apps/quickshell/$surface" "$XDG_CFG/quickshell/$surface"
  done

  # kitty.conf carries the transparent_background_colors that turn the Neovim
  # panes into glass — without this link a fresh machine renders them as opaque
  # rectangles sitting on the wallpaper.
  if [[ "$PICK_TERM" == "kitty" ]] || command -v kitty >/dev/null 2>&1; then
    link_force "$TARGET/apps/kitty/kitty.conf" "$XDG_CFG/kitty/kitty.conf"
  fi

  mkdir -p "$WALLPAPER_DIR" "$TARGET/assets" || die "cannot create wallpaper directory"
  local first
  first="$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print -quit)"
  if [[ -z "$first" ]]; then
    # A 64x64 near-black placeholder, stored as base64 rather than generated
    # by an image editor, so no extra wallpaper-generation tool is needed.
    printf '%s' "\
iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAIGNIUk0AAHomAACAhAAA+gAAAIDo\
AAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAldEVYdGRhdGU6Y3JlYXRl\
ADIwMjYtMDktMzBUMDU6MTE6NDErMDA6MDDi6viIAAAAJXRFWHRkYXRlOm1vZGlmeQAyMDI2LTA5\
LTMwVDA1OjExOjQxKzAwOjAwk7dANAAAACh0RVh0ZGF0ZTp0aW1lc3RhbXAAMjAyNi0wOS0zMFQw\
NToxMTo0MSswMDowMMSiYesAAAB4SURBVGje7c9BDQAgEMAw4Hn+BSOCR0OyKej2zKyfOxrQgAY0\
oAENaEADGtCABjSgAQ1oQAMa0IAGNKABDWhAAxrQgAY0oAENaEADGtCABjSgAQ1oQAMa0IAGNKAB\
DWhAAxrQgAY0oAENaEADGtCABjSgAQ1owGsX6IMAnuKgjwgAAAAASUVORK5CYII=" \
      | base64 -d > "$WALLPAPER_DIR/suf.png" 2>/dev/null \
      || die "cannot seed wallpaper"
    first="$WALLPAPER_DIR/suf.png"
    ok "placeholder wallpaper written (drop your own into $WALLPAPER_DIR)"
  fi
  if [[ -n "$first" ]]; then
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
    mkdir -p "$state_dir" || die "cannot create wallpaper state directory"
    local key image
    for key in wallpaper wallpaper-lock; do
      image="$(cat "$state_dir/$key" 2>/dev/null || true)"
      [[ -f "$image" ]] || image="$first"
      if [[ "$key" == wallpaper || -f "$state_dir/$key" ]]; then
        printf '%s\n' "$image" >"$state_dir/$key" || die "cannot save wallpaper state"
      fi
      if [[ "$key" == wallpaper ]]; then
        ln -sfn "$image" "$TARGET/assets/current-wallpaper" || die "cannot link wallpaper"
      else
        ln -sfn "$image" "$TARGET/assets/lock-wallpaper" || die "cannot link lock wallpaper"
      fi
    done
    ok "desktop and lock wallpaper links are ready"

  fi

  if [[ -f "$TARGET/apps/gtk/gtk-3.0/bookmarks.template" ]]; then
    mkdir -p "$XDG_CFG/gtk-3.0"
    backup_path "$XDG_CFG/gtk-3.0/bookmarks"
    python3 - "$TARGET/apps/gtk/gtk-3.0/bookmarks.template" "$XDG_CFG/gtk-3.0/bookmarks" "$HOME" <<'PYBOOK'
from pathlib import Path
import sys
Path(sys.argv[2]).write_text(Path(sys.argv[1]).read_text().replace('/home/USER', sys.argv[3]))
PYBOOK
    [[ $? == 0 ]] || die "cannot write GTK bookmarks"
    ok "gtk bookmarks written for ${USER:-$(id -un)}"
  fi
}

personalise() {
  # Every per-machine choice lives in config/settings.lua, one `key = value`
  # per line, so each pick is a single anchored sed on its own line.
  local f="$TARGET/config/settings.lua"
  [[ -f "$f" ]] || die "config/settings.lua is missing"
  headline "Personalise  ·  config/settings.lua"

  # set_setting <key> <lua-literal> — replace one `key = value,` line.
  set_setting() {
    local value=${2//\\/\\\\}; value=${value//|/\\|}; value=${value//&/\\&}
    sed -i -E "s|^([[:space:]]*$1[[:space:]]*=[[:space:]]*).*,|\1$value,|" "$f" || die "cannot personalise $f"
  }
  # lua_q <text> — <text> as a Lua string literal.
  lua_q() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }

  if [[ -n "$PICK_MONITOR" ]]; then
    set_setting monitor_output "$(lua_q "$PICK_MONITOR")"
    set_setting monitor_scale  "$(lua_q "$PICK_SCALE")"
    ok "monitor = $PICK_MONITOR, preferred, auto, $PICK_SCALE"
  else
    set_setting monitor_output '""'
    set_setting monitor_scale  '"1"'
    ok "monitor = any output, preferred, auto, 1 (automatic output)"
  fi

  if has_group apps; then
    set_setting terminal "$(lua_q "$PICK_TERM")"
    set_setting browser  "$(lua_q "$PICK_BROWSER")"
    set_setting files    "$(lua_q "$PICK_FILES")"
    ok "SUPER+Return / T → $PICK_TERM"
    ok "SUPER+W → $PICK_BROWSER    SUPER+E → $PICK_FILES"
    case "$PICK_EDITOR" in
      code) set_setting editor '"code"'; ok "SUPER+C → VS Code" ;;
      nvim) set_setting editor "$(lua_q "$PICK_TERM -e nvim")"; ok "SUPER+C → $PICK_TERM -e nvim" ;;
      zed)  set_setting editor '"zeditor"'; ok "SUPER+C → zed" ;;
      *)    skip "SUPER+C left as is" ;;
    esac
  fi

  # The eww daemon autostart checks for eww itself (config/autostart.lua),
  # so a machine without eww needs no edit here.
  # Do not force NVIDIA GLX on Intel/AMD laptops.
  if [[ "$FACT_GPU" != NVIDIA ]]; then
    set_setting nvidia false
  fi
  # Push the session environment into systemd and start the polkit agent.
  set_setting session_env true
  # Persist a custom wallpaper directory for scripts launched by Hyprland.
  set_setting wallpaper_dir "$(lua_q "$WALLPAPER_DIR")"

  # Catch a bad edit now rather than at the next login.
  if command -v Hyprland >/dev/null 2>&1; then
    local verdict
    verdict=$(Hyprland --verify-config -c "$TARGET/hyprland.lua" 2>&1 | sed -n '/Config parsing result/,$p' | tail -n +2)
    if grep -qx 'config ok' <<<"$verdict"; then
      ok "hyprland.lua verified"
    else
      warn "hyprland.lua did not verify:"; printf '%s\n' "$verdict" >>"$LOG"; say "$verdict"
    fi
  fi
}

# ── neovim overlay ─────────────────────────────────────────────────────
#  Two symlinks into an existing lazy.nvim config, not a config of its own.
#  The rice owns the look (apps/nvim); whatever else lives in ~/.config/nvim
#  keeps working, and `git pull` here updates the editor along with the bar.
deploy_nvim() {
  (( DO_NVIM )) || return 0
  headline "Neovim  ·  explorer left, tabs up top, glass all the way down"

  if ! command -v nvim >/dev/null 2>&1; then
    skip "neovim is not installed — overlay stays at $TARGET/apps/nvim"
    return 0
  fi

  # The overlay ships as lazy.nvim plugin specs. Something has to import them,
  # and that something is a lua/plugins directory — without one the files are
  # never read, so bootstrap the LazyVim starter rather than dropping dead
  # symlinks into a config that will ignore them.
  if [[ ! -d "$NVIM_CFG/lua/plugins" ]]; then
    if [[ -e "$NVIM_CFG" || -L "$NVIM_CFG" ]]; then
      warn "$NVIM_CFG has no lua/plugins — not a lazy.nvim config, leaving it alone"
      say  "wire it up by hand: $TARGET/apps/nvim/README.md"
      return 0
    fi
    local starter
    starter="$(mktemp -d)" || die "cannot create Neovim staging directory"
    if ! git clone --depth 1 https://github.com/LazyVim/starter "$starter/config" >>"$LOG" 2>&1; then
      rm -rf -- "$starter"
      die "could not clone the LazyVim starter; see $LOG or rerun with --no-nvim"
    fi
    rm -rf -- "$starter/config/.git"
    mkdir -p "$(dirname "$NVIM_CFG")" || die "cannot create Neovim config parent"
    mv -- "$starter/config" "$NVIM_CFG" || die "cannot deploy Neovim starter"
    rmdir -- "$starter"
    ok "LazyVim starter cloned into ${NVIM_CFG/#$HOME/\~}"
  fi

  if [[ -d "$NVIM_CFG/lua/verum" && ! -L "$NVIM_CFG/lua/verum" ]]; then
    backup_path "$NVIM_CFG/lua/verum"
  fi
  link_force "$TARGET/apps/nvim/lua/verum"             "$NVIM_CFG/lua/verum"
  link_force "$TARGET/apps/nvim/lua/plugins/verum.lua" "$NVIM_CFG/lua/plugins/verum.lua"
  ok "Ctrl+Shift+\` opens the terminal dock · Ctrl+B toggles the explorer"
}

apply_theme() {
  (( DO_THEME )) || { skip "theme install skipped"; return 0; }
  headline "Theme  ·  PureBlackGlass"
  if [[ -x "$TARGET/scripts/theme-install.sh" ]]; then
    if "$TARGET/scripts/theme-install.sh" >>"$LOG" 2>&1; then
      ok "GTK · Qt · Kvantum · portal pointed at PureBlackGlass"
    else
      die "theme-install.sh failed (see $LOG)"
    fi
  else
    die "scripts/theme-install.sh missing"
  fi
}

apply_services() {
  (( DO_SERVICES )) || return 0
  headline "Services"
  local entry scope svc
  MANAGED_SERVICES=()
  while IFS= read -r entry; do
    scope=${entry%%:*}; svc=${entry#*:}
    if [[ "$scope" == user ]]; then
      systemctl --user enable --now "$svc" >>"$LOG" 2>&1 || die "cannot enable user service $svc; see $LOG"
    else
      (( SUDO_OK )) || { skip "$entry requires sudo — skipped"; continue; }
      if ! systemctl cat "$svc.service" >/dev/null 2>&1; then
        if (( DO_PACKAGES )); then die "required service $svc is missing after package installation";
        else skip "$entry is not installed — config-only run"; continue; fi
      fi
      sudo systemctl enable --now "$svc" >>"$LOG" 2>&1 || die "cannot enable $svc; see $LOG"
    fi
    MANAGED_SERVICES+=("$entry")
    ok "$entry enabled"
  done < <(services_for)
}

apply_fan() {
  (( DO_LID )) || return 0
  local src="$TARGET/apps/udev/99-hp-fan.rules"
  [[ -f "$src" ]] || return 0
  # Only hp-wmi machines have the node this rule hands over; skip silently
  # everywhere else rather than littering /etc/udev with a dead rule.
  local h found=0
  for h in /sys/class/hwmon/hwmon*; do
    [[ -r "$h/name" ]] || continue
    [[ "$(<"$h/name")" == "hp" ]] && [[ -e "$h/pwm1_enable" ]] && { found=1; break; }
  done
  (( found )) || return 0
  headline "Fan control  ·  let the panel pin the fans without root"
  (( SUDO_OK )) || { warn "needs root — copy $src to /etc/udev/rules.d/ yourself"; return 0; }
  if sudo cp "$src" /etc/udev/rules.d/99-hp-fan.rules; then
    sudo udevadm control --reload >>"$LOG" 2>&1
    sudo udevadm trigger --subsystem-match=hwmon >>"$LOG" 2>&1
    ok "pwm1_enable handed to the wheel group"
  else
    warn "could not install the fan udev rule"
  fi
}

apply_lid() {
  (( DO_LID )) || return 0
  local src="$TARGET/apps/systemd/10-lid-lock.conf"
  [[ -f "$src" ]] || return 0
  headline "Lid policy  ·  lock and blank, never suspend"
  (( SUDO_OK )) || { warn "needs root — copy $src to /etc/systemd/logind.conf.d/ yourself"; return 0; }
  sudo mkdir -p /etc/systemd/logind.conf.d || die "cannot create lid policy directory"
  if sudo cp "$src" /etc/systemd/logind.conf.d/10-lid-lock.conf; then
    sudo rm -f /etc/systemd/logind.conf.d/10-lid-hibernate.conf
    ok "lid policy installed; reboot to apply it (logind is not restarted during setup)"
  else
    die "could not write logind policy"
  fi
}

# ══════════════════════════════════════════════════════════════════════
#  finish
# ══════════════════════════════════════════════════════════════════════
finish() {
  printf '\n'
  rule '─'
  local pad done_="I N S T A L L E D"
  pad=$(( (COLS - ${#done_}) / 2 )); (( pad < 0 )) && pad=0
  printf '%*s%s%s%s\n' "$pad" '' "$C_RED_HOT$BOLD" "$done_" "$RST"
  rule '─'
  printf '\n'
  kv "rice"       "$TARGET"
  kv "wallpapers" "$WALLPAPER_DIR"
  kv "log"        "$LOG"
  printf '\n   %sNext%s\n' "$BOLD$C_INK" "$RST"
  printf '   %s1%s  drop wallpapers into %s%s%s\n'  "$C_RED_HOT" "$RST" "$C_INK" "$WALLPAPER_DIR" "$RST"
  if [[ -z "$PICK_MONITOR" ]]; then
    printf '   %s2%s  automatic output configured; customise %s%s%s if needed\n' \
      "$C_RED_HOT" "$RST" "$C_INK" "$TARGET/config/settings.lua" "$RST"
  else
    printf '   %s2%s  output already set to %s%s%s\n' "$C_RED_HOT" "$RST" "$C_INK" "$PICK_MONITOR" "$RST"
  fi
  printf '   %s3%s  log out, pick the %sHyprland%s session, log in\n' "$C_RED_HOT" "$RST" "$C_INK" "$RST"
  printf '   %s4%s  later changes: %shyprctl reload%s\n' "$C_RED_HOT" "$RST" "$C_INK" "$RST"
  printf '\n   %sSUPER+Return terminal · SUPER+Space launcher · SUPER+L lock · SUPER+Q close%s\n' "$C_DIM" "$RST"
  printf '\n'
  rule '─'
  local tag="VerumDot — where the desktop stops arguing with itself."
  pad=$(( (COLS - ${#tag}) / 2 )); (( pad < 0 )) && pad=0
  printf '%*s%s%s%s\n\n' "$pad" '' "$C_VOID" "$tag" "$RST"

  if (( FACT_HYPR_RUNNING )) && [[ "$MODE" == "wizard" ]]; then
    if ui_yn "Hyprland is running — reload it now?" y; then
      # A plain reload keeps the engine already running; switching from the
      # legacy hyprlang engine to hyprland.lua needs a full reset.
      if [[ "$(hyprctl eval 'return nil' 2>/dev/null)" == ok* ]]; then
        hyprctl reload >/dev/null 2>&1 && ok "reloaded"
      else
        hyprctl reload full-reset >/dev/null 2>&1 && ok "reloaded (switched to the Lua config)"
      fi
    fi
  fi
}

# ══════════════════════════════════════════════════════════════════════
#  args + main
# ══════════════════════════════════════════════════════════════════════
usage() {
  init_style; banner
  cat <<EOF
   ${BOLD}${C_INK}USAGE${RST}
     ./setup.sh                 interactive wizard — packages + config
     ./setup.sh --auto          no questions asked, everything, sane defaults
     ./setup.sh --update        refresh existing rice; install missing dependencies
     ./setup.sh --packages      dependencies only
     ./setup.sh --config        deploy rice + theme only
     ./setup.sh --dry-run       print the plan, change nothing
     ./setup.sh --list-packages  print the current default repo / AUR manifest
     ./setup.sh --no-nvim       leave ~/.config/nvim untouched
     ./setup.sh --no-aur        skip AUR extras and the default VS Code package
     ./setup.sh --no-services   do not change running/system services
     ./setup.sh --no-lid        leave the system lid policy unchanged
     ./setup.sh --no-theme      skip GTK / Qt theme setup
     ./setup.sh --no-anim       skip the intro animation
     ./setup.sh --no-color      plain text, for logs and pipes

   ${BOLD}${C_INK}ONE COMMAND, FRESH MACHINE${RST}
     ${C_RED_HOT}bash <(curl -fsSL ${VD_REPO}/raw/main/install.sh)${RST}

   Installs to ${C_INK}${TARGET}${RST}. Anything already there is backed up
   as ${C_DIM}<path>.bak.<timestamp>${RST} — nothing is deleted.
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto|-y|--yes)            MODE="auto" ;;
      --config|--config-only)     MODE="config";   DO_PACKAGES=0; DO_CONFIG=1 ;;
      --update)                  MODE="update"; DO_PACKAGES=1; DO_CONFIG=1 ;;
      --packages|--packages-only) MODE="packages"; DO_PACKAGES=1; DO_CONFIG=0 ;;
      --dry-run|-n)               DRYRUN=1 ;;
      --list-packages)            LIST_PACKAGES=1 ;;
      --no-nvim)                  DO_NVIM=0 ;;
      --no-services)              DO_SERVICES=0 ;;
      --no-lid)                   DO_LID=0 ;;
      --no-theme)                 DO_THEME=0 ;;
      --no-aur)                   NO_AUR=1 ;;
      --no-anim)                  ANIM=0 ;;
      --no-color)                 COLOR=0; ANIM=0 ;;
      -h|--help)                  usage ;;
      *) init_style; die "unknown flag: $1   (try --help)" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  if (( LIST_PACKAGES )); then
    init_style
    build_pkg_lists
    printf '[repo]\n'; printf '%s\n' "${PACMAN_LIST[@]}"
    printf '[aur]\n'; (( ${#AUR_LIST[@]} )) && printf '%s\n' "${AUR_LIST[@]}"
    return 0
  fi
  if [[ "$MODE" == wizard && ! -t 0 ]] && (( ! DRYRUN )); then
    if { : </dev/tty; } 2>/dev/null; then exec </dev/tty
    else init_style; die "interactive setup needs a terminal; use --auto, --config or --packages"; fi
  fi
  init_style
  [[ "$(id -u)" -eq 0 ]] && die "do not run as root — sudo is used only where it is needed"

  [[ "$XDG_CFG" == "$HOME/.config" ]] || die "this rice currently requires XDG_CONFIG_HOME=$HOME/.config because its desktop configs use that path"
  if (( ! DRYRUN )); then
    mkdir -p "$(dirname "$LOG")" || die "cannot create log directory"
    : >"$LOG" || die "cannot create log file"
    printf 'VerumDot %s — %s\nsource: %s\n\n' "$VD_VERSION" "$(date)" "$RICE_SRC" >>"$LOG"
  fi

  clear 2>/dev/null
  banner
  preflight

  case "$MODE" in
    wizard) (( DRYRUN )) || wizard ;;
    auto)   say "--auto: full install with defaults, no questions"
            local mons; mons="$(detect_monitors | head -n1)"
            [[ -n "$mons" ]] && PICK_MONITOR="$mons"
            (( FACT_LAPTOP )) || DO_LID=0
            [[ -z "$FACT_AUR" ]] && DO_AUR_HELPER=1 ;;
    update) prepare_update ;;
    packages) say "--packages: dependencies only" ;;
    config)   say "--config: rice + theme only"
              local m2; m2="$(detect_monitors | head -n1)"
              [[ -n "$m2" ]] && PICK_MONITOR="$m2"
              (( FACT_LAPTOP )) || DO_LID=0 ;;
  esac

  # Explicit skip flags also win over answers in the interactive wizard.
  local arg
  for arg in "$@"; do
    case "$arg" in --no-nvim) DO_NVIM=0 ;; --no-aur) NO_AUR=1 ;; --no-theme) DO_THEME=0 ;; --no-services) DO_SERVICES=0 ;; --no-lid) DO_LID=0 ;; esac
  done
  show_plan

  if (( DO_PACKAGES || (DO_CONFIG && (DO_LID || DO_SERVICES)) )); then sudo_begin; fi

  STEP_TOTAL=0
  (( DO_PACKAGES )) && STEP_TOTAL=$(( STEP_TOTAL + 1 ))
  (( DO_CONFIG ))   && STEP_TOTAL=$(( STEP_TOTAL + 2 + DO_NVIM + DO_THEME + DO_SERVICES + DO_LID ))
  STEP_N=0

  (( DO_PACKAGES )) && install_packages
  verify_quickshell
  if (( DO_CONFIG )); then
    deploy_files
    if [[ "$MODE" == update && -n "$UPDATE_SETTINGS" ]]; then restore_update_settings; else personalise; fi
    deploy_nvim
    apply_theme
    [[ "$MODE" == update ]] && cleanup_retired_services
    apply_services
    apply_lid
    apply_fan
  fi
  if (( DO_PACKAGES && DO_CONFIG )); then
    (( DO_SERVICES )) || MANAGED_SERVICES=("${PREVIOUS_SERVICES[@]}")
    cleanup_retired_packages
    save_install_state
  fi
  sudo_end
  if (( DO_CONFIG )); then finish
  else ok "selected dependencies installed and Quickshell runtime checked"; fi
}

main "$@"
