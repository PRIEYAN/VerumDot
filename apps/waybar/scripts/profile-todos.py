#!/usr/bin/env python3
# Tiny JSON-backed todo store for the profile dropdown.
# Usage: profile-todos.py list|add TEXT|toggle INDEX|remove INDEX
import json
import sys
from pathlib import Path

STORE = Path.home() / ".local/share/hypr/profile-todos.json"


def load():
    if STORE.exists():
        try:
            return json.loads(STORE.read_text())
        except json.JSONDecodeError:
            return []
    return []


def save(todos):
    STORE.parent.mkdir(parents=True, exist_ok=True)
    STORE.write_text(json.dumps(todos, indent=2))


def main():
    todos = load()
    if len(sys.argv) < 2 or sys.argv[1] == "list":
        for t in todos:
            mark = "x" if t["done"] else " "
            print(f"[{mark}] {t['text']}")
        return

    cmd = sys.argv[1]
    if cmd == "add" and len(sys.argv) > 2:
        todos.append({"text": sys.argv[2], "done": False})
        save(todos)
    elif cmd == "toggle" and len(sys.argv) > 2:
        i = int(sys.argv[2])
        if 0 <= i < len(todos):
            todos[i]["done"] = not todos[i]["done"]
            save(todos)
    elif cmd == "remove" and len(sys.argv) > 2:
        i = int(sys.argv[2])
        if 0 <= i < len(todos):
            todos.pop(i)
            save(todos)


if __name__ == "__main__":
    main()
