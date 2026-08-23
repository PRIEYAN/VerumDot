#!/usr/bin/env bash
# Tiny persisted stopwatch for the profile dropdown.
# Usage: profile-timer.sh status|toggle|reset
#
# On-disk format matches the previous Python implementation:
# {"running": bool, "elapsed": float, "started_at": float|null}

STORE="$HOME/.local/share/hypr/profile-timer.json"
DEFAULT='{"running":false,"elapsed":0.0,"started_at":null}'

now() { date +%s.%N; }

load() {
  if [ -f "$STORE" ] && jq -e . "$STORE" >/dev/null 2>&1; then
    # Merge over the default so a partial store still has every key.
    jq -c --argjson d "$DEFAULT" '$d * .' "$STORE" 2>/dev/null || printf '%s' "$DEFAULT"
  else
    printf '%s' "$DEFAULT"
  fi
}

save() {
  mkdir -p "$(dirname "$STORE")"
  tmp=$(mktemp "${STORE}.XXXXXX") || exit 1
  printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$STORE" || rm -f "$tmp"
}

state=$(load)
cmd="${1:-status}"

case "$cmd" in
  toggle)
    if [ "$(printf '%s' "$state" | jq -r '.running')" = "true" ]; then
      # Stopping: fold the running segment into elapsed.
      state=$(printf '%s' "$state" | jq -c --argjson n "$(now)" \
        '.elapsed = (.elapsed + ($n - (.started_at // $n))) | .running = false | .started_at = null')
    else
      state=$(printf '%s' "$state" | jq -c --argjson n "$(now)" \
        '.running = true | .started_at = $n')
    fi
    save "$state"
    ;;
  reset)
    state="$DEFAULT"
    save "$state"
    ;;
esac

# Elapsed includes the in-flight segment while running.
read -r elapsed running <<< "$(printf '%s' "$state" | jq -r --argjson n "$(now)" \
  '((if .running then .elapsed + ($n - (.started_at // $n)) else .elapsed end) | floor | tostring)
   + " " + (.running | tostring)')"

printf '%02d:%02d:%02d %s\n' \
  $(( elapsed / 3600 )) $(( (elapsed % 3600) / 60 )) $(( elapsed % 60 )) \
  "$([ "$running" = "true" ] && echo Pause || echo Start)"
