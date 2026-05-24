#!/usr/bin/env python3

import subprocess
import sys
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib, Gtk


CSS = """
window {
  background: transparent;
}

dialog {
  background: #080807;
  color: #f8f4ec;
}

entry,
passwordentry {
  background: rgba(248, 244, 236, 0.08);
  border: 1px solid rgba(222, 207, 178, 0.18);
  border-radius: 12px;
  color: #f8f4ec;
  padding: 10px;
}

button {
  background: rgba(248, 244, 236, 0.08);
  border: 1px solid rgba(222, 207, 178, 0.16);
  border-radius: 999px;
  color: #f8f4ec;
  font-weight: 700;
}

button:hover {
  background: rgba(222, 207, 178, 0.15);
}

.dialog-action {
  padding: 8px 14px;
}

.root {
  background: rgba(8, 8, 7, 0.72);
  border: 1px solid rgba(222, 207, 178, 0.22);
  border-radius: 22px;
  color: #f8f4ec;
}

.topbar {
  padding: 18px 20px 10px;
}

.title {
  font-size: 24px;
  font-weight: 800;
}

.subtitle {
  color: #a79c8c;
  font-size: 12px;
}

.tabs {
  background: rgba(222, 207, 178, 0.10);
  border-radius: 16px;
  padding: 4px;
}

.tab {
  background: transparent;
  border: 0;
  border-radius: 13px;
  color: #c4b7a3;
  font-weight: 700;
  padding: 8px 14px;
}

.tab.active {
  background: #e4d1ad;
  color: #0b0a08;
}

.content {
  padding: 0 20px 20px;
}

.hero {
  background: rgba(222, 207, 178, 0.09);
  border: 1px solid rgba(222, 207, 178, 0.18);
  border-radius: 20px;
  padding: 16px;
}

.hero-title {
  font-size: 16px;
  font-weight: 800;
}

.hero-status {
  color: #e4d1ad;
  font-weight: 700;
}

.pill-button {
  background: rgba(248, 244, 236, 0.08);
  border: 1px solid rgba(222, 207, 178, 0.16);
  border-radius: 999px;
  color: #f8f4ec;
  font-weight: 700;
  padding: 8px 12px;
}

.pill-button:hover {
  background: rgba(222, 207, 178, 0.15);
}

.primary {
  background: #e4d1ad;
  color: #0b0a08;
}

.danger {
  background: rgba(248, 244, 236, 0.06);
  color: #f1dfc1;
}

.section-title {
  color: #f1dfc1;
  font-size: 13px;
  font-weight: 800;
  margin-top: 14px;
}

.card {
  background: rgba(248, 244, 236, 0.055);
  border: 1px solid rgba(222, 207, 178, 0.12);
  border-radius: 18px;
  padding: 12px 14px;
}

.card:hover {
  background: rgba(222, 207, 178, 0.11);
}

.name {
  font-size: 14px;
  font-weight: 800;
}

.meta {
  color: #a79c8c;
  font-size: 12px;
}

.empty {
  color: #a79c8c;
  padding: 28px;
}

.toast {
  color: #e4d1ad;
  font-size: 12px;
  font-weight: 700;
}

.close-button {
  min-width: 34px;
  min-height: 34px;
  padding: 0;
  background: rgba(248, 244, 236, 0.06);
  color: #e4d1ad;
}
"""


def cmd(args):
    return subprocess.run(args, text=True, capture_output=True)


def out(args):
    return cmd(args).stdout.strip()


