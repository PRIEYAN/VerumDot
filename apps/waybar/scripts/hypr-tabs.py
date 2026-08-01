#!/usr/bin/env python3
import json
import subprocess
import sys
import time
import signal
import os
import socket
from pathlib import Path

# Expanded and updated icons list using common Nerd Font codepoints
ICONS = {
    "kitty": "󰄛",
    "alacritty": "󰆍",
    "wezterm": "󰄛",
    "foot": "󰆍",
    "firefox": "󰈹",
    "chromium": "",
    "brave": "󰖟",
    "brave-browser": "󰖟",
    "google-chrome": "",
    "vivaldi": "󰖟",
    "code": "󰨞",
    "code-oss": "󰨞",
    "visual-studio-code-bin": "󰨞",
    "jetbrains-idea": "󰗚",
    "obsidian": "󱓧",
    "thunar": "󰉋",
    "nautilus": "󰉋",
    "dolphin": "󰉋",
    "pcmanfm": "󰉋",
    "discord": "󰙯",
    "vesktop": "󰙯",
    "slack": "󰒱",
    "spotify": "󰓇",
    "spotify-launcher": "󰓇",
    "telegram-desktop": "󰔁",
    "telegram": "󰔁",
    "org.telegram.desktop": "󰔁",
    "vlc": "󰕼",
    "mpv": "󰕼",
    "gimp": "󰔉",
    "inkscape": "󰔉",
    "blender": "󰔉",
    "steam": "󰓓",
    "pavucontrol": "󰓃",
    "antigravity": "󰚩",
}

DOT = "●"
DEFAULT_ICON = "" 

def run_cmd(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return ""

def load_json(cmd):
    out = run_cmd(cmd)
    if not out:
        return None
    try:
        return json.loads(out)
    except Exception:
        return None

def icon_for(app_class):
    if not app_class:
        return DEFAULT_ICON
    app_class = app_class.lower()
    if app_class in ICONS:
        return ICONS[app_class]
    # Partial match
    for key in ICONS:
        if key in app_class:
            return ICONS[key]
    return DEFAULT_ICON

def compute_output(workspace_id):
    active_ws = load_json(["hyprctl", "-j", "activeworkspace"])
    clients = load_json(["hyprctl", "-j", "clients"]) or []

    active_ws_id = None
    if isinstance(active_ws, dict):
        active_ws_id = active_ws.get('id')
    
    ws_clients = []
    for c in clients:
        ws = c.get('workspace', {})
        wid = None
        if isinstance(ws, dict):
            wid = ws.get('id')
        else:
            try:
                wid = int(ws)
            except:
                wid = None
        
        if wid == workspace_id:
            ws_clients.append(c)

    is_active = (workspace_id == active_ws_id)

    if not ws_clients:
        cls = 'active' if is_active else 'inactive'
        return {"text": str(workspace_id), "class": cls, "tooltip": f"Workspace {workspace_id}"}

    # Sort clients to be deterministic
    ws_clients.sort(key=lambda x: x.get('address', ''))
    top = ws_clients[0]
    
    app_class = (top.get('class') or top.get('initialClass') or top.get('app') or top.get('name') or "")
    title = top.get('title') or top.get('initialTitle') or app_class or f"Workspace {workspace_id}"
    icon = icon_for(app_class)

    return {"text": icon, "class": ("active" if is_active else "inactive"), "tooltip": title}

def handle_sigterm(signum, frame):
    sys.exit(0)

def socket2_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if signature:
        path = Path(runtime) / "hypr" / signature / ".socket2.sock"
        if path.exists():
            return str(path)

    hypr_dir = Path(runtime) / "hypr"
    if not hypr_dir.exists():
        return None
    sockets = sorted(hypr_dir.glob("*/.socket2.sock"), key=lambda p: p.stat().st_mtime, reverse=True)
    return str(sockets[0]) if sockets else None

def event_stream():
    path = socket2_path()
    if not path:
        return None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(path)
        return sock.makefile("r")
    except Exception:
        return None

def relevant_event(line):
    line = line.lower()
    return any(k in line for k in (
        "workspace",
        "activewindow",
        "openwindow",
        "closewindow",
        "movewindow",
        "windowtitle",
        "changefloatingmode",
        "fullscreen",
        "focusedmon",
    ))

def main():
    if len(sys.argv) != 2:
        return
    try:
        workspace_id = int(sys.argv[1])
    except ValueError:
        return

    signal.signal(signal.SIGTERM, handle_sigterm)
    signal.signal(signal.SIGINT, handle_sigterm)

    last = None

    def emit():
        nonlocal last
        current = compute_output(workspace_id)
        if current != last:
            print(json.dumps(current), flush=True)
            last = current

    emit()
    stream = event_stream()
    if stream is None:
        while True:
            emit()
            time.sleep(0.2)

    while True:
        line = stream.readline()
        if not line:
            stream = event_stream()
            if stream is None:
                time.sleep(0.2)
                emit()
            continue
        if relevant_event(line):
            emit()

if __name__ == '__main__':
    main()
