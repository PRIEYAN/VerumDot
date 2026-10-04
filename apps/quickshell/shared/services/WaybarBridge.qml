// WaybarBridge — repainting waybar modules on demand.
//
// waybar custom modules only re-exec on their poll interval, up to ten
// seconds, so a change made in a panel used to take that long to appear in
// the bar. Each module declares a `signal` number in config.jsonc, and
// sending RTMIN+<n> repaints it at once.
//
// Signals are coalesced over a short window: dragging a slider would
// otherwise spawn one pkill per frame.

import QtQuick
import Quickshell.Io

QtObject {
    id: bridge

    readonly property int coalesceMs: 150

    // The module signal numbers, mirroring WAYBAR_SIGNAL in lib/ui/waybar.sh
    // and the `signal` fields in apps/waybar/config.jsonc. Named, because
    // "pokeWaybar(9)" at a call site says nothing about what repaints.
    readonly property int brightness: 1
    readonly property int volume: 2
    readonly property int mic: 3
    readonly property int wifi: 8
    readonly property int bluetooth: 9
    readonly property int battery: 10
    readonly property int stayAwake: 11
    readonly property int spotify: 12

    property var _pending: ({})

    readonly property Process _poke: Process {}

    readonly property Timer _timer: Timer {
        interval: bridge.coalesceMs
        onTriggered: {
            const signals = Object.keys(bridge._pending);
            if (signals.length === 0) return;
            bridge._pending = ({});
            bridge._poke.running = false;
            bridge._poke.command = ["sh", "-c",
                signals.map(n => "pkill -RTMIN+" + n + " waybar").join("; ")];
            bridge._poke.running = true;
        }
    }

    function repaint(signalNumber) {
        bridge._pending[signalNumber] = true;
        _timer.restart();
    }
}