class NetworkCenter(Gtk.Application):
    def __init__(self, initial_page):
        super().__init__(application_id="local.hypr.NetworkCenter")
        self.initial_page = initial_page
        self.page = initial_page
        self.window = None
        self.toast = None
        self.list_box = None
        self.hero_title = None
        self.hero_status = None
        self.wifi_tab = None
        self.bt_tab = None

    def do_activate(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        display = Gdk.Display.get_default()
        if display is None:
            print("Network Center needs a graphical display.", file=sys.stderr)
            self.quit()
            return
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("Network Center")
        self.window.set_default_size(560, 720)
        self.window.set_resizable(False)
        self.window.set_decorated(False)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.add_css_class("root")
        self.window.set_child(root)

        topbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        topbar.add_css_class("topbar")
        root.append(topbar)

        heading = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        heading.set_hexpand(True)
        title = Gtk.Label(label="Network Center", xalign=0)
        title.add_css_class("title")
        subtitle = Gtk.Label(label="Fast connections, no maze.", xalign=0)
        subtitle.add_css_class("subtitle")
        heading.append(title)
        heading.append(subtitle)
        topbar.append(heading)

        tabs = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        tabs.add_css_class("tabs")
        self.wifi_tab = self.tab_button("Wi-Fi", "wifi")
        self.bt_tab = self.tab_button("Bluetooth", "bluetooth")
        tabs.append(self.wifi_tab)
        tabs.append(self.bt_tab)
        topbar.append(tabs)

        close = Gtk.Button(label="x")
        close.add_css_class("close-button")
        close.connect("clicked", lambda *_: self.window.close())
        topbar.append(close)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.add_css_class("content")
        root.append(content)

        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        hero.add_css_class("hero")
        content.append(hero)

        hero_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        hero.append(hero_row)
        self.hero_title = Gtk.Label(xalign=0)
        self.hero_title.add_css_class("hero-title")
        self.hero_title.set_hexpand(True)
        self.hero_status = Gtk.Label(xalign=1)
        self.hero_status.add_css_class("hero-status")
        hero_row.append(self.hero_title)
        hero_row.append(self.hero_status)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hero.append(actions)
        self.action_box = actions

        section = Gtk.Label(label="Available", xalign=0)
        section.add_css_class("section-title")
        content.append(section)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(430)
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        scroll.set_child(self.list_box)
        content.append(scroll)

        self.toast = Gtk.Label(xalign=0)
        self.toast.add_css_class("toast")
        content.append(self.toast)

        self.set_page(self.initial_page)
        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.handle_key)
        self.window.add_controller(key)
        self.window.present()

    def handle_key(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_Escape:
            self.window.close()
            return True
        return False

    def tab_button(self, label, page):
        button = Gtk.Button(label=label)
        button.add_css_class("tab")
        button.connect("clicked", lambda *_: self.set_page(page))
        return button

    def set_page(self, page):
        self.page = page
        for button in (self.wifi_tab, self.bt_tab):
            button.remove_css_class("active")
        if page == "wifi":
            self.wifi_tab.add_css_class("active")
            self.render_wifi()
        else:
            self.bt_tab.add_css_class("active")
            self.render_bluetooth()

    def clear(self, box):
        child = box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt

    def set_toast(self, text):
        self.toast.set_text(text)
        GLib.timeout_add_seconds(4, lambda: self.toast.set_text("") or False)

    def run_async(self, label, args, after=None):
        def worker():
            result = cmd(args)
            def done():
                if result.returncode == 0:
                    self.set_toast(label)
                    if after:
                        after()
                else:
                    self.set_toast(result.stderr.strip() or f"{label} failed")
                return False
            GLib.idle_add(done)
        threading.Thread(target=worker, daemon=True).start()

    def button(self, label, callback, primary=False, danger=False):
        btn = Gtk.Button(label=label)
        btn.add_css_class("pill-button")
        if primary:
            btn.add_css_class("primary")
        if danger:
            btn.add_css_class("danger")
        btn.connect("clicked", callback)
        return btn

    def render_wifi(self):
        self.clear(self.action_box)
        self.clear(self.list_box)
        current = self.current_ssid()
        enabled = out(["nmcli", "radio", "wifi"]) or "unknown"
        self.hero_title.set_text(current if current else "Wi-Fi")
        self.hero_status.set_text("Connected" if current else enabled.title())

        self.action_box.append(self.button("Refresh", lambda *_: self.render_wifi()))
        self.action_box.append(self.button("Disconnect", lambda *_: self.disconnect_wifi(), danger=True))
        self.action_box.append(self.button("Power", lambda *_: self.toggle_wifi()))
        self.action_box.append(self.button("Hidden", lambda *_: self.hidden_wifi()))
        self.action_box.append(self.button("Hotspot", lambda *_: self.hotspot_wifi(), primary=True))

        self.list_box.append(self.empty("Scanning networks..."))
        self.run_async("Networks refreshed", ["nmcli", "device", "wifi", "rescan"], self.populate_wifi)

    def populate_wifi(self):
        self.clear(self.list_box)
        rows = self.wifi_rows()
        if not rows:
            self.list_box.append(self.empty("No Wi-Fi networks found."))
            return
        for row in rows:
            self.list_box.append(self.wifi_card(row))

    def current_ssid(self):
        for line in out(["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"]).splitlines():
            parts = line.split(":", 1)
            if len(parts) == 2 and parts[0] == "yes":
                return parts[1]
        return ""

    def wifi_rows(self):
        rows = []
        seen = set()
        data = out(["nmcli", "-t", "-f", "in-use,ssid,signal,security", "dev", "wifi", "list"])
        for line in data.splitlines():
            parts = line.split(":", 3)
            if len(parts) < 4 or not parts[1] or parts[1] in seen:
                continue
            seen.add(parts[1])
            rows.append({
                "active": parts[0] == "*",
                "ssid": parts[1],
                "signal": parts[2],
                "security": "Open" if parts[3] in ("", "--") else "Secured",
            })
        return rows

    def wifi_card(self, row):
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        card.add_css_class("card")
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        text.set_hexpand(True)
        name = Gtk.Label(label=row["ssid"], xalign=0)
        name.add_css_class("name")
        meta = Gtk.Label(label=f'{row["signal"]}% signal · {row["security"]}', xalign=0)
        meta.add_css_class("meta")
        text.append(name)
        text.append(meta)
        card.append(text)
        label = "Connected" if row["active"] else "Connect"
        card.append(self.button(label, lambda _, ssid=row["ssid"]: self.connect_wifi(ssid), primary=not row["active"]))
        return card

    def connect_wifi(self, ssid):
        if cmd(["nmcli", "connection", "show", ssid]).returncode == 0:
            self.run_async(f"Connected to {ssid}", ["nmcli", "connection", "up", ssid], self.render_wifi)
            return
        if cmd(["nmcli", "device", "wifi", "connect", ssid]).returncode == 0:
            self.set_toast(f"Connected to {ssid}")
            self.render_wifi()
            return
        self.ask_password(f"Password for {ssid}", lambda pw: self.run_async(
            f"Connected to {ssid}", ["nmcli", "device", "wifi", "connect", ssid, "password", pw], self.render_wifi
        ))

    def disconnect_wifi(self):
        device = ""
        for line in out(["nmcli", "-t", "-f", "device,type", "device", "status"]).splitlines():
            parts = line.split(":", 1)
            if len(parts) == 2 and parts[1] == "wifi":
                device = parts[0]
                break
        if device:
            self.run_async("Wi-Fi disconnected", ["nmcli", "device", "disconnect", device], self.render_wifi)

    def toggle_wifi(self):
        state = out(["nmcli", "radio", "wifi"])
        self.run_async("Wi-Fi power changed", ["nmcli", "radio", "wifi", "off" if state == "enabled" else "on"], self.render_wifi)

    def hidden_wifi(self):
        self.ask_text("Hidden network name", lambda ssid: self.ask_password(
            f"Password for {ssid}", lambda pw: self.run_async(
                f"Connected to {ssid}", ["nmcli", "device", "wifi", "connect", ssid, "password", pw, "hidden", "yes"], self.render_wifi
            )
        ))

    def hotspot_wifi(self):
        self.ask_text("Hotspot name", lambda ssid: self.ask_password(
            "Hotspot password", lambda pw: self.run_async(
                "Hotspot started", ["nmcli", "device", "wifi", "hotspot", "ssid", ssid, "password", pw], self.render_wifi
            )
        ), default="Hotspot")

    def render_bluetooth(self):
        self.clear(self.action_box)
        self.clear(self.list_box)
        connected = out(["bluetoothctl", "devices", "Connected"]).replace("Device ", "")
        powered = self.bluetooth_powered()
        self.hero_title.set_text(connected.split(" ", 1)[1] if " " in connected else "Bluetooth")
        self.hero_status.set_text("Connected" if connected else ("On" if powered == "yes" else "Off"))

        self.action_box.append(self.button("Refresh", lambda *_: self.render_bluetooth()))
        self.action_box.append(self.button("Disconnect", lambda *_: self.disconnect_bluetooth(), danger=True))
        self.action_box.append(self.button("Power", lambda *_: self.toggle_bluetooth()))
        self.action_box.append(self.button("Pair by MAC", lambda *_: self.pair_by_mac(), primary=True))

        self.list_box.append(self.empty("Scanning devices..."))
        self.run_async("Devices refreshed", ["bluetoothctl", "power", "on"], self.scan_bluetooth)

    def scan_bluetooth(self):
        def worker():
            subprocess.Popen(["bluetoothctl", "scan", "on"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            GLib.timeout_add_seconds(4, self.stop_scan_and_populate)
        threading.Thread(target=worker, daemon=True).start()

    def stop_scan_and_populate(self):
        cmd(["bluetoothctl", "scan", "off"])
        self.populate_bluetooth()
        return False

    def bluetooth_powered(self):
        for line in out(["bluetoothctl", "show"]).splitlines():
            if "Powered:" in line:
                return line.split(":", 1)[1].strip()
        return "unknown"

    def populate_bluetooth(self):
        self.clear(self.list_box)
        rows = self.bluetooth_rows()
        if not rows:
            self.list_box.append(self.empty("No Bluetooth devices found."))
            return
        for row in rows:
            self.list_box.append(self.bluetooth_card(row))

    def bluetooth_rows(self):
        rows = []
        seen = set()
        for line in out(["bluetoothctl", "devices"]).splitlines():
            parts = line.replace("Device ", "", 1).split(" ", 1)
            if len(parts) < 2 or parts[0] in seen:
                continue
            seen.add(parts[0])
            rows.append({"mac": parts[0], "name": parts[1], "state": self.bt_state(parts[0])})
        return rows

    def bt_state(self, mac):
        info = out(["bluetoothctl", "info", mac])
        connected = "Connected: yes" in info
        paired = "Paired: yes" in info
        trusted = "Trusted: yes" in info
        if connected:
            return "Connected"
        if paired and trusted:
            return "Paired · Trusted"
        if paired:
            return "Paired"
        return "New"

    def bluetooth_card(self, row):
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        card.add_css_class("card")
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        text.set_hexpand(True)
        name = Gtk.Label(label=row["name"], xalign=0)
        name.add_css_class("name")
        meta = Gtk.Label(label=f'{row["state"]} · {row["mac"]}', xalign=0)
        meta.add_css_class("meta")
        text.append(name)
        text.append(meta)
        card.append(text)
        if row["state"] == "Connected":
            card.append(self.button("Disconnect", lambda _, mac=row["mac"]: self.bt_disconnect(mac), danger=True))
        else:
            card.append(self.button("Connect", lambda _, mac=row["mac"]: self.bt_connect(mac), primary=True))
        card.append(self.button("Forget", lambda _, mac=row["mac"]: self.bt_forget(mac), danger=True))
        return card

    def bt_connect(self, mac):
        self.run_async("Device connected", ["bluetoothctl", "connect", mac], self.render_bluetooth)

    def bt_disconnect(self, mac):
        self.run_async("Device disconnected", ["bluetoothctl", "disconnect", mac], self.render_bluetooth)

    def bt_forget(self, mac):
        self.run_async("Device forgotten", ["bluetoothctl", "remove", mac], self.render_bluetooth)

    def disconnect_bluetooth(self):
        rows = self.bluetooth_rows()
        for row in rows:
            if row["state"] == "Connected":
                self.bt_disconnect(row["mac"])
                return
        self.set_toast("No connected Bluetooth device")

    def toggle_bluetooth(self):
        action = "off" if self.bluetooth_powered() == "yes" else "on"
        self.run_async("Bluetooth power changed", ["bluetoothctl", "power", action], self.render_bluetooth)

    def pair_by_mac(self):
        self.ask_text("Device MAC address", lambda mac: self.run_async(
            "Device paired", ["bluetoothctl", "pair", mac], lambda: self.run_async(
                "Device trusted", ["bluetoothctl", "trust", mac], lambda: self.run_async(
                    "Device connected", ["bluetoothctl", "connect", mac], self.render_bluetooth
                )
            )
        ))

    def empty(self, text):
        label = Gtk.Label(label=text)
        label.add_css_class("empty")
        return label

    def ask_text(self, title, callback, default=""):
        dialog = Gtk.Dialog(title=title, transient_for=self.window, modal=True)
        cancel = dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        done = dialog.add_button("Done", Gtk.ResponseType.OK)
        cancel.add_css_class("dialog-action")
        done.add_css_class("dialog-action")
        done.add_css_class("primary")
        entry = Gtk.Entry(text=default)
        entry.set_activates_default(True)
        entry.set_margin_top(16)
        entry.set_margin_bottom(16)
        entry.set_margin_start(16)
        entry.set_margin_end(16)
        dialog.get_content_area().append(entry)
        dialog.set_default_response(Gtk.ResponseType.OK)
        dialog.connect("response", lambda d, r: self.handle_entry_response(d, r, entry, callback))
        dialog.present()

    def ask_password(self, title, callback):
        dialog = Gtk.Dialog(title=title, transient_for=self.window, modal=True)
        cancel = dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        connect = dialog.add_button("Connect", Gtk.ResponseType.OK)
        cancel.add_css_class("dialog-action")
        connect.add_css_class("dialog-action")
        connect.add_css_class("primary")
        entry = Gtk.PasswordEntry()
        entry.set_activates_default(True)
        entry.set_margin_top(16)
        entry.set_margin_bottom(16)
        entry.set_margin_start(16)
        entry.set_margin_end(16)
        dialog.get_content_area().append(entry)
        dialog.set_default_response(Gtk.ResponseType.OK)
        dialog.connect("response", lambda d, r: self.handle_entry_response(d, r, entry, callback))
        dialog.present()

    def handle_entry_response(self, dialog, response, entry, callback):
        value = entry.get_text()
        dialog.destroy()
        if response == Gtk.ResponseType.OK and value:
            callback(value)


page = "bluetooth" if len(sys.argv) > 1 and sys.argv[1] == "bluetooth" else "wifi"
NetworkCenter(page).run([sys.argv[0]])
