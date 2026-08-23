#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
mode_file=/tmp/waybar-performance-mode
mode=$(cat "$mode_file" 2>/dev/null || echo normal)
if [ "$1" = "toggle" ]; then
  case "$mode" in
    normal) mode=performance;;
    performance) mode=battery;;
    battery) mode=normal;;
  esac
  printf '%s' "$mode" > "$mode_file"
  if command -v cpupower >/dev/null 2>&1; then
    if [ "$mode" = "performance" ]; then
      sudo cpupower frequency-set -g performance
    elif [ "$mode" = "battery" ]; then
      sudo cpupower frequency-set -g powersave
    else
      sudo cpupower frequency-set -g ondemand
    fi
  fi
  # Repaint the battery module, which colours its glyph by mode
  # (red = performance, green = battery, white = normal).
  pkill -RTMIN+10 waybar >/dev/null 2>&1 || true
  if command -v notify-send >/dev/null 2>&1; then
    case "$mode" in
      performance) notify-send -t 1500 -h string:x-canonical-private-synchronous:perf-mode "(ᗒᗣᗕ)՞" ;;
      battery)     notify-send -t 1500 -h string:x-canonical-private-synchronous:perf-mode "(˶ᵔ ᵕ ᵔ˶)" ;;
      normal)      notify-send -t 1500 -h string:x-canonical-private-synchronous:perf-mode "ツ" ;;
    esac
  fi
  exit 0
fi
icon=''
case "$mode" in
  performance) icon='' ;;
  battery) icon='' ;;
  normal) icon='' ;;
esac
printf '{"text":"%s %s","tooltip":"Click to toggle performance mode"}' "$icon" "$mode"
