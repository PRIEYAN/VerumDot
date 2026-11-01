"""Tor reachability and browser operations, independent of MAC/profile storage."""

from __future__ import annotations

import json
from typing import Any, Callable, Protocol

from .errors import RiceError
from .process import CommandRunner

TOR_ENDPOINT = "https://check.torproject.org/api/ip"
TOR_SOCKS = "socks5h://127.0.0.1:9150"


class IpChecker(Protocol):
    def check(self) -> dict[str, Any]: ...


class BrowserControl(Protocol):
    def available(self) -> bool: ...
    def launch(self) -> None: ...
    def install(self) -> None: ...


class TorIpChecker:
    def __init__(self, command: CommandRunner, *, endpoint: str = TOR_ENDPOINT,
                 proxy: str = TOR_SOCKS):
        self._command = command
        self._endpoint = endpoint
        self._proxy = proxy

    def check(self) -> dict[str, Any]:
        result = {"direct_ip": "Unavailable", "tor_ip": "Not connected", "tor_verified": False}
        direct = self._fetch_json(("--noproxy", "*"))
        if direct is not None:
            result["direct_ip"] = direct["IP"]
        reply = self._fetch_json(("--noproxy", "", "--proxy", self._proxy))
        if reply is not None:
            result["tor_verified"] = reply.get("IsTor") is True
            result["tor_ip"] = reply["IP"] if result["tor_verified"] else "Tor could not be verified"
        return result

    def _fetch_json(self, extra: tuple[str, ...]) -> dict[str, Any] | None:
        base = ("curl", "-4", "--fail", "--silent", "--show-error",
                "--connect-timeout", "8", "--max-time", "20")
        try:
            reply = json.loads(self._command.run(*base, *extra, self._endpoint, timeout=25))
        except (RiceError, ValueError):
            return None
        if not isinstance(reply, dict) or not isinstance(reply.get("IP"), str) or not reply["IP"]:
            return None
        return reply


class TorBrowser:
    def __init__(self, command: CommandRunner, *, launch: Callable[..., None],
                 which: Callable[[str], str | None]):
        self._command = command
        self._launch = launch
        self._which = which

    def available(self) -> bool:
        return self._which("torbrowser-launcher") is not None

    def launch(self) -> None:
        if not self.available():
            raise RiceError("Install Tor Browser first.")
        self._launch("torbrowser-launcher")

    def install(self) -> None:
        self._command.run("pkexec", "/usr/bin/pacman", "-S", "--needed", "--noconfirm",
                          "torbrowser-launcher", timeout=600)
