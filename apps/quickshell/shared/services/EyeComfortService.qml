// EyeComfortService — the warm-tint filter.
//
// hyprsunset has no IPC, so every change is stop-the-daemon-and-start-a-new-
// one. That makes writes expensive and ordering important, which is why this
// object coalesces a drag into a single write and never has two in flight.
//
// The shell script is the only thing that actually touches hyprsunset (see
// lib/domain/eyecomfort.sh); this is a client of it, so the bar toggle and
// this panel cannot disagree about what is running.

import QtQuick
import Quickshell.Io

QtObject {
    id: service

    // Absolute path to apps/waybar/scripts/eye-comfort-toggle.sh.
    required property string script

    // Poll only while the panel section that shows this is actually open.
    property bool active: false

    property bool enabled: false
    property bool available: false
    property int intensity: 70
    property string error: ""

    // True between the user moving the slider and the write landing. While
    // set, incoming status reads are ignored: they describe the daemon as it
    // was before the change and would visibly snap the slider backwards.
    property bool pending: false

    readonly property int coalesceMs: 180
    readonly property int pollMs: 2000

    readonly property Process _read: Process {
        command: [service.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (service.pending || service._write.running) return;
                try {
                    const state = JSON.parse(text);
                    service.enabled = state.enabled;
                    service.intensity = state.intensity;
                    service.available = state.available;
                } catch (e) {
                    service.error = "Could not read Eye Comfort status.";
                }
            }
        }
    }

    readonly property Process _write: Process {
        onExited: (exitCode) => {
            if (exitCode !== 0)
                service.error = "Could not apply Eye Comfort. Try again.";
            // A value that arrived while this write was running is applied
            // next; otherwise re-read to pick up what actually happened.
            if (service.pending) service._delay.restart();
            else service._read.running = true;
        }
    }

    // Coalesces a drag and serialises writes, preserving the final value.
    readonly property Timer _delay: Timer {
        interval: service.coalesceMs
        onTriggered: {
            if (service._write.running) return;
            service.pending = false;
            service._write.command = [service.script, "apply",
                service.enabled ? "on" : "off", String(service.intensity)];
            service._write.running = true;
        }
    }

    readonly property Timer _poll: Timer {
        interval: service.pollMs
        repeat: true
        running: service.active
        onTriggered: {
            if (!service.pending && !service._write.running)
                service._read.running = true;
        }
    }

    function refresh() {
        _read.running = true;
    }

    function apply(isEnabled, newIntensity) {
        if (!service.available) return;
        service.enabled = isEnabled;
        service.intensity = Math.max(0, Math.min(100, Math.round(newIntensity)));
        service.error = "";
        service.pending = true;
        _delay.restart();
    }
}
