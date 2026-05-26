#!/usr/bin/env python3

import subprocess
import sys
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GLib, Gtk


CSS = """
window { background: transparent; }

dialog {
  background: rgba(0, 0, 0, 0.92);
  color: #ffffff;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.12);
}

entry,
passwordentry {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 4px;
  color: #ffffff;
  padding: 8px;
  caret-color: #ffffff;
}

entry:focus,
passwordentry:focus {
  border-color: rgba(255, 255, 255, 0.45);
}

button {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 4px;
  color: #ffffff;
  font-weight: 500;
  box-shadow: none;
}

button:hover {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.30);
}

.dialog-action {
  padding: 6px 12px;
}

.root {
  background: rgba(0, 0, 0, 0.82);
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 10px;
  color: #ffffff;
  font-family: "Iosevka Term", monospace;
}

.topbar {
  padding: 14px 16px 10px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.title {
  font-size: 14px;
  font-weight: 700;
  color: #ffffff;
  letter-spacing: 0.5px;
}

.subtitle {
  color: rgba(255, 255, 255, 0.40);
  font-size: 10px;
}

.tabs {
  background: transparent;
  padding: 8px 16px 0;
  border: none;
}

.tab {
  background: transparent;
  border: none;
  border-bottom: 1px solid transparent;
  border-radius: 0;
  color: rgba(255, 255, 255, 0.40);
  font-weight: 600;
  padding: 6px 10px;
  font-size: 10px;
  letter-spacing: 0.5px;
  box-shadow: none;
}

.tab:hover {
  color: rgba(255, 255, 255, 0.75);
  background: transparent;
}

.tab.active {
  color: #ffffff;
  border-bottom: 1px solid #ffffff;
}

.content {
  padding: 10px 16px 14px;
}

.hero {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 6px;
  padding: 12px;
}

.hero-title {
  font-size: 12px;
  font-weight: 700;
  color: #ffffff;
  letter-spacing: 0.3px;
}

.hero-status {
  color: rgba(255, 255, 255, 0.55);
  font-weight: 500;
  font-size: 10px;
}

.pill-button {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 4px;
  color: rgba(255, 255, 255, 0.85);
  font-weight: 500;
  padding: 4px 8px;
  font-size: 10px;
  box-shadow: none;
}

.pill-button:hover {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.30);
  color: #ffffff;
}

.primary {
  background: #ffffff;
  color: #000000;
  border-color: #ffffff;
}

.primary:hover {
  background: rgba(255, 255, 255, 0.85);
  color: #000000;
}

.danger {
  background: transparent;
  color: rgba(255, 255, 255, 0.75);
  border-color: rgba(255, 255, 255, 0.20);
}

.danger:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #ffffff;
}

.section-title {
  color: rgba(255, 255, 255, 0.35);
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 1px;
  margin-top: 10px;
  margin-bottom: 2px;
}

.card {
  background: transparent;
  border: none;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 0;
  padding: 10px 4px;
}

.card:hover {
  background: rgba(255, 255, 255, 0.03);
}

.name {
  font-size: 12px;
  font-weight: 600;
  color: #ffffff;
}

.meta {
  color: rgba(255, 255, 255, 0.40);
  font-size: 9px;
  letter-spacing: 0.3px;
}

.empty {
  color: rgba(255, 255, 255, 0.40);
  padding: 24px;
  font-size: 11px;
}

.toast {
  color: rgba(255, 255, 255, 0.65);
  font-size: 10px;
  font-weight: 500;
  padding: 4px 0 0;
}

.close-button {
  min-width: 24px;
  min-height: 24px;
  padding: 0 6px;
  background: transparent;
  border-radius: 4px;
  color: rgba(255, 255, 255, 0.55);
  border: none;
  font-size: 12px;
  font-weight: 600;
  box-shadow: none;
}

.close-button:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #ffffff;
}
"""


def cmd(args):
    return subprocess.run(args, text=True, capture_output=True)


def out(args):
    return cmd(args).stdout.strip()


