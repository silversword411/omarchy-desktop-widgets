import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "."

Item {
  id: root

  property var bar: null

  // Shared with the desktop widget, see PomodoroStore.qml
  readonly property string currentMode: PomodoroStore.currentMode
  readonly property bool isTimerRunning: PomodoroStore.isTimerRunning
  readonly property int secondsLeft: PomodoroStore.secondsLeft

  readonly property color modeColor: {
    if (currentMode === "SHORT") return "#10b981"
    if (currentMode === "LONG") return "#06b6d4"
    return Commons.Color.accent
  }

  function formatTime(totalSec) { return PomodoroStore.formatTime(totalSec) }
  function toggleRunning() { PomodoroStore.togglePlayPause() }
  function resetTimer() { PomodoroStore.resetCurrentTimer() }
  function cycleMode() { PomodoroStore.skipToNextSession() }

  // Blinks the icon in step with the countdown text, no animation loop needed
  readonly property bool tickPhase: secondsLeft % 2 === 0

  implicitWidth: pillContainer.implicitWidth
  implicitHeight: Style.bar.statusSlot || 32

  Rectangle {
    id: pillContainer
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: Math.min(parent.height - 4, 28)
    implicitWidth: rowLayout.implicitWidth + 16
    radius: Style.cornerRadius || 8
    color: mouseArea.containsMouse ? Qt.rgba(root.modeColor.r, root.modeColor.g, root.modeColor.b, 0.22) : Qt.rgba(Commons.Color.bar.background.r, Commons.Color.bar.background.g, Commons.Color.bar.background.b, 0.65)
    border.color: root.isTimerRunning ? root.modeColor : Util.alpha(Commons.Color.foreground, 0.12)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    RowLayout {
      id: rowLayout
      anchors.centerIn: parent
      spacing: 6

      // Blinking Icon (while running)
      Text {
        text: "\uf252"
        font.family: Style.font.family
        font.pixelSize: 11
        color: root.modeColor
        opacity: root.isTimerRunning && root.tickPhase ? 0.4 : 1.0
      }

      // Countdown Text
      Text {
        text: root.formatTime(root.secondsLeft)
        font.family: Style.font.family
        font.pixelSize: 11
        font.weight: Font.Bold
        color: Commons.Color.foreground
      }

      // Small Play/Pause Indicator
      Text {
        text: root.isTimerRunning ? "\uf04c" : "\uf04b"
        font.family: Style.font.family
        font.pixelSize: 9
        color: root.isTimerRunning ? root.modeColor : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      onClicked: function(mouse) {
        if (mouse.button === Qt.LeftButton) {
          root.toggleRunning()
        } else if (mouse.button === Qt.RightButton) {
          root.cycleMode()
        }
      }
    }
  }
}
