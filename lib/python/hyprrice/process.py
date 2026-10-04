"""Running external commands."""

from __future__ import annotations

import os
import subprocess
from typing import Sequence

from .errors import RiceError

DEFAULT_TIMEOUT = 40


class CommandError(RiceError):
    """A command exited non-zero, timed out, or was not found."""


class Command:
    """A runner for external commands.

    Exists as a class rather than a bare function so a caller can fix the
    timeout and the environment once, and so tests can substitute a double.
    The tools below depend on *this interface*, not on subprocess.

    LC_ALL=C is forced because every caller parses the output: a localised
    nmcli or upower would otherwise break the parsing on a non-English
    system, which is the kind of bug that never shows up where it is written.
    """

    def __init__(self, timeout: int = DEFAULT_TIMEOUT, env: dict[str, str] | None = None):
        self._timeout = timeout
        self._env = {**(env or os.environ), "LC_ALL": "C"}

    def run(self, *args: str, timeout: int | None = None) -> str:
        """Run a command and return its stdout, stripped.

        Raises CommandError on a non-zero exit, a timeout, or a missing
        executable — so a caller never has to check a return code *and*
        catch three unrelated exception types.
        """
        try:
            result = subprocess.run(
                args,
                capture_output=True,
                text=True,
                timeout=timeout if timeout is not None else self._timeout,
                env=self._env,
            )
        except subprocess.TimeoutExpired as error:
            raise CommandError(f"{args[0]} timed out") from error
        except FileNotFoundError as error:
            raise CommandError(f"{args[0]} is not installed") from error

        if result.returncode:
            detail = result.stderr.strip() or result.stdout.strip()
            raise CommandError(detail or f"{args[0]} failed")
        return result.stdout.strip()

    def try_run(self, *args: str, timeout: int | None = None, default: str = "") -> str:
        """Run a command, returning `default` instead of raising."""
        try:
            return self.run(*args, timeout=timeout)
        except CommandError:
            return default

    @staticmethod
    def detach(*args: str) -> None:
        """Start a program that must outlive this process."""
        subprocess.Popen(
            args,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
