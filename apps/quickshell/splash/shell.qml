//@ pragma UseQApplication

// A bounded, silent login overlay. Run through scripts/splash.sh so an
// unresponsive Qt decoder cannot keep a window or process alive indefinitely.
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // The fade is part of this budget, not added after it. Startup/decoder
    // stalls are separately bounded by the launcher's external watchdog.
    readonly property int holdMs: 850
    readonly property int fadeMs: 180
    readonly property int minShowMs: 320
    readonly property int pollMs: 80
    readonly property url video: "file://" + Quickshell.shellPath("../../../assets/splash.mp4")
        .split("/").map(encodeURIComponent).join("/")

    property bool showing: false
    property bool finished: false
    property bool dismissing: false
    property int decodedFrames: 0
    property double startedAt: 0
    property int exitCode: 0

    function dismiss(reason) {
        if (dismissing || !showing) return;
        console.info("splash: dismiss", reason);
        dismissing = true;
        poll.stop();
        reveal.start();
    }

    function finish(code) {
        if (finished) return;
        finished = true;
        // Unmap FIRST. Stopping/clearing a MediaPlayer can block while FFmpeg
        // drains its decoder. Never put that operation before hiding windows.
        showing = false;
        exitCode = code;
        poll.stop();
        fadeDeadline.stop();
        hardDeadline.stop();
        reveal.stop();
        console.info("splash: hidden");
        exitDelay.start();
    }

    Component.onCompleted: {
        if (finished) return;
        startedAt = Date.now();
        poll.start();
        fadeDeadline.start();
        hardDeadline.start();
        // Do not cover the desktop while QML/QtMultimedia are initializing.
        showing = true;
    }

    // One overlay per connected output, all governed by the same deadline.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            visible: root.showing
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hypr-splash"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Fade both the black background and video to reveal the desktop.
            // Fading the video alone would leave an opaque black window.
            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: root.dismissing ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: root.fadeMs; easing.type: Easing.InOutQuad }
                }
                MouseArea { anchors.fill: parent }
                VideoOutput {
                    id: output
                    anchors.centerIn: parent
                    height: Math.round(Math.min(parent.width, parent.height) * 0.55)
                    width: height
                    fillMode: VideoOutput.PreserveAspectFit

                    // Wait for a real frame before dismissing an already-ready desktop.
                    Connections {
                        target: output.videoSink
                        function onVideoFrameChanged(frame) { root.decodedFrames += 1 }
                    }
                }
            }

            MediaPlayer {
                id: player
                source: root.video
                videoOutput: output
                // No AudioOutput: the login animation is always silent.
                Component.onCompleted: play()
                onErrorOccurred: function(error, message) {
                    console.warn("splash: cannot play video:", message);
                    root.finish(1);
                }
            }
        }
    }

    // Never overlap probes; splash-ready.sh also limits its IPC call.
    Process {
        id: ready
        command: [Quickshell.shellPath("../../../scripts/splash-ready.sh")]
        onExited: function(code) {
            if (code === 0 && root.decodedFrames > 0 && Date.now() - root.startedAt >= root.minShowMs)
                root.dismiss("desktop ready");
        }
    }
    Timer {
        id: poll
        interval: root.pollMs
        repeat: true
        onTriggered: if (!ready.running) ready.running = true
    }
    Timer {
        id: fadeDeadline
        interval: root.holdMs - root.fadeMs
        onTriggered: root.dismiss("deadline")
    }
    Timer {
        id: hardDeadline
        interval: root.holdMs
        onTriggered: root.finish(0)
    }
    Timer {
        id: reveal
        interval: root.fadeMs
        onTriggered: root.finish(0)
    }
    Timer {
        id: exitDelay
        interval: 25
        // Allow the unmap requests to reach Wayland before decoder teardown.
        onTriggered: Qt.exit(root.exitCode)
    }
}
