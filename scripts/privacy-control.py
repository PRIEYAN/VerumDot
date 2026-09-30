#!/usr/bin/env python3
"""NetworkManager MAC controls and explicitly scoped Tor Browser checks."""

import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "hypr/privacy"


def run(*args, timeout=40):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                            env={**os.environ, "LC_ALL": "C"})
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Command failed")
    return result.stdout.strip()


def load():
    try:
        return json.loads((STATE / "profiles.json").read_text())
    except FileNotFoundError:
        return {}


def save(profiles):
    target = STATE / "profiles.tmp"
    target.write_text(json.dumps(profiles))
    target.chmod(0o600)
    target.replace(STATE / "profiles.json")


def connection():
    routes = json.loads(run("ip", "-j", "route", "show", "default"))
    preferred = {r.get("dev") for r in routes}
    devices = []
    for row in run("nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "device").splitlines():
        device, kind, state = row.split(":", 2)
        if kind in ("wifi", "ethernet") and state == "connected":
            devices.append((device, kind))
    devices.sort(key=lambda item: item[0] not in preferred)
    if not devices:
        raise RuntimeError("Connect to Wi-Fi or Ethernet first.")
    device, kind = devices[0]
    uuid = run("nmcli", "-g", "GENERAL.CON-UUID", "device", "show", device)
    prop = "802-11-wireless.cloned-mac-address" if kind == "wifi" else "802-3-ethernet.cloned-mac-address"
    setting = run("nmcli", "--escape", "no", "-g", prop, "connection", "show", "uuid", uuid)
    mac = (Path("/sys/class/net") / device / "address").read_text().strip()
    return dict(device=device, uuid=uuid, prop=prop, setting=setting, mac=mac)


def status():
    result = dict(browser_available=bool(shutil.which("torbrowser-launcher")),
                  device="", mac="", randomized=False, restorable=False, error="")
    try:
        conn = connection()
        profiles = load()
        result.update(device=conn["device"], mac=conn["mac"],
                      randomized=conn["setting"] == "random",
                      restorable=conn["uuid"] in profiles)
        if result["restorable"]:
            result["previous_mac"] = profiles[conn["uuid"]]["mac"]
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        result["error"] = str(error)
    return result


def change_mac(enable):
    conn = connection()
    profiles = load()
    uuid = conn["uuid"]
    if enable:
        if uuid not in profiles:
            profiles[uuid] = conn
            save(profiles)  # Record the original before any network change.
        setting = "random"
    else:
        if uuid not in profiles:
            raise RuntimeError("No previous MAC setting was saved for this connection.")
        setting = profiles[uuid]["setting"]
    try:
        run("nmcli", "connection", "modify", "uuid", uuid, conn["prop"], setting)
        run("nmcli", "--wait", "30", "connection", "up", "uuid", uuid, "ifname", conn["device"])
        current = connection()
        if current["uuid"] != uuid or current["setting"] != setting:
            raise RuntimeError("The expected connection setting was not applied.")
        if enable and current["mac"] == conn["mac"]:
            raise RuntimeError("The MAC address did not change.")
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        # Restore the setting in force before this attempt, then reconnect.
        try:
            run("nmcli", "connection", "modify", "uuid", uuid, conn["prop"], conn["setting"])
            run("nmcli", "--wait", "30", "connection", "up", "uuid", uuid, "ifname", conn["device"])
        except (RuntimeError, subprocess.TimeoutExpired):
            raise RuntimeError(f"{error} Reconnect in the Wi-Fi menu; the original setting is saved.")
        raise RuntimeError(f"{error} The previous connection setting was restored.")
    if not enable:
        del profiles[uuid]
        save(profiles)
    return status()


def check_ip():
    result = {"direct_ip": "Unavailable", "tor_ip": "Not connected", "tor_verified": False}
    endpoint = "https://check.torproject.org/api/ip"
    base = ["curl", "-4", "--fail", "--silent", "--show-error", "--connect-timeout", "8", "--max-time", "20"]
    try:
        reply = json.loads(run(*base, "--noproxy", "*", endpoint, timeout=25))
        result["direct_ip"] = reply["IP"]
    except (RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired):
        pass
    # Tor Browser's SOCKS listener. Do not fall back to a direct connection.
    try:
        reply = json.loads(run(*base, "--noproxy", "", "--proxy", "socks5h://127.0.0.1:9150",
                               endpoint, timeout=25))
        result["tor_verified"] = reply.get("IsTor") is True
        result["tor_ip"] = reply["IP"] if result["tor_verified"] else "Tor could not be verified"
    except (RuntimeError, ValueError, KeyError, subprocess.TimeoutExpired):
        pass
    return result


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "status":
        return status()
    if action == "check":
        return check_ip()
    if action == "browser":
        if not shutil.which("torbrowser-launcher"):
            raise RuntimeError("Install Tor Browser first.")
        subprocess.Popen(["torbrowser-launcher"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"message": "Connect inside Tor Browser to start private browsing."}
    if action == "install":
        run("pkexec", "/usr/bin/pacman", "-S", "--needed", "--noconfirm", "torbrowser-launcher", timeout=600)
        return status()
    if action not in ("mac-on", "mac-off"):
        raise RuntimeError("Usage: privacy-control.py status|mac-on|mac-off|browser|install|check")
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return change_mac(action == "mac-on")


if __name__ == "__main__":
    try:
        print(json.dumps(main()))
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
