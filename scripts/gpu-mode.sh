#!/usr/bin/env bash
# GPU-mode module for eww, driven by OmenCore (omencore-cli) — HP Omen/Victus
# control tool. Two mutually-exclusive modes surfaced in the battery dropdown:
#   Integrated  -> Intel iGPU only, NVIDIA dGPU powered off (battery)
#   Hybrid      -> Intel UHD + NVIDIA (PRIME render-offload available)
#
# WHY OmenCore (not supergfxctl): the user requires the HP "Omen" tooling and
# explicitly forbids supergfxctl. OmenCore is a .NET tool with a CLI, uses HP's
# own firmware/WMI path for GPU switching, and does NOT wrap supergfxctl. This
# script stays pure shell (repo rule: no Python) and only shells out to it.
#
# Subcommands:
#   (none)      emit JSON {text,tooltip,class,mode} for the bar/poll
#   get         print the current mode (Integrated|Hybrid|Discrete|unknown)
#   set <mode>  switch to Integrated|Hybrid via pkexec (root); a reboot is
#               required to apply, so we only request + notify, never reboot.
#   init        seed the eww gpu_* vars at startup (no poll-interval lag)
#
# IMPORTANT — one unconfirmed detail: OmenCore's *CLI* GPU-switch verb is not
# documented (GPU switching may be GUI-only). So `set` probes a list of
# candidate invocations (OMEN_SET_CANDIDATES) and uses the first that exits 0;
# if all fail it launches the OmenCore GUI as a fallback. Once you run
# `omencore-cli --help` on the machine, pin the real verb in OMEN_SET_CANDIDATES.
#
# Also: whether the internal panel can actually be rerouted depends on the
# Victus BIOS exposing a MUX. Many Victus 15 / base 16 models have none, in
# which case "Integrated" powers the dGPU down but Hybrid stays offload-only.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/json.sh"

# --- configuration ---------------------------------------------------------
# Resolve the OmenCore CLI (system-wide install, then PATH).
OMEN_CLI="$(command -v omencore-cli 2>/dev/null || printf '/usr/local/bin/omencore-cli')"
OMEN_GUI="$(command -v omencore-gui 2>/dev/null || printf '/usr/local/bin/omencore-gui')"

# Persisted last-known mode — lets the widget/poll reflect state WITHOUT a root
# prompt every interval (reading OmenCore may need root). Written on each `set`.
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/eww-gpu-mode"
STATE_FILE="$STATE_DIR/mode"

# Candidate `set` invocations, tried in order until one exits 0. $1=mode(lower).
# Adjust to the real verb from `omencore-cli --help`.
omen_set_candidates() {
  local m="$1"
  printf '%s\n' \
    "gpu --mode $m" \
    "gpu $m" \
    "gpu-mode $m" \
    "mux $m" \
    "graphics --mode $m"
}

# Nerd Font glyphs (printf'd from UTF-8 bytes so the Private-Use-Area chars
# survive editing/encoding round-trips, matching performance-mode.sh):
#   chip      U+F0EE0 (integrated / single GPU)
#   expansion U+F08AE (hybrid / dual GPU)
G_IGPU=$(printf '\xf3\xb0\xbb\xa0')
G_HYBRID=$(printf '\xf3\xb0\xa2\xae')

have_omen() { [ -x "$OMEN_CLI" ] || command -v omencore-cli >/dev/null 2>&1; }

# Best-effort READ of current mode without root, in priority order:
#   1) our persisted state file (authoritative for what we last set)
#   2) live detection from the kernel: is the NVIDIA dGPU present & driven?
detect_mode() {
  if [ -r "$STATE_FILE" ]; then
    cat "$STATE_FILE"; return 0
  fi
  # dGPU removed from the PCI bus (integrated) -> no NVIDIA VGA/3D controller.
  if command -v lspci >/dev/null 2>&1; then
    if lspci -nn 2>/dev/null | grep -Eiq '\[10de:.*\](.*VGA|.*3D)'; then
      # NVIDIA present: hybrid if the module is loaded, else still hybrid-capable.
      printf 'Hybrid'; return 0
    else
      printf 'Integrated'; return 0
    fi
  fi
  # Fallback: nvidia kernel interface present?
  if [ -d /proc/driver/nvidia ]; then printf 'Hybrid'; else printf 'unknown'; fi
}

# emit <text> <tooltip> <class> <mode>
emit() {
  printf '{"text":%s,"tooltip":%s,"class":%s,"mode":%s}\n' \
    "$(json_str "$1")" "$(json_str "$2")" "$(json_str "$3")" "$(json_str "$4")"
}

status_json() {
  if ! have_omen; then
    emit "$G_IGPU" "GPU switching unavailable (omencore-cli not installed)" "na" "na"
    return
  fi
  local mode; mode=$(detect_mode)
  case "$mode" in
    Integrated) emit "$G_IGPU"   "GPU: Integrated only (Intel)"       "integrated" "Integrated" ;;
    Hybrid)     emit "$G_HYBRID" "GPU: Hybrid (Intel + NVIDIA)"       "hybrid"     "Hybrid" ;;
    Discrete)   emit "$G_HYBRID" "GPU: Discrete (NVIDIA)"             "hybrid"     "Discrete" ;;
    *)          emit "$G_HYBRID" "GPU: ${mode:-unknown}"              "hybrid"     "${mode:-unknown}" ;;
  esac
}

# Push current state into eww's gpu_* vars so the bar reflects it instantly.
push_eww() {
  local json; json=$(status_json)
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

# Run the switch as root via pkexec, trying each candidate verb until success.
# Returns 0 on the first that exits 0.
try_switch() {
  local m="$1" args
  while IFS= read -r args; do
    [ -n "$args" ] || continue
    # shellcheck disable=SC2086 — intentional word-split of the candidate args.
    if pkexec "$OMEN_CLI" $args >/dev/null 2>&1; then
      return 0
    fi
  done < <(omen_set_candidates "$m")
  return 1
}

case "$1" in
  get)
    detect_mode
    ;;
  set)
    target="$2"
    case "$target" in
      Integrated|Hybrid|Discrete) : ;;
      *) echo "usage: gpu-mode.sh set Integrated|Hybrid|Discrete" >&2; exit 2 ;;
    esac
    if ! have_omen; then
      notify "GPU switch failed" "OmenCore (omencore-cli) is not installed"
      exit 1
    fi
    if [ "$(detect_mode)" = "$target" ]; then
      notify "GPU mode" "Already in ${target} mode"
      push_eww; exit 0
    fi
    lower=$(printf '%s' "$target" | tr '[:upper:]' '[:lower:]')
    if try_switch "$lower"; then
      mkdir -p "$STATE_DIR"; printf '%s' "$target" > "$STATE_FILE"
      case "$target" in
        Integrated) msg="Switched to Integrated (Intel only). Reboot to apply." ;;
        Hybrid)     msg="Switched to Hybrid (Intel + NVIDIA). Reboot to apply." ;;
        Discrete)   msg="Switched to Discrete (NVIDIA). Reboot to apply." ;;
      esac
      notify "GPU mode → ${target}" "$msg"
      push_eww
    else
      # CLI verb unknown / GPU switch is GUI-only on this build → open the GUI.
      notify "GPU switch (CLI)" "No working omencore-cli GPU verb — opening OmenCore GUI. Set '${target}' there, then reboot."
      [ -x "$OMEN_GUI" ] && setsid -f "$OMEN_GUI" >/dev/null 2>&1
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
