"""NetworkManager MAC randomisation and Tor reachability checks.

Three responsibilities, three classes:

  ConnectionInspector  reads the active connection out of NetworkManager
  ProfileStore         remembers the setting in force before we changed it
  MacRandomiser        performs the change, and undoes it if it misfires

They were one module of free functions sharing a `run()` and a pair of
load/save helpers. Splitting them is what makes the rollback path testable:
MacRandomiser takes its collaborators as arguments, so a test can hand it a
store and an inspector without touching the real network.
"""

from __future__ import annotations

import fcntl
import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .errors import RiceError
from .process import Command

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "hypr/privacy"

TOR_ENDPOINT = "https://check.torproject.org/api/ip"
TOR_SOCKS = "socks5h://127.0.0.1:9150"
RANDOM = "random"


@dataclass(frozen=True)
class Connection:
    """The active connection, and the MAC setting currently applied to it."""

    device: str
    uuid: str
    prop: str
    setting: str
    mac: str

    def as_profile(self) -> dict[str, str]:
        return {"device": self.device, "uuid": self.uuid, "prop": self.prop,
                "setting": self.setting, "mac": self.mac}


class ConnectionInspector:
    """Finds the connection a MAC change should apply to."""

    WIFI_PROP = "802-11-wireless.cloned-mac-address"
    ETHERNET_PROP = "802-3-ethernet.cloned-mac-address"

    def __init__(self, command: Command):
        self._command = command

    def active(self) -> Connection:
        device, kind = self._preferred_device()
        uuid = self._command.run("nmcli", "-g", "GENERAL.CON-UUID", "device", "show", device)
        prop = self.WIFI_PROP if kind == "wifi" else self.ETHERNET_PROP
        setting = self._command.run(
            "nmcli", "--escape", "no", "-g", prop, "connection", "show", "uuid", uuid
        )
        mac = (Path("/sys/class/net") / device / "address").read_text().strip()
        return Connection(device=device, uuid=uuid, prop=prop, setting=setting, mac=mac)

    def _preferred_device(self) -> tuple[str, str]:
        """The connected device carrying the default route, if there is one.

        Sorting by "is this the default route" matters on a machine with
        both Wi-Fi and Ethernet up: randomising the MAC of the interface
        that is not actually carrying traffic looks like a no-op to the user.
        """
        routes = json.loads(self._command.run("ip", "-j", "route", "show", "default"))
        default_devices = {route.get("dev") for route in routes}

        devices: list[tuple[str, str]] = []
        for row in self._command.run("nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device").splitlines():
            device, kind, state = row.split(":", 2)
            if kind in ("wifi", "ethernet") and state == "connected":
                devices.append((device, kind))

        if not devices:
            raise RiceError("Connect to Wi-Fi or Ethernet first.")
        devices.sort(key=lambda item: item[0] not in default_devices)
        return devices[0]


class ProfileStore:
    """Remembers the MAC setting that was in force before randomisation.

    Without this there is nothing to restore: 'off' has to put back whatever
    the user had, which may well not be the NetworkManager default.
    """

    def __init__(self, directory: Path = STATE_DIR):
        self._directory = directory
        self._path = directory / "profiles.json"

    def load(self) -> dict[str, Any]:
        try:
            return json.loads(self._path.read_text())
        except FileNotFoundError:
            return {}
        except json.JSONDecodeError:
            # A corrupt store must not wedge the feature; the worst case is
            # that 'off' has nothing to restore, which it reports clearly.
            return {}

    def save(self, profiles: dict[str, Any]) -> None:
        self._directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = self._directory / "profiles.tmp"
        temporary.write_text(json.dumps(profiles))
        # 0600: this records which networks the machine has been on.
        temporary.chmod(0o600)
        temporary.replace(self._path)

    def remember(self, connection: Connection) -> None:
        profiles = self.load()
        if connection.uuid not in profiles:
            profiles[connection.uuid] = connection.as_profile()
            self.save(profiles)

    def forget(self, uuid: str) -> None:
        profiles = self.load()
        profiles.pop(uuid, None)
        self.save(profiles)

    def recorded(self, uuid: str) -> dict[str, str] | None:
        return self.load().get(uuid)

    def lock(self):
        """An exclusive lock held for the duration of a change.

        The bar toggle and the control centre switch drive the same code;
        two overlapping runs could record a randomised MAC as the 'original'
        and make the change permanent.
        """
        self._directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        handle = (self._directory / "lock").open("w")
        fcntl.flock(handle, fcntl.LOCK_EX)
        return handle


