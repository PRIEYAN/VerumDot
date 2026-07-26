#!/usr/bin/env bash

CACHE_FILE="$HOME/.cache/hypr_wallpaper"
DEFAULT_WALLPAPER="$HOME/Pictures/Wallpapers/suf.png"
WATCHER_PID_FILE="$HOME/.cache/hypr_wallpaper_watcher.pid"

# Ensure cache dir exists
mkdir -p "$(dirname "$CACHE_FILE")"

set_wallpaper() {
    local img="$1"
    
    # Check if file exists, else use default
    if [[ ! -f "$img" ]]; then
        img="$DEFAULT_WALLPAPER"
    fi

    # Persist choice
    echo "$img" > "$CACHE_FILE"

    # hyprpaper v0.8+ unified IPC: the `wallpaper` command auto-loads the
    # image, so a separate `preload` is unnecessary (and rejected as an
    # "invalid hyprpaper request" on this version). Setting it directly is
    # what actually sticks.
    local monitors
    monitors=$(hyprctl monitors | grep "Monitor" | awk '{print $2}')
    for m in $monitors; do
        hyprctl hyprpaper wallpaper "$m,$img" >/dev/null 2>&1
    done

    # Start watcher for this file
    start_watcher "$img"
}

start_watcher() {
    local img="$1"
    
    # Kill previous watcher
    if [[ -f "$WATCHER_PID_FILE" ]]; then
        local pid=$(cat "$WATCHER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
        fi
        rm "$WATCHER_PID_FILE"
    fi

    # Don't watch the default wallpaper
    if [[ "$img" == "$DEFAULT_WALLPAPER" ]]; then
        return
    fi

    # Background watcher
    (
        # Wait for deletion
        inotifywait -e delete_self "$img" >/dev/null 2>&1
        # Fallback to default
        "$0" set "$DEFAULT_WALLPAPER"
    ) &
    echo $! > "$WATCHER_PID_FILE"
}

init() {
    # Ensure hyprpaper is running
    if ! pgrep -x "hyprpaper" > /dev/null; then
        hyprpaper &
    fi

    # Wait for hyprpaper's IPC socket instead of a blind sleep, so the
    # first `wallpaper` call doesn't race the daemon's startup.
    local sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.hyprpaper.sock"
    for _ in $(seq 1 50); do
        [[ -S "$sock" ]] && break
        sleep 0.1
    done

    local img="$DEFAULT_WALLPAPER"
    if [[ -f "$CACHE_FILE" ]]; then
        img="$(cat "$CACHE_FILE")"
    fi

    # Never restore Hyprland's stock wallpaper: if the cached choice is the
    # old default or no longer exists, fall back to the user's default.
    if [[ "$img" == /usr/share/hypr/* || ! -f "$img" ]]; then
        img="$DEFAULT_WALLPAPER"
    fi

    set_wallpaper "$img"
}

case "$1" in
    set)
        set_wallpaper "$2"
        ;;
    init)
        init
        ;;
    *)
        echo "Usage: $0 {set path/to/img|init}"
        exit 1
        ;;
esac
