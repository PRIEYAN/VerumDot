//@ pragma UseQApplication

// Spotify media card — macOS Sonoma "Now Playing".
//
// Hangs off the underside of the waybar island, under the now-playing module.
// Driven entirely by MPRIS, so it updates in place rather than being redrawn.
//
// Dismissal is a fullscreen transparent click-catcher, deliberately NOT
// HyprlandFocusGrab: the grab cleared on its own whenever anything else took
// focus (a notification, the bar repainting), which is what made the card
// close out from under you.
//
// Run:    qs -p ~/.config/hypr/apps/quickshell/spotify
// Toggle: qs -p ~/.config/hypr/apps/quickshell/spotify ipc call spotify toggle

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris

ShellRoot {
    id: root

    // ---- geometry: hangs off the waybar island ----
    readonly property int barHeight: 44        // island: 4px margin + 40px tall
    // The bar's song title starts at x=468; the card's content is inset by
    // `pad`, so this lines the album art up with the title. (The module
    // shifts a little as the app-info title beside it changes width.)
    readonly property int leftOffset: 452
    readonly property int cardWidth: 420
    readonly property int cardRadius: 20
    readonly property int pad: 16

    // ---- macOS Sonoma glass material ----
    readonly property color glass: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.60)
    readonly property color edge: Qt.rgba(1, 1, 1, 0.18)
    readonly property color raised: Qt.rgba(1, 1, 1, 0.12)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
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
    readonly property string uiFont: "Inter"
    readonly property string iconFont: "IosevkaTerm Nerd Font"

    property bool shown: false
    property real displayPosition: 0

    // Spotify's MPRIS player, or null when Spotify is not running.
    readonly property var player: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            const bus = (p.dbusName || "").toLowerCase();
            const id = (p.identity || "").toLowerCase();
            if (bus.indexOf("spotify") !== -1 || id.indexOf("spotify") !== -1) return p;
        }
        return null;
    }

    readonly property bool hasTrack: player !== null
    readonly property real trackLength: (player && player.lengthSupported && player.length > 0)
        ? player.length : 0

    function fmtTime(seconds) {
        let s = Math.max(0, Math.floor(seconds || 0));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    function resync() {
        if (player && player.positionSupported) displayPosition = player.position;
        else displayPosition = 0;
    }

    onShownChanged: if (shown) resync()

    // MPRIS players do not stream position, so interpolate locally and pull the
    // real value back once a second to correct drift.
    Timer {
        running: root.shown && root.player !== null && root.player.isPlaying
        interval: 200
        repeat: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (ticks % 5 === 0) root.resync();
            else root.displayPosition += 0.2;
        }
    }

    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged() { root.resync() }
        function onTrackChanged() { root.displayPosition = 0; root.resync() }
        function onIsPlayingChanged() { root.resync() }
    }

    IpcHandler {
        target: "spotify"
        function toggle(): void { root.shown = !root.shown }
        function open(): void { root.shown = true }
        function close(): void { root.shown = false }
        function isOpen(): bool { return root.shown }
    }

    // ---- round icon button, used for every transport control ----
    component IconButton: Rectangle {
        id: btn

        property string glyph: ""
        property int size: 34
        property int glyphSize: 16
        property bool accented: false
        property bool enabled: true
        signal clicked()

        width: size
        height: size
        radius: size / 2
        color: {
            if (!btn.enabled) return "transparent";
            if (btn.accented) return area.containsMouse ? root.accentHover : root.accent;
            return area.containsMouse ? root.raised : "transparent";
        }
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: !btn.enabled ? root.faint : (btn.accented ? root.accentFg : root.fg)
            font.family: root.iconFont
            font.pixelSize: btn.glyphSize
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    PanelWindow {
        id: panel

        visible: root.shown || card.opacity > 0.01
        color: "transparent"

        // Fullscreen so a click anywhere else dismisses. Everything outside the
        // card is fully transparent, and the layerrule's ignore_alpha keeps the
        // blur off those pixels.
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hypr-spotify"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        onVisibleChanged: if (visible) keys.forceActiveFocus()

        MouseArea {
            anchors.fill: parent
            onClicked: root.shown = false
        }

        Item {
            id: keys
            focus: true
            Keys.onEscapePressed: root.shown = false
        }

        Rectangle {
            id: card

            width: root.cardWidth
            height: body.implicitHeight + root.pad * 2
            x: root.leftOffset
            y: root.barHeight

            // Square where it meets the bar, rounded below.
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: root.cardRadius
            bottomRightRadius: root.cardRadius
            color: root.glass
            border.width: 1
            border.color: root.edge
            clip: true

            opacity: root.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            // Swallow clicks so they never reach the dismiss layer underneath.
            MouseArea { anchors.fill: parent }

            Text {
                anchors.centerIn: parent
                visible: !root.hasTrack
                text: "Spotify is not running"
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: 14
            }

            Item {
                id: body
                visible: root.hasTrack
                x: root.pad
                y: root.pad
                width: parent.width - root.pad * 2
                implicitHeight: Math.max(art.height, info.implicitHeight)

                // ---- album art ----
                Rectangle {
                    id: art
                    width: 118
                    height: 118
                    radius: 12
                    color: root.raised
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready
                        text: "󰎇"
                        color: root.faint
                        font.family: root.iconFont
                        font.pixelSize: 40
                    }

                    Image {
                        id: cover
                        anchors.fill: parent
                        source: root.player ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                    }
                }

                // ---- title / artist / progress / transport ----
                Column {
                    id: info
                    anchors.left: art.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 5

                    Text {
                        width: parent.width
                        text: root.player ? root.player.trackTitle : ""
                        color: root.fg
                        font.family: root.uiFont
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.player ? root.player.trackArtist : ""
                        color: root.muted
                        font.family: root.uiFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: root.player ? (root.player.trackAlbum || "") : ""
                        color: root.faint
                        font.family: root.uiFont
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Item { width: 1; height: 3 }

                    // Progress. Click or drag anywhere on it to seek.
                    Item {
                        width: parent.width
                        height: 14

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.18)

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                color: root.fg
                                width: root.trackLength > 0
                                    ? parent.width * Math.min(1, Math.max(0, root.displayPosition / root.trackLength))
                                    : 0
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.player !== null && root.player.canSeek && root.trackLength > 0
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: mouse => seekTo(mouse.x)
                            onPositionChanged: mouse => { if (pressed) seekTo(mouse.x) }

                            function seekTo(x) {
                                const frac = Math.min(1, Math.max(0, x / width));
                                const target = frac * root.trackLength;
                                root.displayPosition = target;
                                root.player.position = target;
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: elapsed.height

                        Text {
                            id: elapsed
                            anchors.left: parent.left
                            text: root.fmtTime(root.displayPosition)
                            color: root.faint
                            font.family: root.uiFont
                            font.pixelSize: 11
                        }

                        Text {
                            anchors.right: parent.right
                            text: "-" + root.fmtTime(Math.max(0, root.trackLength - root.displayPosition))
                            color: root.faint
                            font.family: root.uiFont
                            font.pixelSize: 11
                        }
                    }

                    // ---- transport: shuffle | prev | play/pause | next | repeat ----
                    Item {
                        width: parent.width
                        height: 40

                        IconButton {
                            id: shuffleBtn
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            size: 28
                            glyphSize: 13
                            enabled: root.player !== null && root.player.shuffleSupported
                            glyph: (root.player && root.player.shuffle) ? "󰒝" : "󰒞"
                            accented: root.player !== null && root.player.shuffle
                            onClicked: root.player.shuffle = !root.player.shuffle
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            IconButton {
                                glyph: "󰒮"
                                size: 32
                                glyphSize: 17
                                enabled: root.player !== null && root.player.canGoPrevious
                                onClicked: { root.player.previous(); root.resync() }
                            }

                            IconButton {
                                glyph: (root.player && root.player.isPlaying) ? "󰏤" : "󰐊"
                                size: 40
                                glyphSize: 20
                                accented: true
                                enabled: root.player !== null && root.player.canTogglePlaying
                                onClicked: { root.player.togglePlaying(); root.resync() }
                            }

                            IconButton {
                                glyph: "󰒭"
                                size: 32
                                glyphSize: 17
                                enabled: root.player !== null && root.player.canGoNext
                                onClicked: { root.player.next(); root.resync() }
                            }
                        }

                        IconButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            size: 28
                            glyphSize: 13
                            enabled: root.player !== null && root.player.loopSupported
                            glyph: {
                                if (!root.player) return "󰑗";
                                switch (root.player.loopState) {
                                case MprisLoopState.Track:    return "󰑘";
                                case MprisLoopState.Playlist: return "󰑖";
                                default:                      return "󰑗";
                                }
                            }
                            accented: root.player !== null
                                && root.player.loopState !== MprisLoopState.None
                            onClicked: {
                                // None -> Playlist -> Track -> None
                                const s = root.player.loopState;
                                if (s === MprisLoopState.None) root.player.loopState = MprisLoopState.Playlist;
                                else if (s === MprisLoopState.Playlist) root.player.loopState = MprisLoopState.Track;
                                else root.player.loopState = MprisLoopState.None;
                            }
                        }
                    }
                }
            }
        }
    }
}
