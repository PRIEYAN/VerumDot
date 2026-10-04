"""Shared Python support for the rice.

The shell side has lib/; this is its counterpart for the two Python tools.
Both of them are *protocol* programs — their stdout is JSON consumed by the
quickshell control centre — so the pieces they share are the ones that keep
that protocol honest: a single command runner, a single error type that
serialises predictably, and a single entry point that guarantees exactly one
JSON object is printed whatever happens.
"""

from .errors import RiceError
from .process import Command, CommandError
from .cli import json_main

__all__ = ["RiceError", "Command", "CommandError", "json_main"]
