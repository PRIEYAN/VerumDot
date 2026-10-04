"""The entry point shared by the JSON-emitting tools."""

from __future__ import annotations

import json
import sys
from typing import Any, Callable

from .errors import RiceError


def json_main(action: Callable[[], Any]) -> int:
    """Run `action` and print exactly one JSON object.

    The guarantee matters: the control centre parses this stdout, so a
    traceback printed alongside a result, or nothing printed at all, is a
    hung panel rather than a visible failure.

    An expected failure (RiceError) becomes {"error": "..."} with exit 1.
    An unexpected one is still reported as JSON — the caller must never be
    left waiting — but the traceback goes to stderr so it stays findable,
    and the exit code distinguishes it.
    """
    try:
        print(json.dumps(action()))
        return 0
    except RiceError as error:
        print(json.dumps({"error": str(error)}))
        return 1
    except Exception as error:  # noqa: BLE001 - deliberately broad; see above
        import traceback

        traceback.print_exc(file=sys.stderr)
        print(json.dumps({"error": f"internal error: {error}"}))
        return 2
