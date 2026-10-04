//@ pragma UseQApplication

// Control centre — slides in from the right edge when the pointer hits the
// top-right corner of the screen (the far end of waybar).
//
// The Wi-Fi and Bluetooth tiles are split: clicking the round icon toggles the
// radio, clicking the rest of the tile opens a detail page inside the panel
// listing networks / devices.
//
// Everything is driven by quickshell's native services rather than by shelling
// out: Pipewire for volume and mic, UPower for the power profile, Networking
// for Wi-Fi, Bluetooth for the adapter, and the Wayland idle inhibitor for
// stay-awake. Brightness is the one exception — no native service — so it goes
// through brightnessctl.
//
// Run: qs -p ~/.config/hypr/apps/quickshell/controlcenter

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

ShellRoot {
    id: root

    // ---- geometry ----
    // waybar island: 4px top margin + 40px tall, so its underside is at 44.
    readonly property int barHeight: 44
    readonly property int panelWidth: 380
    readonly property int edgeGap: 8
    // waybar island side margin, from apps/waybar/config.jsonc ("4 6 0 6").
    readonly property int islandInset: 6
    readonly property int pad: 16
    readonly property int tileHeight: 64
    readonly property int tileGap: 10
    readonly property int cardRadius: 22
    readonly property int tileRadius: 14
    readonly property int listRowHeight: 44
    readonly property int listMaxHeight: 264   // 6 rows before it scrolls
    // The waybar island is inset from the screen edges now, so the very corner
    // is free space — the hot corner no longer overlaps any bar module and can
    // afford to be a slightly easier target.
    readonly property int hotSize: 12

    // ---- macOS Sonoma glass material ----
    // The panel sits at 60% so white text stays legible over a bright
    // wallpaper; the frost itself comes from the 4-pass blur in hypr.conf.
    // Cards layered on it use the 12% white "raised" material.
    readonly property color glass: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.60)
    readonly property color edge: Qt.rgba(1, 1, 1, 0.18)
    readonly property color tileOff: Qt.rgba(1, 1, 1, 0.12)
    readonly property color trackOff: Qt.rgba(1, 1, 1, 0.18)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
    readonly property color pressed: Qt.rgba(1, 1, 1, 0.15)
    readonly property color fg: Qt.rgba(1, 1, 1, 0.95)
    readonly property color muted: Qt.rgba(1, 1, 1, 0.70)
    readonly property color faint: Qt.rgba(1, 1, 1, 0.45)
    // Selection and "on" states are a solid white fill, so anything drawn on
    // top of one has to invert to black to stay legible. (Named accentFg, not
    // onAccent — QML reads a property starting with "on" as a signal handler.)
    readonly property color accent: "#ffffff"
    readonly property color accentFg: "#000000"
    readonly property color accentFgMuted: Qt.rgba(0, 0, 0, 0.60)
    // Hover on a white fill has to go darker — Qt.lighter("#ffffff") is a no-op.
    readonly property color accentHover: Qt.rgba(0.87, 0.87, 0.87, 1)
    readonly property color danger: "#FF6961"
    // Falls back to Noto Sans until inter-font is installed.
    readonly property string uiFont: "Inter"
    readonly property string iconFont: "IosevkaTerm Nerd Font"

    property bool shown: false
    PersistentProperties {
        id: sessionState
        reloadableId: "controlcenter-session"
        property bool stayAwake: false
    }
    property alias stayAwake: sessionState.stayAwake
    property string page: "main"               // main | wifi | bluetooth | privacy
    property bool powerExpanded: false
    property bool audioExpanded: false
    property bool brightnessExpanded: false
    property bool fanExpanded: false
    // auto | normal | max — see scripts/fan-control.sh for what each resolves to.
    property string fanMode: "auto"

    // .../hypr — this config lives at hypr/apps/quickshell/controlcenter.
    readonly property string riceDir: Quickshell.shellPath("../../..")

    // ---- audio ----
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // Pipewire nodes only publish live data — and only accept being made the
    // default — while something binds them, so the whole device list is
    // tracked, not just the two currently in use.
    PwObjectTracker {
        objects: [root.sink, root.source]
            .concat(root.audioSinks)
            .concat(root.audioSources)
    }

    // PwNodeType flags: Audio=1, Stream=4, Source=8, Sink=16, so a real
    // output device is 17 and a real input is 9. Application streams carry
    // the Stream bit and are filtered out.
    function audioDevices(wantType) {
        const out = [];
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; i++) {
            const n = nodes[i];
            if ((n.type & 4) !== 0) continue;
            if (n.type !== wantType) continue;
            out.push(n);
        }
        out.sort((a, b) => (a.nickname || a.description || "")
            .localeCompare(b.nickname || b.description || ""));
        return out;
    }

    readonly property var audioSinks: audioDevices(17)
    readonly property var audioSources: audioDevices(9)

    function deviceLabel(n) {
        return n.nickname || n.description || n.name || "Unknown device";
    }

    // Switching goes through wpctl rather than Pipewire.preferredDefault*:
    // wpctl is WirePlumber's own tool and writes the same default-node
    // metadata the rest of the session reads.
    //
    // Note WirePlumber will refuse (and silently revert) a device that is not
    // actually usable — an HDMI output with nothing plugged into it, say — so
    // a row that bounces back is the system saying no, not a failed click.
    Process { id: audioSwitch }

    function setDefaultNode(node) {
        if (!node) return;
        audioSwitch.running = false;
        audioSwitch.command = ["wpctl", "set-default", String(node.id)];
        audioSwitch.running = true;
    }

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool sinkMuted: sink?.audio?.muted ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false

    // ---- brightness (no native service; brightnessctl instead) ----
    property int brightness: 0

    Process {
        id: brightnessRead
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                // device,class,current,percent,max
                const parts = text.trim().split(",");
                if (parts.length >= 4) {
                    const pct = parseInt(parts[3].replace("%", ""), 10);
                    if (!isNaN(pct)) root.brightness = pct;
                }
            }
        }
    }

    Process { id: brightnessWrite }

    function setBrightness(pct) {
        // Floored at 5 so the slider can never black the panel out entirely.
        const v = Math.max(5, Math.min(100, Math.round(pct)));
        root.brightness = v;
        brightnessWrite.command = ["brightnessctl", "set", v + "%"];
        brightnessWrite.running = true;
        pokeWaybar(1);
    }

    // ---- eye comfort ----
    property bool eyeComfortEnabled: false
    property bool eyeComfortAvailable: false
    property int eyeComfortIntensity: 70
    property bool eyeComfortPending: false
    property string eyeComfortError: ""
    readonly property string eyeComfortScript: riceDir + "/apps/waybar/scripts/eye-comfort-toggle.sh"

    Process {
        id: eyeComfortRead
        command: [root.eyeComfortScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.eyeComfortPending || eyeComfortWrite.running) return;
                try {
                    const state = JSON.parse(text);
                    root.eyeComfortEnabled = state.enabled;
                    root.eyeComfortIntensity = state.intensity;
                    root.eyeComfortAvailable = state.available;
                } catch (e) {
                    root.eyeComfortError = "Could not read Eye Comfort status.";
                }
            }
        }
    }

    Process {
        id: eyeComfortWrite
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.eyeComfortError = "Could not apply Eye Comfort. Try again.";
            if (root.eyeComfortPending) eyeComfortDelay.restart();
            else eyeComfortRead.running = true;
        }
    }

    // Coalesce dragging and serialize writes, preserving the final value.
    Timer {
        id: eyeComfortDelay
        interval: 180
        onTriggered: {
            if (eyeComfortWrite.running) return;
            root.eyeComfortPending = false;
            eyeComfortWrite.command = [root.eyeComfortScript, "apply",
                root.eyeComfortEnabled ? "on" : "off", String(root.eyeComfortIntensity)];
            eyeComfortWrite.running = true;
        }
    }

    function setEyeComfort(enabled, intensity) {
        if (!eyeComfortAvailable) return;
        eyeComfortEnabled = enabled;
        eyeComfortIntensity = Math.max(0, Math.min(100, Math.round(intensity)));
        eyeComfortError = "";
        eyeComfortPending = true;
        eyeComfortDelay.restart();
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.shown && root.brightnessExpanded
        onTriggered: {
            if (!root.eyeComfortPending && !eyeComfortWrite.running)
                eyeComfortRead.running = true;
        }
    }

    // ---- privacy ----
    property var privacyState: ({})
    property var privacyCheck: ({})
    property string privacyError: ""
    property string privacyMessage: ""
    readonly property string privacyScript: riceDir + "/scripts/privacy-control.py"

    Process {
        id: privacyRead
        command: ["python3", root.privacyScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.privacyState = JSON.parse(text); }
                catch (e) { root.privacyError = "Could not read privacy status."; }
            }
        }
    }

    Process {
        id: privacyWrite
        property string action: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.error) root.privacyError = result.error;
                    else if (privacyWrite.action === "check") root.privacyCheck = result;
                    else if (result.message) root.privacyMessage = result.message;
                    else root.privacyState = result;
                } catch (e) { root.privacyError = "The privacy action did not finish."; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.privacyError)
                root.privacyError = "The privacy action failed or was cancelled.";
            privacyRead.running = true;
        }
    }

    function privacyAction(action) {
        if (privacyWrite.running) return;
        privacyError = "";
        privacyMessage = "";
        if (action !== "check") privacyCheck = ({});
        privacyWrite.action = action;
        privacyWrite.command = ["python3", privacyScript, action];
        privacyWrite.running = true;
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.shown && root.page === "privacy" && !privacyWrite.running
        onTriggered: privacyRead.running = true
    }

    // ---- network ----
    readonly property var wifiDevice: {
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].type === DeviceType.Wifi) return devices[i];
        }
        return null;
    }

    // Connected first, then saved networks, then by signal. De-duplicated by
    // SSID so a network with several access points shows up once.
    readonly property var wifiNetworks: {
        const out = [];
        const seen = {};
        const devices = Networking.devices.values;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (d.type !== DeviceType.Wifi || !d.networks) continue;
            const nets = d.networks.values;
            for (let j = 0; j < nets.length; j++) {
                const n = nets[j];
                if (!n.name || seen[n.name]) continue;
                seen[n.name] = true;
                out.push(n);
            }
        }
        out.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.known !== b.known) return a.known ? -1 : 1;
            return (b.signalStrength || 0) - (a.signalStrength || 0);
        });
        return out;
    }

    readonly property string wifiName: {
        if (!Networking.wifiEnabled) return "Off";
        const nets = wifiNetworks;
        for (let i = 0; i < nets.length; i++) {
            if (nets[i].connected) return nets[i].name;
        }
        return "Not connected";
    }

    // Set while a secured network is waiting for its password.
    property var pendingNetwork: null
    property string psk: ""
    property bool pskVisible: false
    property string wifiError: ""

    // `scannerEnabled` stays on for as long as the page is open, so it cannot
    // double as a "scanning now" indicator. These pulse for a few seconds after
    // a scan is actually kicked off.
    property bool wifiScanning: false
    property bool btScanning: false

    Timer { id: wifiScanPulse; interval: 6000; onTriggered: root.wifiScanning = false }
    Timer { id: btScanPulse; interval: 8000; onTriggered: root.btScanning = false }

    function rescanWifi() {
        const d = wifiDevice;
        if (!d || !Networking.wifiEnabled) return;
        // Bouncing the scanner is what forces NetworkManager to go look again.
        d.scannerEnabled = false;
        d.scannerEnabled = true;
        wifiScanning = true;
        wifiScanPulse.restart();
    }

    function rescanBt() {
        const a = btAdapter;
        if (!a || !a.enabled) return;
        a.discovering = false;
        a.discovering = true;
        btScanning = true;
        btScanPulse.restart();
    }

    // signalStrength is a 0–1 fraction, not a percentage.
    function wifiGlyph(strength) {
        if (strength >= 0.75) return "󰤨";
        if (strength >= 0.50) return "󰤥";
        if (strength >= 0.25) return "󰤢";
        return "󰤟";
    }

    function isOpenNetwork(net) {
        return net.security === WifiSecurityType.Open
            || net.security === WifiSecurityType.Owe;
    }

    function activateNetwork(net) {
        root.wifiError = "";
        if (net.connected) { net.disconnect(); return; }
        if (net.known || isOpenNetwork(net)) { net.connect(); return; }
        askForPsk(net);
    }

    function askForPsk(net) {
        root.pendingNetwork = net;
        root.psk = "";
        root.pskVisible = false;
    }

    function cancelPsk() {
        root.pendingNetwork = null;
        root.psk = "";
        root.pskVisible = false;
        root.wifiError = "";
    }

    function submitPsk() {
        if (!pendingNetwork || psk.length < 8) return;
        pendingNetwork.connectWithPsk(psk);
        pendingNetwork = null;
        psk = "";
        pskVisible = false;
    }

    // ---- bluetooth ----
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter?.enabled ?? false

    readonly property var btDevices: {
        const out = [];
        const devices = Bluetooth.devices.values;
        for (let i = 0; i < devices.length; i++) out.push(devices[i]);
        out.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.paired !== b.paired) return a.paired ? -1 : 1;
            return (a.name || "").localeCompare(b.name || "");
        });
        return out;
    }

    readonly property string btName: {
        if (!btOn) return "Off";
        const devices = btDevices;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].connected) return devices[i].name || "Connected";
        }
        return "On";
    }

    function activateDevice(dev) {
        if (dev.connected) dev.disconnect();
        else if (dev.paired || dev.bonded) dev.connect();
        else dev.pair();
    }

    // ---- power profile ----
    readonly property string profileLabel: {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance: return "Performance";
        case PowerProfile.PowerSaver:  return "Battery saver";
        default:                       return "Balanced";
        }
    }

    readonly property string profileGlyph: {
        switch (PowerProfiles.profile) {
        case PowerProfile.Performance: return "󰓅";
        case PowerProfile.PowerSaver:  return "󰌪";
        default:                       return "󰗑";
        }
    }

    // ---- fan ----
    // hp-wmi exposes one writable knob, pwm1_enable, with two meaningful
    // values: the BIOS automatic curve, or both fans pinned at maximum. There
    // is no duty-cycle register, so "fan speed" is a three-way *setting* rather
    // than a slider:
    //
    //   auto    follow the power mode — performance pins the fans at max,
    //           battery and balanced hand them back to the BIOS curve
    //   normal  always the BIOS curve, even in performance mode
    //   max     always pinned, even in battery mode
    //
    // scripts/fan-control.sh owns the sysfs write and the persisted choice;
    // this only reads and drives it, so SUPER+P and the panel cannot disagree.
    readonly property string fanScript: riceDir + "/scripts/fan-control.sh"

    readonly property string fanLabel: {
        switch (root.fanMode) {
        case "max":    return "Max";
        case "normal": return "Normal";
        default:       return "Auto";
        }
    }

    Process {
        id: fanRead
        command: [root.fanScript, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                if (v === "auto" || v === "normal" || v === "max") root.fanMode = v;
            }
        }
    }

    Process { id: fanWrite }

    function setFanMode(m) {
        root.fanMode = m;                 // optimistic, so the row ticks at once
        fanWrite.running = false;
        fanWrite.command = [root.fanScript, "set", m];
        fanWrite.running = true;
    }

    Process { id: fanApply }

    // On "auto" the resolved pwm depends on the power mode, so a mode change
    // has to re-run the resolution. Harmless on "normal"/"max" — fan-control.sh
    // skips the write when the node already holds the value it wants.
    function applyFan() {
        fanApply.running = false;
        fanApply.command = [root.fanScript, "apply"];
        fanApply.running = true;
    }

    // ---- keeping waybar in step ----
    // waybar custom modules only re-exec on their poll interval (up to 10s),
    // so a change made in here used to take that long to show up in the bar.
    // Each module has a `signal` in config.jsonc; poking it repaints at once.
    // Signals are coalesced over 150ms so dragging a slider does not spawn a
    // pkill per frame.
    Process { id: waybarPoke }
    property var pendingPokes: ({})

    Timer {
        id: pokeTimer
        interval: 150
        onTriggered: {
            const sigs = Object.keys(root.pendingPokes);
            if (sigs.length === 0) return;
            root.pendingPokes = ({});
            waybarPoke.running = false;
            waybarPoke.command = ["sh", "-c",
                sigs.map(n => "pkill -RTMIN+" + n + " waybar").join("; ")];
            waybarPoke.running = true;
        }
    }

    function pokeWaybar(sig) {
        root.pendingPokes[sig] = true;
        pokeTimer.restart();
    }

    // Module signal numbers, from apps/waybar/config.jsonc.
    onVolumeChanged: pokeWaybar(2)
    onSinkMutedChanged: pokeWaybar(2)
    onMicMutedChanged: pokeWaybar(3)
    onWifiNameChanged: pokeWaybar(8)
    onBtNameChanged: pokeWaybar(9)
    onStayAwakeChanged: pokeWaybar(11)

    // battery-status.sh colours the waybar battery glyph from this file, and
    // waybar only repaints that module on RTMIN+10. Without this the bar kept
    // showing the mode it was last told about by SUPER+P.
    Process { id: waybarSync }

    function syncWaybarMode() {
        let mode = "normal";
        if (PowerProfiles.profile === PowerProfile.Performance) mode = "performance";
        else if (PowerProfiles.profile === PowerProfile.PowerSaver) mode = "battery";

        waybarSync.running = false;
        waybarSync.command = ["sh", "-c",
            "printf '%s' " + mode + " > /tmp/waybar-performance-mode;"
            + " pkill -RTMIN+10 waybar"];
        waybarSync.running = true;
    }

    // Fires for SUPER+P too, not just clicks in here.
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            root.syncWaybarMode();
            root.applyFan();
        }
    }

    Component.onCompleted: {
        root.syncWaybarMode();
        fanRead.running = true;
        // pwm1_enable resets to the BIOS default on every boot, so the saved
        // choice has to be re-asserted once the shell comes up.
        root.applyFan();
    }

    // ---- power actions (mirrors scripts/power-menu.sh) ----
    Process { id: powerProc }

    function powerAction(what) {
        let cmd;
        switch (what) {
        case "shutdown": cmd = [root.riceDir + "/scripts/mogger_shutdown.sh"]; break;
        case "reboot":   cmd = ["systemctl", "reboot"]; break;
        case "logout":   cmd = ["hyprctl", "dispatch", "exit"]; break;
        case "lock":     cmd = ["hyprlock", "-c",
                                root.riceDir + "/apps/hyprlock/hyprlock.conf"]; break;
        default: return;
        }
        root.close();
        powerProc.command = cmd;
        // Detached so hyprlock outlives this shell process.
        powerProc.startDetached();
    }

    // Balanced → Performance → Battery saver → Balanced. Skips Performance on
    // machines that do not offer it.
    function cycleProfile() {
        const p = PowerProfiles.profile;
        if (p === PowerProfile.Balanced) {
            PowerProfiles.profile = PowerProfiles.hasPerformanceProfile
                ? PowerProfile.Performance
                : PowerProfile.PowerSaver;
        } else if (p === PowerProfile.Performance) {
            PowerProfiles.profile = PowerProfile.PowerSaver;
        } else {
            PowerProfiles.profile = PowerProfile.Balanced;
        }
    }

    // ---- navigation ----
    // Scanning is expensive, so it runs only while the matching page is open.
    onPageChanged: {
        if (page === "privacy") privacyRead.running = true;
        if (wifiDevice) wifiDevice.scannerEnabled = (page === "wifi") && Networking.wifiEnabled;
        if (btAdapter) btAdapter.discovering = (page === "bluetooth") && btOn;
        if (page !== "wifi") cancelPsk();
        // Opening a page counts as asking it to look.
        if (page === "wifi" && Networking.wifiEnabled) {
            wifiScanning = true;
            wifiScanPulse.restart();
        }
        if (page === "bluetooth" && btOn) {
            btScanning = true;
            btScanPulse.restart();
        }
    }

    function open() {
        brightnessRead.running = true;
        fanRead.running = true;
        eyeComfortRead.running = true;
        privacyRead.running = true;
        shown = true;
    }

    function close() {
        shown = false;
        page = "main";
        powerExpanded = false;
        audioExpanded = false;
        brightnessExpanded = false;
        fanExpanded = false;
    }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void {
            if (root.shown) root.close();
            else root.open();
        }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function isOpen(): bool { return root.shown }
        function toggleStayAwake(): void { root.stayAwake = !root.stayAwake }
        function isStayAwake(): bool { return root.stayAwake }
    }

    // Held against the always-visible hot corner window — an inhibitor bound to
    // the panel would lapse every time the panel closed.
    IdleInhibitor {
        window: hotCorner
        enabled: root.stayAwake
    }

    // ================= reusable pieces =================

    component Slider: Item {
        id: slider

        property string glyph: ""
        property int value: 0            // 0–100
        // When set, the leading glyph becomes its own button.
        property bool iconClickable: false
        property bool iconActive: false
        signal moved(int value)
        signal iconClicked()

        implicitHeight: 28

        Rectangle {
            id: sliderIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            radius: 13
            color: {
                if (!slider.iconClickable) return "transparent";
                if (slider.iconActive) return root.accent;
                return sliderIconArea.containsMouse ? root.tileOff : "transparent";
            }
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: slider.glyph
                color: (slider.iconClickable && slider.iconActive) ? root.fg : root.muted
                font.family: root.iconFont
                font.pixelSize: 15
            }

            MouseArea {
                id: sliderIconArea
                anchors.fill: parent
                enabled: slider.iconClickable
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: slider.iconClicked()
            }
        }

        Item {
            id: trackArea
            anchors.left: sliderIcon.right
            anchors.leftMargin: 8
            anchors.right: readout.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 10
                radius: height / 2
                color: root.trackOff

                Rectangle {
                    // Clamped to the track: volume can sit above 100% (waybar
                    // allows boost to 150), and an unclamped fill would paint
                    // straight over the readout.
                    width: Math.min(parent.width,
                        Math.max(parent.height, parent.width * Math.min(100, slider.value) / 100))
                    height: parent.height
                    radius: parent.radius
                    color: root.fg
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => slider.moved(Math.round(mouse.x / width * 100))
                onPositionChanged: mouse => {
                    if (pressed) slider.moved(Math.round(mouse.x / width * 100));
                }
            }
        }

        Text {
            id: readout
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 38
            horizontalAlignment: Text.AlignRight
            text: slider.value + "%"
            color: root.muted
            font.family: root.uiFont
            font.pixelSize: 12
        }
    }

    component Tile: Rectangle {
        id: tile

        property string glyph: ""
        property string label: ""
        property string sublabel: ""
        property bool active: false
        // When true the round icon is its own button (toggles the radio) and
        // the rest of the tile opens a detail page.
        property bool splitIcon: false
        signal clicked()
        signal iconClicked()

        height: root.tileHeight
        radius: root.tileRadius
        color: bodyHover.containsMouse ? root.pressed : root.tileOff

        Behavior on color { ColorAnimation { duration: 150 } }

        // Declared first so the icon's own handler below sits on top of it.
        MouseArea {
            id: bodyHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.clicked()
        }

        Rectangle {
            id: bubble
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: width / 2
            color: {
                if (tile.active) {
                    return iconHover.containsMouse
                        ? root.accentHover
                        : root.accent;
                }
                return iconHover.containsMouse ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.18);
            }

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: tile.glyph
                color: tile.active ? root.accentFg : root.fg
                font.family: root.iconFont
                font.pixelSize: 16
            }

            MouseArea {
                id: iconHover
                anchors.fill: parent
                enabled: tile.splitIcon
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.iconClicked()
            }
        }

        Column {
            anchors.left: bubble.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: tile.label
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: tile.sublabel !== ""
                text: tile.sublabel
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }

    component Toggle: Rectangle {
        id: toggle

        property bool on: false
        signal switched()

        width: 40
        height: 22
        radius: height / 2
        color: toggle.on ? root.accent : root.trackOff

        Behavior on color { ColorAnimation { duration: 150 } }

        Rectangle {
            width: 16
            height: 16
            radius: width / 2
            y: 3
            x: toggle.on ? toggle.width - width - 3 : 3
            // The knob inverts on the white "on" track, or it vanishes into it.
            color: toggle.on ? root.accentFg : "#ffffff"
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.switched()
        }
    }

    // Header shared by both detail pages: back arrow, title, radio switch.
    component PageHeader: Item {
        id: header

        property string title: ""
        property bool on: false
        property string note: ""
        signal switched()

        implicitHeight: 30

        Text {
            id: backGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            text: "󰅁"
            color: backArea.containsMouse ? root.fg : root.muted
            font.family: root.iconFont
            font.pixelSize: 16

            MouseArea {
                id: backArea
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.page = "main"
            }
        }

        Text {
            id: headerTitle
            anchors.left: backGlyph.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: header.title
            color: root.fg
            font.family: root.uiFont
            font.pixelSize: 14
        }

        Text {
            anchors.left: headerTitle.right
            anchors.leftMargin: 8
            anchors.right: headerToggle.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: header.note
            color: root.faint
            font.family: root.uiFont
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Toggle {
            id: headerToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            on: header.on
            onSwitched: header.switched()
        }
    }

    component ListRow: Rectangle {
        id: listRow

        property string glyph: ""
        property string title: ""
        property string note: ""
        property string trailing: ""
        property bool active: false
        signal clicked()

        height: root.listRowHeight
        radius: 10
        color: listRow.active
            ? root.accent
            : (rowHover.containsMouse ? root.hover : "transparent")

        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            id: rowGlyph
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            text: listRow.glyph
            color: listRow.active ? root.accentFg : root.fg
            font.family: root.iconFont
            font.pixelSize: 15
        }

        Column {
            anchors.left: rowGlyph.right
            anchors.leftMargin: 8
            anchors.right: rowTrailing.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: listRow.title
                color: listRow.active ? root.accentFg : root.fg
                font.family: root.uiFont
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: listRow.note !== ""
                text: listRow.note
                color: listRow.active ? root.accentFgMuted : root.muted
                font.family: root.uiFont
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        Text {
            id: rowTrailing
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: listRow.trailing
            color: listRow.active ? root.accentFgMuted : root.faint
            font.family: root.iconFont
            font.pixelSize: 11
        }

        MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: listRow.clicked()
        }
    }

    // ================= hot corner =================

    PanelWindow {
        id: hotCorner

        color: "transparent"
        anchors.top: true
        anchors.right: true
        implicitWidth: root.hotSize
        implicitHeight: root.hotSize

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hypr-hotcorner"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            // Hover is the gesture; the click handler only exists so this tiny
            // patch of waybar is never a dead zone.
            onEntered: root.open()
            onClicked: root.open()
        }
    }

    // ================= panel =================

    PanelWindow {
        id: panel

        visible: root.shown || card.opacity > 0.01
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hypr-controlcenter"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        onVisibleChanged: if (visible) keys.forceActiveFocus()

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: keys
            focus: true
            Keys.onEscapePressed: {
                if (root.page === "main") root.close();
                else root.page = "main";
            }
        }

        Rectangle {
            id: card

            width: root.panelWidth
            height: content.implicitHeight + root.pad * 2
            // Flush against the underside of the waybar island and aligned to
            // its right edge, so it reads as an extension of the bar.
            y: root.barHeight
            anchors.right: parent.right
            anchors.rightMargin: root.islandInset

            Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

            // Slide via a transform rather than x: the card stays anchored to
            // the right edge, so the closed position does not depend on the
            // window's width (which is 0 while the window is unmapped).
            transform: Translate {
                x: root.shown ? 0 : root.panelWidth + root.edgeGap * 2
                Behavior on x { NumberAnimation { duration: 210; easing.type: Easing.OutCubic } }
            }

            opacity: root.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // Square where it meets the bar, rounded below.
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: root.cardRadius
            bottomRightRadius: root.cardRadius
            color: root.glass
            border.width: 1
            border.color: root.edge
            clip: true

            // Swallow clicks so they do not reach the dismiss layer underneath.
            MouseArea { anchors.fill: parent }

            Item {
                id: content
                x: root.pad
                y: root.pad
                width: parent.width - root.pad * 2
                implicitHeight: root.page === "wifi" ? pageWifi.implicitHeight
                              : root.page === "bluetooth" ? pageBt.implicitHeight
                              : root.page === "privacy" ? pagePrivacy.implicitHeight
                              : pageMain.implicitHeight

                // ---------------- main ----------------
                Column {
                    id: pageMain
                    width: parent.width
                    spacing: root.tileGap
                    visible: opacity > 0
                    opacity: root.page === "main" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    Text {
                        text: "Control Centre"
                        color: root.faint
                        font.family: root.uiFont
                        font.pixelSize: 11
                        bottomPadding: 2
                    }

                    Slider {
                        width: parent.width
                        glyph: "󰃟"
                        value: root.brightness
                        onMoved: v => root.setBrightness(v)
                        iconClickable: true
                        iconActive: root.brightnessExpanded
                        onIconClicked: {
                            root.brightnessExpanded = !root.brightnessExpanded;
                            if (root.brightnessExpanded) eyeComfortRead.running = true;
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: eyeComfortContent.implicitHeight + 24
                        radius: root.tileRadius
                        color: root.tileOff
                        visible: root.brightnessExpanded

                        Column {
                            id: eyeComfortContent
                            x: 12
                            y: 12
                            width: parent.width - 24
                            spacing: 10

                            Item {
                                width: parent.width
                                height: 30

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Eye Comfort"
                                    color: root.fg
                                    font.family: root.uiFont
                                    font.pixelSize: 13
                                }

                                Toggle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    on: root.eyeComfortEnabled
                                    enabled: root.eyeComfortAvailable
                                    opacity: enabled ? 1 : 0.4
                                    onSwitched: root.setEyeComfort(!root.eyeComfortEnabled,
                                        root.eyeComfortIntensity)
                                }
                            }

                            Text {
                                width: parent.width
                                text: root.eyeComfortError || (!root.eyeComfortAvailable
                                    ? "Install hyprsunset to enable Eye Comfort."
                                    : "Reduce blue light with a warmer screen.")
                                wrapMode: Text.WordWrap
                                color: root.eyeComfortError ? root.danger : root.muted
                                font.family: root.uiFont
                                font.pixelSize: 11
                            }

                            Slider {
                                width: parent.width
                                glyph: "󰖔"
                                value: root.eyeComfortIntensity
                                enabled: root.eyeComfortAvailable
                                opacity: enabled ? 1 : 0.4
                                onMoved: v => root.setEyeComfort(root.eyeComfortEnabled, v)
                            }

                            Item {
                                width: parent.width
                                height: 14
                                Text {
                                    anchors.left: parent.left
                                    text: "Less warm"
                                    color: root.faint
                                    font.family: root.uiFont
                                    font.pixelSize: 10
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: "More warm"
                                    color: root.faint
                                    font.family: root.uiFont
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }

                    Slider {
                        width: parent.width
                        glyph: root.sinkMuted ? "󰝟" : "󰕾"
                        value: Math.round(root.volume * 100)
                        // The icon opens the output/input device picker.
                        iconClickable: true
                        iconActive: root.audioExpanded
                        onMoved: v => {
                            if (root.sink?.audio) root.sink.audio.volume = v / 100;
                        }
                        onIconClicked: root.audioExpanded = !root.audioExpanded
                    }

                    // Audio device picker — speaker and mic chosen separately.
                    Column {
                        width: parent.width
                        spacing: 2
                        visible: root.audioExpanded

                        Text {
                            text: "OUTPUT"
                            color: root.faint
                            font.family: root.uiFont
                            font.pixelSize: 10
                            font.letterSpacing: 0.8
                            topPadding: 6
                            bottomPadding: 2
                            leftPadding: 4
                        }

                        Repeater {
                            model: root.audioSinks

                            ListRow {
                                id: sinkRow
                                required property var modelData
                                width: parent.width
                                glyph: "󰕾"
                                title: root.deviceLabel(sinkRow.modelData)
                                trailing: sinkRow.active ? "󰄬" : ""
                                active: root.sink !== null
                                    && sinkRow.modelData.id === root.sink.id
                                onClicked: root.setDefaultNode(sinkRow.modelData)
                            }
                        }

                        Text {
                            text: "INPUT"
                            color: root.faint
                            font.family: root.uiFont
                            font.pixelSize: 10
                            font.letterSpacing: 0.8
                            topPadding: 8
                            bottomPadding: 2
                            leftPadding: 4
                        }

                        Repeater {
                            model: root.audioSources

                            ListRow {
                                id: srcRow
                                required property var modelData
                                width: parent.width
                                glyph: "󰍬"
                                title: root.deviceLabel(srcRow.modelData)
                                trailing: srcRow.active ? "󰄬" : ""
                                active: root.source !== null
                                    && srcRow.modelData.id === root.source.id
                                onClicked: root.setDefaultNode(srcRow.modelData)
                            }
                        }
                    }

                    Item { width: 1; height: 2 }

                    // Wi-Fi | Bluetooth — icon toggles, body opens the page.
                    Row {
                        width: parent.width
                        spacing: root.tileGap

                        Tile {
                            width: (parent.width - root.tileGap) / 2
                            glyph: Networking.wifiEnabled ? "󰤨" : "󰤮"
                            label: "Wi-Fi"
                            sublabel: root.wifiName
                            active: Networking.wifiEnabled
                            splitIcon: true
                            onIconClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                            onClicked: root.page = "wifi"
                        }

                        Tile {
                            width: (parent.width - root.tileGap) / 2
                            glyph: root.btOn ? "󰂯" : "󰂲"
                            label: "Bluetooth"
                            sublabel: root.btName
                            active: root.btOn
                            splitIcon: true
                            onIconClicked: {
                                if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled;
                            }
                            onClicked: root.page = "bluetooth"
                        }
                    }

                    // Power profile — the body cycles the three modes (same
                    // as SUPER+P), the icon opens the fan drawer underneath.
                    Tile {
                        width: parent.width
                        glyph: root.profileGlyph
                        label: "Power mode"
                        sublabel: root.profileLabel + "  ·  Fan " + root.fanLabel.toLowerCase()
                        active: PowerProfiles.profile !== PowerProfile.Balanced
                                || root.fanExpanded
                        splitIcon: true
                        onIconClicked: root.fanExpanded = !root.fanExpanded
                        onClicked: root.cycleProfile()
                    }

                    // Fan override. Deliberately independent of the power mode:
                    // "normal" keeps the fans civil while the CPU runs flat out,
                    // "max" pins them even on battery.
                    Column {
                        width: parent.width
                        spacing: 2
                        visible: root.fanExpanded

                        ListRow {
                            width: parent.width
                            glyph: "󰑐"
                            title: "Auto"
                            note: "Follows the power mode"
                            trailing: root.fanMode === "auto" ? "󰄬" : ""
                            active: root.fanMode === "auto"
                            onClicked: root.setFanMode("auto")
                        }
                        ListRow {
                            width: parent.width
                            glyph: "󰈐"
                            title: "Normal"
                            note: "BIOS curve, even in performance"
                            trailing: root.fanMode === "normal" ? "󰄬" : ""
                            active: root.fanMode === "normal"
                            onClicked: root.setFanMode("normal")
                        }
                        ListRow {
                            width: parent.width
                            glyph: "󰓅"
                            title: "Max"
                            note: "Pinned at full speed, even on battery"
                            trailing: root.fanMode === "max" ? "󰄬" : ""
                            active: root.fanMode === "max"
                            onClicked: root.setFanMode("max")
                        }
                    }

                    // Mic | stay awake
                    Row {
                        width: parent.width
                        spacing: root.tileGap

                        Tile {
                            width: (parent.width - root.tileGap) / 2
                            glyph: root.micMuted ? "󰍭" : "󰍬"
                            label: "Microphone"
                            sublabel: root.micMuted ? "Muted" : "On"
                            active: !root.micMuted
                            onClicked: {
                                if (root.source?.audio)
                                    root.source.audio.muted = !root.source.audio.muted;
                            }
                        }

                        Tile {
                            width: (parent.width - root.tileGap) / 2
                            glyph: root.stayAwake ? "󰅶" : "󰒲"
                            label: "Stay awake"
                            sublabel: root.stayAwake ? "On" : "Off"
                            active: root.stayAwake
                            onClicked: root.stayAwake = !root.stayAwake
                        }
                    }

                    Tile {
                        width: parent.width
                        glyph: "󰒃"
                        label: "Privacy"
                        sublabel: "MAC address · Tor Browser"
                        onClicked: root.page = "privacy"
                    }

                    // Power — expands a drawer rather than opening a page, so
                    // the destructive actions always take two deliberate clicks.
                    Tile {
                        width: parent.width
                        glyph: "󰐥"
                        label: "Power"
                        sublabel: root.powerExpanded
                            ? "Pick an action"
                            : "Shut down, restart, log out, lock"
                        active: root.powerExpanded
                        onClicked: root.powerExpanded = !root.powerExpanded
                    }

                    Column {
                        width: parent.width
                        spacing: 2
                        visible: root.powerExpanded

                        ListRow {
                            width: parent.width
                            glyph: "󰐥"
                            title: "Shut down"
                            onClicked: root.powerAction("shutdown")
                        }
                        ListRow {
                            width: parent.width
                            glyph: "󰜉"
                            title: "Restart"
                            onClicked: root.powerAction("reboot")
                        }
                        ListRow {
                            width: parent.width
                            glyph: "󰍃"
                            title: "Log out"
                            onClicked: root.powerAction("logout")
                        }
                        ListRow {
                            width: parent.width
                            glyph: "󰌾"
                            title: "Lock"
                            onClicked: root.powerAction("lock")
                        }
                    }
                }

                // ---------------- privacy ----------------
                Column {
                    id: pagePrivacy
                    width: parent.width
                    spacing: 10
                    visible: root.page === "privacy"

                    Item {
                        width: parent.width
                        height: 30
                        Text {
                            anchors.centerIn: parent
                            text: "Privacy"
                            color: root.fg
                            font.family: root.uiFont
                            font.pixelSize: 15
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "‹ Back"
                            color: root.muted
                            font.family: root.uiFont
                            font.pixelSize: 13
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.page = "main"
                            }
                        }
                    }

                    Tile {
                        width: parent.width
                        glyph: "󰒃"
                        label: root.privacyState.restorable ? "Restore MAC setting" : "Randomize MAC"
                        sublabel: root.privacyState.randomized ? "Random address on each connection"
                            : "Use a random address on this network"
                        active: root.privacyState.randomized ?? false
                        enabled: !privacyWrite.running && !!root.privacyState.device
                        opacity: enabled ? 1 : 0.5
                        onClicked: root.privacyAction(root.privacyState.restorable ? "mac-off" : "mac-on")
                    }

                    Text {
                        width: parent.width
                        text: "Changing the MAC briefly reconnects this network."
                        color: root.muted
                        font.family: root.uiFont
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        text: (root.privacyState.device || "No active network")
                            + "\nCurrent MAC: " + (root.privacyState.mac || "Unavailable")
                            + (root.privacyState.previous_mac ? "\nPrevious MAC: " + root.privacyState.previous_mac : "")
                        color: root.muted
                        font.family: root.uiFont
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Rectangle { width: parent.width; height: 1; color: root.edge }

                    Tile {
                        width: parent.width
                        glyph: "󰇧"
                        label: root.privacyState.browser_available ? "Open Tor Browser" : "Install Tor Browser"
                        sublabel: root.privacyState.browser_available ? "Private browsing through Tor" : "Requires administrator authentication"
                        enabled: !privacyWrite.running
                        opacity: enabled ? 1 : 0.5
                        onClicked: root.privacyAction(root.privacyState.browser_available ? "browser" : "install")
                    }

                    Text {
                        width: parent.width
                        text: "Tor Browser hides your IP for browsing inside it. Other apps keep their usual connection."
                        color: root.muted
                        font.family: root.uiFont
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    ListRow {
                        width: parent.width
                        glyph: "󰄬"
                        title: "Check public IPs"
                        note: "Connect Tor Browser first · checks IPv4"
                        enabled: !privacyWrite.running
                        opacity: enabled ? 1 : 0.5
                        onClicked: root.privacyAction("check")
                    }

                    Text {
                        width: parent.width
                        visible: !!root.privacyCheck.direct_ip
                        text: "Ordinary connection: " + (root.privacyCheck.direct_ip || "")
                            + "\nTor connection: " + (root.privacyCheck.tor_ip || "")
                            + (root.privacyCheck.tor_verified ? "\nTor exit verified" : "\nTor not verified")
                        color: root.muted
                        font.family: root.uiFont
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        visible: privacyWrite.running
                        text: privacyWrite.action === "check" ? "Checking connections…"
                            : privacyWrite.action === "install" ? "Installing Tor Browser…"
                            : "Applying…"
                        color: root.muted
                        font.family: root.uiFont
                        font.pixelSize: 11
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: root.privacyError || root.privacyState.error || root.privacyMessage
                        color: (root.privacyError || root.privacyState.error) ? root.danger : root.muted
                        font.family: root.uiFont
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                // ---------------- wi-fi ----------------
                Column {
                    id: pageWifi
                    width: parent.width
                    spacing: 8
                    visible: opacity > 0
                    opacity: root.page === "wifi" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    PageHeader {
                        width: parent.width
                        title: "Wi-Fi"
                        on: Networking.wifiEnabled
                        note: root.wifiScanning ? "scanning…" : ""
                        onSwitched: Networking.wifiEnabled = !Networking.wifiEnabled
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.edge
                    }

                    Text {
                        width: parent.width
                        visible: !Networking.wifiEnabled || root.wifiNetworks.length === 0
                        text: !Networking.wifiEnabled
                            ? "Wi-Fi is off"
                            : (root.wifiScanning ? "Searching for networks…" : "No networks found")
                        color: root.muted
                        font.family: root.uiFont
                        font.pixelSize: 12
                        topPadding: 10
                        bottomPadding: 10
                    }

                    ListView {
                        width: parent.width
                        visible: Networking.wifiEnabled && root.wifiNetworks.length > 0
                        height: visible
                            ? Math.min(root.wifiNetworks.length * root.listRowHeight, root.listMaxHeight)
                            : 0
                        model: root.wifiNetworks
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: ListRow {
                            id: netRow
                            required property var modelData
                            width: ListView.view.width
                            glyph: root.wifiGlyph(netRow.modelData.signalStrength || 0)
                            title: netRow.modelData.name
                            note: netRow.modelData.connected
                                ? "Connected"
                                : (netRow.modelData.stateChanging
                                    ? "Connecting…"
                                    : (netRow.modelData.known ? "Saved" : "New network"))
                            trailing: (root.isOpenNetwork(netRow.modelData) ? "" : "󰌾  ")
                                + Math.round((netRow.modelData.signalStrength || 0) * 100) + "%"
                            active: netRow.modelData.connected
                            onClicked: root.activateNetwork(netRow.modelData)

                            // A saved network whose stored key is wrong (or was
                            // cleared) fails with NoSecrets — ask again rather
                            // than failing silently.
                            Connections {
                                target: netRow.modelData
                                function onConnectionFailed(reason) {
                                    if (reason === ConnectionFailReason.NoSecrets) {
                                        root.askForPsk(netRow.modelData);
                                        root.wifiError = "Wrong password — try again";
                                    } else {
                                        root.wifiError = "Could not connect to "
                                            + netRow.modelData.name;
                                    }
                                }
                            }
                        }
                    }

                    // Password prompt for a secured network we have no working
                    // credentials for.
                    Rectangle {
                        id: pskBox
                        width: parent.width
                        visible: root.pendingNetwork !== null
                        height: visible ? 76 : 0
                        radius: 10
                        color: root.tileOff
                        clip: true

                        Text {
                            id: pskTitle
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            y: 9
                            text: "󰌾  Password for " + (root.pendingNetwork?.name ?? "")
                            color: root.fg
                            font.family: root.uiFont
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        // input | show/hide | connect | cancel
                        Rectangle {
                            id: pskField
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.top: pskTitle.bottom
                            anchors.topMargin: 6
                            height: 30
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.08)

                            TextInput {
                                id: pskInput
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: pskButtons.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                echoMode: root.pskVisible ? TextInput.Normal : TextInput.Password
                                color: root.fg
                                font.family: root.uiFont
                                font.pixelSize: 12
                                clip: true

                                text: root.psk
                                onTextChanged: root.psk = text
                                onAccepted: root.submitPsk()
                                Keys.onEscapePressed: root.cancelPsk()

                                // Focus follows the prompt appearing.
                                Connections {
                                    target: root
                                    function onPendingNetworkChanged() {
                                        if (root.pendingNetwork) pskInput.forceActiveFocus();
                                    }
                                }

                                Text {
                                    anchors.fill: parent
                                    visible: pskInput.text === ""
                                    verticalAlignment: Text.AlignVCenter
                                    text: "at least 8 characters"
                                    color: root.faint
                                    font: pskInput.font
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: pskButtons
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                // Reveal — a WPA key is long enough to be worth
                                // checking before submitting.
                                Text {
                                    width: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: root.iconFont
                                    text: root.pskVisible ? "󰈉" : "󰈈"
                                    color: revealArea.containsMouse ? root.fg : root.muted
                                    font.pixelSize: 13
                                    MouseArea {
                                        id: revealArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.pskVisible = !root.pskVisible
                                    }
                                }

                                Text {
                                    width: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: root.iconFont
                                    text: "󰌑"
                                    color: root.psk.length >= 8
                                        ? (connectArea.containsMouse ? root.fg : root.muted)
                                        : Qt.rgba(1, 1, 1, 0.18)
                                    font.pixelSize: 13
                                    MouseArea {
                                        id: connectArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: root.psk.length >= 8
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.submitPsk()
                                    }
                                }

                                Text {
                                    width: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: root.iconFont
                                    text: "󰅖"
                                    color: cancelArea.containsMouse ? root.fg : root.muted
                                    font.pixelSize: 13
                                    MouseArea {
                                        id: cancelArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.cancelPsk()
                                    }
                                }
                            }
                        }
                    }

                    // Connection error, shown whether or not the prompt is up.
                    // No height binding here: Column already drops invisible
                    // children, and height:implicitHeight would be a loop.
                    Text {
                        width: parent.width
                        visible: root.wifiError !== ""
                        text: root.wifiError
                        color: "#ff6b6b"
                        font.family: root.uiFont
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    // Search for new networks.
                    ListRow {
                        width: parent.width
                        visible: Networking.wifiEnabled
                        height: visible ? root.listRowHeight : 0
                        glyph: "󰑓"
                        title: root.wifiScanning ? "Searching…" : "Search for networks"
                        note: root.wifiScanning ? "" : "Scan for new Wi-Fi networks nearby"
                        onClicked: root.rescanWifi()
                    }

                    // Forget is only meaningful for a saved network.
                    ListRow {
                        width: parent.width
                        visible: root.wifiNetworks.some(n => n.connected)
                        height: visible ? root.listRowHeight : 0
                        glyph: "󰩹"
                        title: "Forget this network"
                        onClicked: {
                            const nets = root.wifiNetworks;
                            for (let i = 0; i < nets.length; i++) {
                                if (nets[i].connected) { nets[i].forget(); return; }
                            }
                        }
                    }
                }

                // ---------------- bluetooth ----------------
                Column {
                    id: pageBt
                    width: parent.width
                    spacing: 8
                    visible: opacity > 0
                    opacity: root.page === "bluetooth" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    PageHeader {
                        width: parent.width
                        title: "Bluetooth"
                        on: root.btOn
                        note: root.btScanning ? "scanning…" : ""
                        onSwitched: {
                            if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled;
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.edge
                    }

                    Text {
                        width: parent.width
                        visible: !root.btOn || root.btDevices.length === 0
                        text: !root.btOn
                            ? "Bluetooth is off"
                            : (root.btScanning ? "Searching for devices…" : "No devices found")
                        color: root.muted
                        font.family: root.uiFont
                        font.pixelSize: 12
                        topPadding: 10
                        bottomPadding: 10
                    }

                    ListView {
                        width: parent.width
                        visible: root.btOn && root.btDevices.length > 0
                        height: visible
                            ? Math.min(root.btDevices.length * root.listRowHeight, root.listMaxHeight)
                            : 0
                        model: root.btDevices
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: ListRow {
                            required property var modelData
                            width: ListView.view.width
                            glyph: modelData.connected ? "󰂱" : "󰂲"
                            title: modelData.name || modelData.address
                            note: {
                                if (modelData.pairing) return "Pairing…";
                                if (modelData.state === BluetoothDeviceState.Connecting) return "Connecting…";
                                if (modelData.connected) return "Connected";
                                if (modelData.paired) return "Paired";
                                return "Available";
                            }
                            trailing: modelData.batteryAvailable
                                ? Math.round(modelData.battery * 100) + "%"
                                : ""
                            active: modelData.connected
                            onClicked: root.activateDevice(modelData)
                        }
                    }

                    // Search for new devices.
                    ListRow {
                        width: parent.width
                        visible: root.btOn
                        height: visible ? root.listRowHeight : 0
                        glyph: "󰑓"
                        title: root.btScanning ? "Searching…" : "Search for devices"
                        note: root.btScanning ? "" : "Scan for nearby Bluetooth devices"
                        onClicked: root.rescanBt()
                    }
                }
            }
        }
    }
}
