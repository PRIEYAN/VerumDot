#!/usr/bin/env python3
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


def hidden_workspace_open():
    try:
        out = subprocess.run(
            ["hyprctl", "-j", "monitors"],
            capture_output=True, text=True, timeout=1,
        ).stdout
        for mon in json.loads(out):
            if mon.get("focused"):
                return mon.get("specialWorkspace", {}).get("name") == "special:hidden"
    except Exception:
        pass
    return False


def render():
    now = datetime.now()
    return {
        "text": now.strftime("%a %d %b  %H:%M"),
        "tooltip": now.strftime("%A, %d %B %Y  %H:%M:%S"),
        "class": ["hidden-ws"] if hidden_workspace_open() else [],
    }


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
        return None, None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.connect(path)
        return sock, sock.makefile("r")
    except Exception:
        return None, None


def relevant_event(line):
    line = line.lower()
    return "activespecial" in line or "focusedmon" in line or "monitoradded" in line


def main():
    last = None

    def emit():
        nonlocal last
        current = render()
        if current != last:
            print(json.dumps(current), flush=True)
            last = current

    emit()

    sock, stream = event_stream()
    next_tick = time.monotonic() + 1

    while True:
        if stream is None:
            time.sleep(max(0, next_tick - time.monotonic()))
            next_tick = time.monotonic() + 1
            emit()
            sock, stream = event_stream()
            continue

        sock.settimeout(max(0.01, next_tick - time.monotonic()))
        try:
            line = stream.readline()
        except socket.timeout:
            next_tick = time.monotonic() + 1
            emit()
            continue
        except Exception:
            sock, stream = None, None
            continue

        if not line:
            sock, stream = None, None
            continue

        if relevant_event(line):
            emit()

        if time.monotonic() >= next_tick:
            next_tick = time.monotonic() + 1
            emit()


if __name__ == "__main__":
    main()
