#!/usr/bin/env python3
"""NetworkManager MAC controls and explicitly scoped Tor Browser checks.

Prints exactly one JSON object on stdout, which is what the quickshell
control centre parses. The behaviour lives in lib/python/hyprrice/privacy.py.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib" / "python"))

from hyprrice import RiceError, json_main           # noqa: E402
from hyprrice.privacy import PrivacyService         # noqa: E402

USAGE = "Usage: privacy-control.py status|mac-on|mac-off|browser|install|check"


def dispatch(service: PrivacyService, action: str):
    """Map a verb to a call. A table, so an unknown verb cannot fall through
    into a branch that does something — every action here changes the
    network or installs software."""
    actions = {
        "status":  service.status,
        "check":   service.check_ip,
        "browser": service.launch_browser,
        "install": service.install_browser,
        "mac-on":  lambda: service.set_randomised(True),
        "mac-off": lambda: service.set_randomised(False),
    }
    handler = actions.get(action)
    if handler is None:
        raise RiceError(USAGE)
    return handler()


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    service = PrivacyService()
    return json_main(lambda: dispatch(service, action))


if __name__ == "__main__":
    sys.exit(main())
