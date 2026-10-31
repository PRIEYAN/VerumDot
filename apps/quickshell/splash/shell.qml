//@ pragma UseQApplication

// Boot splash — the first exec-once in hyprland.conf.
//
// A pure black overlay with assets/splash.mp4 centred on it, covering the
// desktop while hyprpaper and waybar come up behind it. It lifts as soon as
// scripts/splash-ready.sh reports those are up, and in any case at holdMs:
// the deadline is a ceiling, not a wait, so a service that crashes or stalls
// on a low battery can delay nothing. The surface is an Overlay layer so it
// sits above the bar while the bar is still painting its first frame.
//
// The video is 7s long and is deliberately truncated — the budget is the
// second, not the clip. keyboardFocus stays None so keystrokes typed during
// boot land in whatever gets focus afterwards rather than being swallowed.
//
// Run: qs -p ~/.config/hypr/apps/quickshell/splash

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // Hard ceiling on how long the splash may own the screen, and the tail of
    // that budget spent fading out rather than cutting to the desktop.
    //
    // 850, not 1000: the scheduler is contending with video decode here, so
    // the fade lands 30-100ms past its nominal time. A nominal 1000 measured
    // 958-1053ms on the wall clock and so broke the one-second budget on some
    // boots; 850 measured 881-954ms over six runs. The ceiling has to hold on
    // the slow runs, not the median, so the slack lives in the constant.
    readonly property int holdMs: 850
    readonly property int fadeMs: 180
    // How often to ask whether the desktop is ready. Cheap: two process checks.
    readonly property int pollMs: 80
    // Floor on the reveal, so a session that is somehow ready instantly still
    // shows the clip rather than flashing a black frame and vanishing.
    readonly property int minShowMs: 320

    // Quickshell loads this file through a qrc: virtual path, so Qt.resolvedUrl
    // on a relative path yields "qrc:/qs-blackhole" and the player rejects it as
    // an invalid resource. shellPath() resolves against the real directory, so
    // the clip is still found when the repo is cloned somewhere other than
    // ~/.config/hypr.
    readonly property url video: "file://" + Quickshell.shellPath("../../../assets/splash.mp4")

    PanelWindow {
        id: panel

        color: "#000000"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hypr-splash"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Swallow clicks so a stray tap during boot cannot reach whatever is
        // painting underneath.
        MouseArea { anchors.fill: parent }

        Item {
            id: stage
            anchors.fill: parent
            opacity: 1.0

            Behavior on opacity {
                NumberAnimation { duration: root.fadeMs; easing.type: Easing.InOutQuad }
            }

            VideoOutput {
                id: output
                anchors.centerIn: parent
                // Portrait clip: size off the screen's short edge so it never
                // runs past the top and bottom of the display.
                height: Math.round(parent.height * 0.55)
                width: height
                fillMode: VideoOutput.PreserveAspectFit
            }
        }

        MediaPlayer {
            id: player
            source: root.video
            videoOutput: output

            // A missing or undecodable file must not hold the screen black for
            // the full second — bail out as soon as the error is known.
            onErrorOccurred: function(err, str) {
                console.warn("splash: cannot play video:", str);
                Qt.exit(1);
            }
        }

        // Elapsed time owned here rather than read back from the player: the
        // clip keeps running through the fade, so its position is not the
        // splash's age.
        property double startedAt: 0
        property bool dismissing: false

        Component.onCompleted: {
            startedAt = Date.now();
            player.play();
            hold.start();
            poll.start();
        }

        // dismiss() — begin the fade. Idempotent, because the readiness poll
        // and the deadline race each other by design and either may win.
        function dismiss() {
            if (dismissing)
                return;
            dismissing = true;
            poll.stop();
            hold.stop();
            stage.opacity = 0.0;
            quit.start();
        }

        // The readiness probe, re-run every pollMs until it reports success.
        // A new Process per tick (rather than one long-lived watcher) keeps a
        // hung probe from being able to wedge the splash: the deadline still
        // fires underneath it.
        Process {
            id: ready
            command: [Quickshell.shellPath("../../../scripts/splash-ready.sh")]
            onExited: function(code) {
                if (code === 0 && Date.now() - panel.startedAt >= root.minShowMs)
                    panel.dismiss();
            }
        }

        Timer {
            id: poll
            interval: root.pollMs
            repeat: true
            onTriggered: if (!ready.running) ready.running = true
        }

        Timer {
            id: hold
            interval: root.holdMs - root.fadeMs
            repeat: false
            onTriggered: panel.dismiss()
        }

        // Unmap the surface before asking the engine to exit, and in that
        // order: tearing down the ffmpeg decoder blocks for ~3.5s, so an exit
        // with the window still mapped holds a black screen over the desktop
        // for that whole time. Hiding first puts the delay after the splash is
        // already off screen; scripts/splash.sh reaps the lingering process.
        //
        // Qt.exit() rather than Qt.quit(): quickshell connects no receiver to
        // QQmlEngine::quit(), so Qt.quit() only logs a warning and never exits.
        Timer {
            id: quit
            interval: root.fadeMs
            repeat: false
            onTriggered: {
                player.stop();
                player.source = "";
                panel.visible = false;
                Qt.exit(0);
            }
        }
    }
}
