pragma Singleton
import QtQuick
import Quickshell

// One animation driver for the Media Player visualizer. The widget is
// instantiated once per monitor; each copy used to run its own 65 ms timer
// while music played. Every copy now draws the same 24 bars.
Singleton {
  id: driver

  // Flat bars until something plays
  property var visualizerHeights: Array(24).fill(4)
  property real animPhase: 0
  property bool visualizerFlat: false
  // Set by the widgets from the active MPRIS player; they all see the same one
  property bool playing: false

  // Copies that can show bars right now (visible with the visualizer enabled)
  property var wantingCopies: ({})
  readonly property bool anyWanting: Object.keys(wantingCopies).length > 0
  function setWanting(key, wants) {
    var m = Object.assign({}, wantingCopies)
    if (wants) m[key] = true
    else delete m[key]
    wantingCopies = m
  }

  // Only tick while bars can be seen and are moving: keep going while
  // playing, and once more after playback stops to flatten them, then idle.
  Timer {
    interval: 65
    running: driver.anyWanting && (driver.playing || !driver.visualizerFlat)
    repeat: true
    onRunningChanged: if (!running) driver.visualizerHeights = Array(24).fill(4)
    onTriggered: {
      driver.animPhase += 0.25
      var heights = []
      var count = 24
      var playing = driver.playing
      for (var i = 0; i < count; i++) {
        if (!playing) {
          heights.push(4)
        } else {
          var sin1 = Math.sin(driver.animPhase + i * 0.45)
          var sin2 = Math.cos(driver.animPhase * 1.3 - i * 0.3)
          var raw = (sin1 + sin2 + 2) / 4 // 0 to 1
          var pulse = (Math.sin(driver.animPhase * 2.2) + 1) * 0.15
          var h = Math.round(6 + (raw + pulse) * 46 + (Math.random() * 8))
          heights.push(Math.min(58, Math.max(6, h)))
        }
      }
      driver.visualizerHeights = heights
      driver.visualizerFlat = !playing
    }
  }
}