class MacRandomiser:
    """Applies and reverts MAC randomisation, verifying the result."""

    RECONNECT_TIMEOUT = "30"

    def __init__(self, command: Command, inspector: ConnectionInspector, store: ProfileStore):
        self._command = command
        self._inspector = inspector
        self._store = store

    def apply(self, enable: bool) -> None:
        connection = self._inspector.active()

        if enable:
            # Recorded before any network change, so a failure midway still
            # leaves us able to put the original setting back.
            self._store.remember(connection)
            target = RANDOM
        else:
            recorded = self._store.recorded(connection.uuid)
            if recorded is None:
                raise RiceError("No previous MAC setting was saved for this connection.")
            target = recorded["setting"]

        try:
            self._set_and_verify(connection, target, enable)
        except RiceError as error:
            raise self._rollback(connection, error) from error

        if not enable:
            self._store.forget(connection.uuid)

    def _set_and_verify(self, connection: Connection, target: str, enable: bool) -> None:
        self._write(connection, target)
        current = self._inspector.active()
        if current.uuid != connection.uuid or current.setting != target:
            raise RiceError("The expected connection setting was not applied.")
        if enable and current.mac == connection.mac:
            # NetworkManager accepted the setting but the driver ignored it;
            # reporting success here would be a privacy claim we cannot make.
            raise RiceError("The MAC address did not change.")

    def _write(self, connection: Connection, setting: str) -> None:
        self._command.run("nmcli", "connection", "modify", "uuid", connection.uuid,
                          connection.prop, setting)
        self._command.run("nmcli", "--wait", self.RECONNECT_TIMEOUT, "connection", "up",
                          "uuid", connection.uuid, "ifname", connection.device)

    def _rollback(self, connection: Connection, error: Exception) -> RiceError:
        """Put back the setting that was in force before this attempt."""
        try:
            self._write(connection, connection.setting)
        except RiceError:
            return RiceError(
                f"{error} Reconnect in the Wi-Fi menu; the original setting is saved."
            )
        return RiceError(f"{error} The previous connection setting was restored.")


class PrivacyService:
    """What the control centre actually calls."""

    def __init__(self, command: Command | None = None):
        self._command = command or Command()
        self._inspector = ConnectionInspector(self._command)
        self._store = ProfileStore()
        self._randomiser = MacRandomiser(self._command, self._inspector, self._store)

    def status(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "browser_available": bool(shutil.which("torbrowser-launcher")),
            "device": "", "mac": "", "randomized": False, "restorable": False, "error": "",
        }
        try:
            connection = self._inspector.active()
            recorded = self._store.recorded(connection.uuid)
            result.update(
                device=connection.device,
                mac=connection.mac,
                randomized=connection.setting == RANDOM,
                restorable=recorded is not None,
            )
            if recorded is not None:
                result["previous_mac"] = recorded["mac"]
        except (RiceError, OSError, ValueError) as error:
            # Reported in-band rather than raised: the panel wants to render
            # the rest of its state alongside the problem.
            result["error"] = str(error)
        return result

    def set_randomised(self, enable: bool) -> dict[str, Any]:
        with self._store.lock():
            self._randomiser.apply(enable)
        return self.status()

    def check_ip(self) -> dict[str, Any]:
        result = {"direct_ip": "Unavailable", "tor_ip": "Not connected", "tor_verified": False}
        result["direct_ip"] = self._fetch_ip(("--noproxy", "*")) or "Unavailable"

        reply = self._fetch_json(("--noproxy", "", "--proxy", TOR_SOCKS))
        if reply is not None:
            # Trust Tor only when the endpoint itself confirms it. A reply
            # that merely arrived could have come over a direct connection.
            result["tor_verified"] = reply.get("IsTor") is True
            result["tor_ip"] = reply.get("IP") if result["tor_verified"] else "Tor could not be verified"
        return result

    def _fetch_json(self, extra: tuple[str, ...]) -> dict[str, Any] | None:
        base = ("curl", "-4", "--fail", "--silent", "--show-error",
                "--connect-timeout", "8", "--max-time", "20")
        try:
            return json.loads(self._command.run(*base, *extra, TOR_ENDPOINT, timeout=25))
        except (RiceError, ValueError):
            return None

    def _fetch_ip(self, extra: tuple[str, ...]) -> str | None:
        reply = self._fetch_json(extra)
        return reply.get("IP") if reply else None

    def launch_browser(self) -> dict[str, str]:
        if not shutil.which("torbrowser-launcher"):
            raise RiceError("Install Tor Browser first.")
        Command.detach("torbrowser-launcher")
        return {"message": "Connect inside Tor Browser to start private browsing."}

    def install_browser(self) -> dict[str, Any]:
        self._command.run("pkexec", "/usr/bin/pacman", "-S", "--needed", "--noconfirm",
                          "torbrowser-launcher", timeout=600)
        return self.status()
