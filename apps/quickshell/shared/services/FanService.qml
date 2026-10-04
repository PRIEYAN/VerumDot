// FanService — the hp-wmi fan setting.
//
// hp-wmi exposes one writable knob, pwm1_enable, with two meaningful values:
// the BIOS automatic curve, or both fans pinned at maximum. There is no
// duty-cycle register, so "fan speed" is a three-way *setting* rather than a
// slider:
//
//   auto    follow the power mode — performance pins the fans, the others
//           hand them back to the BIOS curve
//   normal  always the BIOS curve, even in performance mode
//   max     always pinned, even on battery
//
// lib/domain/fan.sh owns the sysfs write and the persisted choice; this only
// reads and drives it, so SUPER+P and this panel cannot disagree.

import QtQuick
import Quickshell.Io

QtObject {
    id: service

    // Absolute path to scripts/fan-control.sh.
    required property string script

    readonly property var modes: ["auto", "normal", "max"]
    property string mode: "auto"

    readonly property string label: {
        switch (service.mode) {
        case "max":    return "Max";
        case "normal": return "Normal";
        default:       return "Auto";
        }
    }

    readonly property Process _read: Process {
        command: [service.script, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim();
                if (service.modes.indexOf(value) !== -1) service.mode = value;
            }
        }
    }

    readonly property Process _write: Process {}
    readonly property Process _apply: Process {}

    function refresh() {
        _read.running = true;
    }

    function setMode(next) {
        // Optimistic, so the row ticks the instant it is clicked; the next
        // refresh corrects it if the write was refused.
        service.mode = next;
        _write.running = false;
        _write.command = [service.script, "set", next];
        _write.running = true;
    }

    // On "auto" the resolved pwm depends on the power mode, so a mode change
    // has to re-run the resolution. Harmless on "normal" and "max" —
    // fan-control.sh skips the write when the node already holds that value.
    function apply() {
        _apply.running = false;
        _apply.command = [service.script, "apply"];
        _apply.running = true;
    }
}
