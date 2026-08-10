#!/usr/bin/env python3
# Tiny persisted stopwatch for the profile dropdown.
# Usage: profile-timer.py status|toggle|reset
import json
import sys
import time
from pathlib import Path

STORE = Path.home() / ".local/share/hypr/profile-timer.json"
DEFAULT = {"running": False, "elapsed": 0.0, "started_at": None}


def load():
    if STORE.exists():
        try:
            return {**DEFAULT, **json.loads(STORE.read_text())}
        except json.JSONDecodeError:
            return dict(DEFAULT)
    return dict(DEFAULT)


def save(state):
    STORE.parent.mkdir(parents=True, exist_ok=True)
    STORE.write_text(json.dumps(state))


def current_elapsed(state):
    if state["running"] and state["started_at"] is not None:
        return state["elapsed"] + (time.time() - state["started_at"])
    return state["elapsed"]


def fmt(seconds):
    seconds = int(seconds)
    h, seconds = divmod(seconds, 3600)
    m, s = divmod(seconds, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def main():
    state = load()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"

    if cmd == "toggle":
        if state["running"]:
            state["elapsed"] = current_elapsed(state)
            state["running"] = False
            state["started_at"] = None
        else:
            state["running"] = True
            state["started_at"] = time.time()
        save(state)
    elif cmd == "reset":
        state = dict(DEFAULT)
        save(state)

    elapsed = current_elapsed(state)
    label = "Pause" if state["running"] else "Start"
    print(f"{fmt(elapsed)} {label}")


if __name__ == "__main__":
    main()
