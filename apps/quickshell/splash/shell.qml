import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Core

ShellRoot {
  anchors.fill: screen
  color: "black"

  PopupWindow {
    id: splashWindow
    anchors.fill: screen

    WlrLayershell.layer: "overlay"
    WlrLayershell.namespace: "hypr-splash"

    color: "#000000"
    flags: Qt.FramelessWindowHint
    opacity: 1.0

    Rectangle {
      anchors.fill: parent
      color: "#000000"

      MediaPlayer {
        id: videoPlayer
        source: "file://" + StandardPaths.configLocation + "/hypr/assets/splash.mp4"
        videoOutput: videoOutput
        autoPlay: true

        onStatusChanged: {
          if (status === MediaPlayer.LoadedMedia) {
            console.log("Video loaded, playing...")
          }
        }
      }

      VideoOutput {
        id: videoOutput
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        fillMode: VideoOutput.PreserveAspectFit
      }
    }

    Timer {
      id: closeTimer
      interval: 1000
      running: true
      repeat: false

      onTriggered: {
        console.log("Splash timeout, closing...")
        splashWindow.close()
      }
    }
  }
}
