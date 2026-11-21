pragma Singleton
import QtQuick
import Quickshell

// One pomodoro for the whole shell. The desktop widget is instantiated once
// per monitor and the bar pill once per bar; each used to run its own timer
// and its own session, so a session started on one monitor did not exist on
// the others. Everything here is shared; the widgets only draw it.
Singleton {
  id: store

  property string currentMode: "FOCUS" // "FOCUS" | "SHORT" | "LONG"
  property bool isTimerRunning: false

  property int focusDurationSec: 25 * 60
  property int shortDurationSec: 5 * 60
  property int longDurationSec: 15 * 60

  property int totalSeconds: focusDurationSec
  property int secondsLeft: focusDurationSec

  property int completedSessions: 0
  property int cycleStep: 1 // 1..4
  property string activePreset: "25/5"
  property bool soundAlerts: true
  property bool showNotifications: true

  readonly property string modeTitle: currentMode === "SHORT" ? "Short Break" : (currentMode === "LONG" ? "Long Break" : "Deep Focus")
  readonly property real progressFraction: totalSeconds <= 0 ? 0 : Math.max(0.0, Math.min(1.0, 1.0 - (secondsLeft / totalSeconds)))

  function formatTime(secs) {
    var m = Math.floor(secs / 60)
    var s = secs % 60
    return (m < 10 ? "0" + m : m.toString()) + ":" + (s < 10 ? "0" + s : s.toString())
  }

  function applyPreset(preset) {
    activePreset = preset
    if (preset === "25/5") {
      focusDurationSec = 25 * 60; shortDurationSec = 5 * 60; longDurationSec = 15 * 60
    } else if (preset === "50/10") {
      focusDurationSec = 50 * 60; shortDurationSec = 10 * 60; longDurationSec = 20 * 60
    } else if (preset === "15/3") {
      focusDurationSec = 15 * 60; shortDurationSec = 3 * 60; longDurationSec = 10 * 60
    }
    setMode(currentMode, false)
  }

  function setMode(mode, autoStart) {
    currentMode = mode
    isTimerRunning = autoStart ? true : false
    if (mode === "FOCUS") totalSeconds = focusDurationSec
    else if (mode === "SHORT") totalSeconds = shortDurationSec
    else if (mode === "LONG") totalSeconds = longDurationSec
    secondsLeft = totalSeconds
  }

  function togglePlayPause() { isTimerRunning = !isTimerRunning }

  function resetCurrentTimer() {
    isTimerRunning = false
    secondsLeft = totalSeconds
  }

  function skipToNextSession() {
    isTimerRunning = false
    if (currentMode === "FOCUS") {
      completedSessions++
      if (cycleStep >= 4) { cycleStep = 1; setMode("LONG", false) }
      else { cycleStep++; setMode("SHORT", false) }
    } else {
      setMode("FOCUS", false)
    }
  }

  function onSessionFinished() {
    isTimerRunning = false
    if (currentMode === "FOCUS") {
      completedSessions++
      if (showNotifications) Quickshell.execDetached(["notify-send", "-i", "appointment-soon", "🍅 Focus Session Complete!", "Great job! Take a well-deserved break."])
      if (soundAlerts) Quickshell.execDetached(["bash", "-c", "paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null"])
      if (cycleStep >= 4) { cycleStep = 1; setMode("LONG", true) }
      else { cycleStep++; setMode("SHORT", true) }
    } else {
      if (showNotifications) Quickshell.execDetached(["notify-send", "-i", "appointment-soon", "⚡ Break Finished!", "Time to dive back into flow state."])
      if (soundAlerts) Quickshell.execDetached(["bash", "-c", "paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null"])
      setMode("FOCUS", true)
    }
  }

  // The one countdown ticker
  Timer {
    interval: 1000
    repeat: true
    running: store.isTimerRunning
    onTriggered: {
      if (store.secondsLeft > 1) store.secondsLeft--
      else { store.secondsLeft = 0; store.onSessionFinished() }
    }
  }
}