def refresh_waybar(page):
    signal = "8" if page == "wifi" else "9"
    subprocess.run(["pkill", f"-RTMIN+{signal}", "waybar"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


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
        self.window.set_default_size(420, 560)
        self.window.set_resizable(False)
        self.window.set_decorated(False)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.add_css_class("root")
        self.window.set_child(root)

        topbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        topbar.add_css_class("topbar")
        root.append(topbar)

        heading = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        heading.set_hexpand(True)
        title = Gtk.Label(label="NETWORK", xalign=0)
        title.add_css_class("title")
        subtitle = Gtk.Label(label="connections", xalign=0)
        subtitle.add_css_class("subtitle")
        heading.append(title)
        heading.append(subtitle)
        topbar.append(heading)

        close = Gtk.Button(label="x")
        close.add_css_class("close-button")
        close.connect("clicked", lambda *_: self.window.close())
        topbar.append(close)

        tabs = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        tabs.add_css_class("tabs")
        self.wifi_tab = self.tab_button("WI-FI", "wifi")
        self.bt_tab = self.tab_button("BLUETOOTH", "bluetooth")
        tabs.append(self.wifi_tab)
        tabs.append(self.bt_tab)
        root.append(tabs)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        content.add_css_class("content")
        root.append(content)

        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        hero.add_css_class("hero")
        content.append(hero)

        hero_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        hero.append(hero_row)
        self.hero_title = Gtk.Label(xalign=0)
        self.hero_title.add_css_class("hero-title")
        self.hero_title.set_hexpand(True)
        self.hero_status = Gtk.Label(xalign=1)
        self.hero_status.add_css_class("hero-status")
        hero_row.append(self.hero_title)
        hero_row.append(self.hero_status)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        hero.append(actions)
        self.action_box = actions

        section = Gtk.Label(label="AVAILABLE", xalign=0)
        section.add_css_class("section-title")
        content.append(section)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(340)
        scroll.set_vexpand(True)
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
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
                    refresh_waybar(self.page)
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
        self.hero_title.set_text(current if current else "wi-fi")
        self.hero_status.set_text("connected" if current else enabled.lower())

        self.action_box.append(self.button("refresh", lambda *_: self.render_wifi()))
        self.action_box.append(self.button("disconnect", lambda *_: self.disconnect_wifi(), danger=True))
        self.action_box.append(self.button("power", lambda *_: self.toggle_wifi()))
        self.action_box.append(self.button("hidden", lambda *_: self.hidden_wifi()))
        self.action_box.append(self.button("hotspot", lambda *_: self.hotspot_wifi(), primary=True))

        self.list_box.append(self.empty("scanning..."))
        self.run_async("networks refreshed", ["nmcli", "device", "wifi", "rescan"], self.populate_wifi)

    def populate_wifi(self):
        self.clear(self.list_box)
        rows = self.wifi_rows()
        if not rows:
            self.list_box.append(self.empty("no networks found"))
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
                "security": "open" if parts[3] in ("", "--") else "secured",
            })
        return rows

    def wifi_card(self, row):
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        card.add_css_class("card")
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_hexpand(True)
        name = Gtk.Label(label=row["ssid"], xalign=0)
        name.add_css_class("name")
        meta = Gtk.Label(label=f'{row["signal"]}% / {row["security"]}', xalign=0)
        meta.add_css_class("meta")
        text.append(name)
        text.append(meta)
        card.append(text)
        label = "connected" if row["active"] else "connect"
        card.append(self.button(label, lambda _, r=row: self.connect_wifi(r["ssid"], r["security"]), primary=not row["active"]))
        return card

    def connect_wifi(self, ssid, security):
        if cmd(["nmcli", "connection", "show", ssid]).returncode == 0:
            self.run_async(f"connected to {ssid}", ["nmcli", "connection", "up", ssid], self.render_wifi)
            return
        if security == "secured":
            self.ask_password(f"password for {ssid}", lambda pw: self.run_async(
                f"connected to {ssid}", ["nmcli", "device", "wifi", "connect", ssid, "password", pw], self.render_wifi
            ))
        else:
            self.run_async(f"connected to {ssid}", ["nmcli", "device", "wifi", "connect", ssid], self.render_wifi)

    def disconnect_wifi(self):
        device = ""
        for line in out(["nmcli", "-t", "-f", "device,type", "device", "status"]).splitlines():
            parts = line.split(":", 1)
            if len(parts) == 2 and parts[1] == "wifi":
                device = parts[0]
                break
        if device:
            self.run_async("wi-fi disconnected", ["nmcli", "device", "disconnect", device], self.render_wifi)

    def toggle_wifi(self):
        state = out(["nmcli", "radio", "wifi"])
        self.run_async("wi-fi power changed", ["nmcli", "radio", "wifi", "off" if state == "enabled" else "on"], self.render_wifi)

    def hidden_wifi(self):
        self.ask_text("hidden network name", lambda ssid: self.ask_password(
            f"password for {ssid}", lambda pw: self.run_async(
                f"connected to {ssid}", ["nmcli", "device", "wifi", "connect", ssid, "password", pw, "hidden", "yes"], self.render_wifi
            )
        ))

    def hotspot_wifi(self):
        self.ask_text("hotspot name", lambda ssid: self.ask_password(
            "hotspot password", lambda pw: self.run_async(
                "hotspot started", ["nmcli", "device", "wifi", "hotspot", "ssid", ssid, "password", pw], self.render_wifi
            )
        ), default="Hotspot")

    def render_bluetooth(self):
        self.clear(self.action_box)
        self.clear(self.list_box)
        connected = out(["bluetoothctl", "devices", "Connected"]).replace("Device ", "")
        powered = self.bluetooth_powered()
        self.hero_title.set_text(connected.split(" ", 1)[1] if " " in connected else "bluetooth")
        self.hero_status.set_text("connected" if connected else ("on" if powered == "yes" else "off"))

        self.action_box.append(self.button("refresh", lambda *_: self.render_bluetooth()))
        self.action_box.append(self.button("disconnect", lambda *_: self.disconnect_bluetooth(), danger=True))
        self.action_box.append(self.button("power", lambda *_: self.toggle_bluetooth()))
        self.action_box.append(self.button("pair", lambda *_: self.pair_by_mac(), primary=True))

        self.list_box.append(self.empty("scanning..."))
        self.run_async("devices refreshed", ["bluetoothctl", "power", "on"], self.scan_bluetooth)

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
            self.list_box.append(self.empty("no devices found"))
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
            return "connected"
        if paired and trusted:
            return "paired / trusted"
        if paired:
            return "paired"
        return "new"

    def bluetooth_card(self, row):
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        card.add_css_class("card")
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_hexpand(True)
        name = Gtk.Label(label=row["name"], xalign=0)
        name.add_css_class("name")
        meta = Gtk.Label(label=f'{row["state"]} / {row["mac"]}', xalign=0)
        meta.add_css_class("meta")
        text.append(name)
        text.append(meta)
        card.append(text)
        if row["state"] == "connected":
            card.append(self.button("disconnect", lambda _, mac=row["mac"]: self.bt_disconnect(mac), danger=True))
        else:
            card.append(self.button("connect", lambda _, mac=row["mac"]: self.bt_connect(mac), primary=True))
        card.append(self.button("forget", lambda _, mac=row["mac"]: self.bt_forget(mac), danger=True))
        return card

    def bt_connect(self, mac):
        self.run_async("device connected", ["bluetoothctl", "connect", mac], self.render_bluetooth)

    def bt_disconnect(self, mac):
        self.run_async("device disconnected", ["bluetoothctl", "disconnect", mac], self.render_bluetooth)

    def bt_forget(self, mac):
        self.run_async("device forgotten", ["bluetoothctl", "remove", mac], self.render_bluetooth)

    def disconnect_bluetooth(self):
        rows = self.bluetooth_rows()
        for row in rows:
            if row["state"] == "connected":
                self.bt_disconnect(row["mac"])
                return
        self.set_toast("no connected device")

    def toggle_bluetooth(self):
        action = "off" if self.bluetooth_powered() == "yes" else "on"
        self.run_async("bluetooth power changed", ["bluetoothctl", "power", action], self.render_bluetooth)

    def pair_by_mac(self):
        self.ask_text("device mac address", lambda mac: self.run_async(
            "device paired", ["bluetoothctl", "pair", mac], lambda: self.run_async(
                "device trusted", ["bluetoothctl", "trust", mac], lambda: self.run_async(
                    "device connected", ["bluetoothctl", "connect", mac], self.render_bluetooth
                )
            )
        ))

    def empty(self, text):
        label = Gtk.Label(label=text)
        label.add_css_class("empty")
        return label

    def ask_text(self, title, callback, default=""):
        dialog = Gtk.Dialog(title=title, transient_for=self.window, modal=True)
        cancel = dialog.add_button("cancel", Gtk.ResponseType.CANCEL)
        done = dialog.add_button("done", Gtk.ResponseType.OK)
        cancel.add_css_class("dialog-action")
        done.add_css_class("dialog-action")
        done.add_css_class("primary")
        entry = Gtk.Entry(text=default)
        entry.set_activates_default(True)
        entry.set_margin_top(14)
        entry.set_margin_bottom(14)
        entry.set_margin_start(14)
        entry.set_margin_end(14)
        dialog.get_content_area().append(entry)
        dialog.set_default_response(Gtk.ResponseType.OK)
        dialog.connect("response", lambda d, r: self.handle_entry_response(d, r, entry, callback))
        dialog.present()

    def ask_password(self, title, callback):
        dialog = Gtk.Dialog(title=title, transient_for=self.window, modal=True)
        cancel = dialog.add_button("cancel", Gtk.ResponseType.CANCEL)
        connect = dialog.add_button("connect", Gtk.ResponseType.OK)
        cancel.add_css_class("dialog-action")
        connect.add_css_class("dialog-action")
        connect.add_css_class("primary")
        entry = Gtk.PasswordEntry()
        entry.set_activates_default(True)
        entry.set_margin_top(14)
        entry.set_margin_bottom(14)
        entry.set_margin_start(14)
        entry.set_margin_end(14)
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
