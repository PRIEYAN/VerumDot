#!/usr/bin/env bash
#
# Instant battery/charger refresh for waybar. Watches power events via upower
# and pokes the custom/battery module (RTMIN+10) the moment AC is plugged or
# unplugged, so the charging bolt appears/disappears immediately instead of
# waiting for the module's poll interval. Falls back to polling sysfs if
# upower is unavailable.

SIG="-RTMIN+10"

poke() { pkill "$SIG" waybar >/dev/null 2>&1; }

# Refresh once on start so state is correct right after launch.
poke

if command -v upower >/dev/null 2>&1; then
  # Each power event prints a line; refresh on any of them (cheap, rare).
  upower --monitor 2>/dev/null | while read -r _; do
    poke
  done
else
  # Fallback: watch the AC 'online' flag for changes.
  adp=$(ls /sys/class/power_supply/ | grep -m1 -E '^(ADP|AC|ACAD)')
  file="/sys/class/power_supply/${adp}/online"
  last=""
  while :; do
    cur=$(cat "$file" 2>/dev/null)
    [ "$cur" != "$last" ] && { poke; last=$cur; }
    sleep 2
  done
fi
