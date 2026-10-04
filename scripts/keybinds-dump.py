#!/usr/bin/env python3
"""Dump this rice's Hyprland keybinds as JSON for the quickshell cheat sheet.

Reads hyprland.conf, follows every `source =`, and turns each bind into a row
the popup can render:

    {"title": "Apps", "items": [{"keys": [["Super","T"]], "action": "Terminal"}]}

`keys` is a list of chord variants, because several binds can share one
action. The parsing and classification live in lib/python/hyprrice/keybinds.py.

    keybinds-dump.py [config]      # default: ../hyprland.conf
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HYPR_HOME = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HYPR_HOME / "lib" / "python"))

from hyprrice.keybinds import CheatSheet, ConfigReader   # noqa: E402


def main() -> int:
    config = sys.argv[1] if len(sys.argv) > 1 else str(HYPR_HOME / "hyprland.conf")
    binds = ConfigReader().read(config)
    json.dump(CheatSheet(binds).sections(), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
