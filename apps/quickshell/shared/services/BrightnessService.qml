// BrightnessService — the backlight, via brightnessctl.
//
// The one piece of hardware with no native quickshell service, so it is the
// one that has to shell out. Extracted from the control centre's root object
// so that object stops being eight services and a UI at once.

import QtQuick
import Quickshell.Io

QtObject {
    id: service

    // Current level, 0-100.
    property int value: 0

    // Emitted after a write lands, so the owner can repaint the bar without
    // this object needing to know waybar exists.
    signal changed()

    // Floored at 5: a slider that reaches 0 blacks the panel out with no way
    // back, since the control to undo it is on the screen that went dark.
    readonly property int minimum: 5

    readonly property Process _read: Process {
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                // machine-readable form: device,class,current,percent,max
                const parts = text.trim().split(",");
                if (parts.length < 4) return;
                const percent = parseInt(parts[3].replace("%", ""), 10);
                if (!isNaN(percent)) service.value = percent;
            }
        }
    }

    readonly property Process _write: Process {}

    function refresh() {
        _read.running = true;
    }

    function set(percent) {
        const clamped = Math.max(service.minimum, Math.min(100, Math.round(percent)));
        service.value = clamped;
        _write.command = ["brightnessctl", "set", clamped + "%"];
        _write.running = true;
        service.changed();
    }
}
