#!/usr/bin/env python3
import json
import subprocess
import sys

ICONS = {
    "kitty": "",
    "alacritty": "",
    "wezterm": "",
    "foot": "",
    "firefox": "",
    "chromium": "",
    "brave": "",
    "google-chrome": "",
    "vivaldi": "",
    "code": "",
    "code-oss": "",
    "jetbrains-idea": "",
    "obsidian": "",
    "thunar": "",
    "nautilus": "",
    "dolphin": "",
}


def run_cmd(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()
    except subprocess.CalledProcessError:
        return ""


active = run_cmd(["hyprctl", "-j", "activewindow"])
if not active:
    print(json.dumps({"text": " No app", "tooltip": "No active window"}))
    sys.exit(0)

try:
    active = json.loads(active)
except json.JSONDecodeError:
    print(json.dumps({"text": " No app", "tooltip": "Active window info unavailable"}))
    sys.exit(0)

app_class = (active.get("class") or active.get("app") or active.get("name") or "Unknown").lower()
icon = ICONS.get(app_class, "")
title = active.get("title") or active.get("class") or active.get("app") or "No title"
label = title if len(title) <= 30 else title[:27] + "..."
text = f"{icon} {label}"
print(json.dumps({"text": text, "tooltip": title}))
