// PrivacyService — MAC randomisation and the Tor reachability check.
//
// Every call is the same shape: run scripts/privacy-control.py with a verb,
// parse one JSON object, and route it by which verb asked. Routing on the
// verb rather than on the shape of the reply is deliberate — `check` and
// `status` both return objects, and guessing between them by their keys
// would break the moment either gained a field.

import QtQuick
import Quickshell.Io

QtObject {
    id: service

    // Absolute path to scripts/privacy-control.py.
    required property string script

    // Poll only while the privacy page is the one on screen.
    property bool active: false

    property var state: ({})
    property var check: ({})
    property string error: ""
    property string message: ""

    readonly property int pollMs: 3000
    readonly property bool busy: _write.running
    // Which verb is in flight, so the panel can label its progress line.
    readonly property string action: _write.action

    readonly property Process _read: Process {
        command: ["python3", service.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { service.state = JSON.parse(text); }
                catch (e) { service.error = "Could not read privacy status."; }
            }
        }
    }

    readonly property Process _write: Process {
        property string action: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.error) service.error = result.error;
                    else if (service._write.action === "check") service.check = result;
                    else if (result.message) service.message = result.message;
                    else service.state = result;
                } catch (e) {
                    service.error = "The privacy action did not finish.";
                }
            }
        }
        onExited: (exitCode) => {
            // pkexec returns non-zero when the user cancels the prompt, which
            // is not a failure worth shouting about — but it must not be
            // silent either, or the panel just appears to do nothing.
            if (exitCode !== 0 && !service.error)
                service.error = "The privacy action failed or was cancelled.";
            service._read.running = true;
        }
    }

    readonly property Timer _poll: Timer {
        interval: service.pollMs
        repeat: true
        running: service.active && !service._write.running
        onTriggered: service._read.running = true
    }

    function refresh() {
        _read.running = true;
    }

    function run(action) {
        if (_write.running) return;
        service.error = "";
        service.message = "";
        if (action !== "check") service.check = ({});
        _write.action = action;
        _write.command = ["python3", service.script, action];
        _write.running = true;
    }
}
