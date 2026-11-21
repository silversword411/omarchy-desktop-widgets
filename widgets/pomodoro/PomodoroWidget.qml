import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import qs.Commons
// Qt 6.12 adds a QtQuick "Color" singleton that wins over qs.Commons.Color in
// these subfolder widgets; reference the shell colours through an alias.
import qs.Commons as Commons
import qs.Ui

// Import base WidgetCard from the shared repository link or parent widgets directory
import "../../shared"
import ".."
import "."

WidgetCard {
  id: pomodoroWidgetRoot

  // ---------------------------------------------------------------------------
  // 🏷️ Identity & Placement Settings
  // ---------------------------------------------------------------------------
  widgetId: "pomodoro"
  title: "Flow State Pomodoro"
  icon: "\uf252"
  showHeader: false // Custom integrated header with session indicators & grips

  defaultX: screenWidth - width - Style.space(24)
  defaultY: screenHeight - height - Style.space(64)

  width: 320
  height: 410
  minWidth: 260
  minHeight: 280

  // Controls and text shrink with the widget so everything stays visible at
  // the minimum size; the progress ring takes whatever height is left.
  readonly property real uiScale: Math.max(0.6, Math.min(1, Math.min(width / 320, height / 410)))
  function sc(v) { return Math.round(v * uiScale) }

  // ---------------------------------------------------------------------------
  // ⏱️ Pomodoro State & Durations
  // ---------------------------------------------------------------------------
  // Shared with every other copy and the bar pill, see PomodoroStore.qml
  readonly property string currentMode: PomodoroStore.currentMode
  readonly property bool isTimerRunning: PomodoroStore.isTimerRunning
  readonly property int focusDurationSec: PomodoroStore.focusDurationSec
  readonly property int shortDurationSec: PomodoroStore.shortDurationSec
  readonly property int longDurationSec: PomodoroStore.longDurationSec
  readonly property int totalSeconds: PomodoroStore.totalSeconds
  readonly property int secondsLeft: PomodoroStore.secondsLeft
  readonly property int completedSessions: PomodoroStore.completedSessions
  readonly property int cycleStep: PomodoroStore.cycleStep
  readonly property string activePreset: PomodoroStore.activePreset
  readonly property bool soundAlerts: PomodoroStore.soundAlerts
  readonly property bool showNotifications: PomodoroStore.showNotifications
  menuWidth: 320

  function applyPreset(preset) { PomodoroStore.applyPreset(preset) }

  customMenuContent: Component {
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(3)

      Text {
        text: "INTERVAL PRESETS"
        font.family: Style.font.family
        font.pixelSize: 9
        font.weight: Font.Bold
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
        Layout.leftMargin: 4
        Layout.topMargin: 2
      }

      Repeater {
        model: [
          { id: "25/5", label: "Standard: 25m Focus / 5m Break", icon: "\uf252" },
          { id: "50/10", label: "Deep Work: 50m Focus / 10m Break", icon: "\uf0e7" },
          { id: "15/3", label: "Sprint: 15m Focus / 3m Break", icon: "\uf135" }
        ]

        Rectangle {
          required property var modelData
          Layout.fillWidth: true
          implicitHeight: 28
          radius: 6
          readonly property bool isSelected: pomodoroWidgetRoot.activePreset === modelData.id
          color: pMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : (isSelected ? pomodoroWidgetRoot.fgTint(0.08) : "transparent")

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              text: modelData.icon
              font.family: Style.font.family
              font.pixelSize: 11
              color: isSelected ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
            }

            Text {
              Layout.fillWidth: true
              text: modelData.label
              font.family: Style.font.family
              font.pixelSize: 11
              font.weight: isSelected ? Font.Bold : Font.Normal
              color: isSelected ? Commons.Color.foreground : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.8)
              elide: Text.ElideRight
            }

            Text {
              visible: isSelected
              text: "\uf00c"
              font.family: Style.font.family
              font.pixelSize: 10
              color: Commons.Color.accent
            }
          }

          MouseArea {
            id: pMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pomodoroWidgetRoot.applyPreset(modelData.id)
          }
        }
      }

      Text {
        text: "ALERTS & NOTIFICATIONS"
        font.family: Style.font.family
        font.pixelSize: 9
        font.weight: Font.Bold
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
        Layout.leftMargin: 4
        Layout.topMargin: 4
      }

      // Play Sound Chimes Toggle
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: sndMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: pomodoroWidgetRoot.soundAlerts ? "\uf028" : "\uf6a9"
            font.family: Style.font.family
            font.pixelSize: 11
            color: pomodoroWidgetRoot.soundAlerts ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
          }

          Text {
            Layout.fillWidth: true
            text: "Completion Audio Chimes"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }

          Text {
            text: pomodoroWidgetRoot.soundAlerts ? "\uf14a" : "\uf0c8"
            font.family: Style.font.family
            font.pixelSize: 12
            color: pomodoroWidgetRoot.soundAlerts ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.4)
          }
        }

        MouseArea {
          id: sndMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: PomodoroStore.soundAlerts = !PomodoroStore.soundAlerts
        }
      }

      // Desktop Notification Banners Toggle
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: notifMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf0f3"
            font.family: Style.font.family
            font.pixelSize: 11
            color: pomodoroWidgetRoot.showNotifications ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
          }

          Text {
            Layout.fillWidth: true
            text: "Desktop Notification Banners"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }

          Text {
            text: pomodoroWidgetRoot.showNotifications ? "\uf14a" : "\uf0c8"
            font.family: Style.font.family
            font.pixelSize: 12
            color: pomodoroWidgetRoot.showNotifications ? Commons.Color.accent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.4)
          }
        }

        MouseArea {
          id: notifMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: PomodoroStore.showNotifications = !PomodoroStore.showNotifications
        }
      }

      Text {
        text: "SESSION MANAGEMENT"
        font.family: Style.font.family
        font.pixelSize: 9
        font.weight: Font.Bold
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
        Layout.leftMargin: 4
        Layout.topMargin: 4
      }

      // Restart Current Timer Action
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: restartMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf2f9"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.accent
          }

          Text {
            Layout.fillWidth: true
            text: "Restart Current Interval"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }
        }

        MouseArea {
          id: restartMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            pomodoroWidgetRoot.contextMenuOpen = false
            pomodoroWidgetRoot.resetCurrentTimer()
          }
        }
      }

      // Reset Streak Action
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: resetStreakMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf0e2"
            font.family: Style.font.family
            font.pixelSize: 11
            color: resetStreakMouse.containsMouse ? Commons.Color.urgent : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
          }

          Text {
            Layout.fillWidth: true
            text: "Reset Completed Sessions Streak"
            font.family: Style.font.family
            font.pixelSize: 11
            color: resetStreakMouse.containsMouse ? Commons.Color.urgent : Commons.Color.foreground
          }
        }

        MouseArea {
          id: resetStreakMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            pomodoroWidgetRoot.contextMenuOpen = false
            pomodoroWidgetRoot.completedSessions = 0
            pomodoroWidgetRoot.cycleStep = 1
          }
        }
      }
    }
  }

  readonly property color modeColor: {
    if (currentMode === "SHORT") return "#10b981" // Emerald Mint
    if (currentMode === "LONG") return "#06b6d4"  // Electric Cyan
    return Commons.Color.accent                           // Theme Accent / Focus Red
  }

  readonly property string modeTitle: PomodoroStore.modeTitle
  readonly property real progressFraction: PomodoroStore.progressFraction

  function formatTime(secs) { return PomodoroStore.formatTime(secs) }
  function setMode(mode, autoStart) { PomodoroStore.setMode(mode, autoStart) }
  function togglePlayPause() { PomodoroStore.togglePlayPause() }
  function resetCurrentTimer() { PomodoroStore.resetCurrentTimer() }
  function skipToNextSession() { PomodoroStore.skipToNextSession() }

  // The arc is a Canvas: repaint when the shared countdown moves, only while shown
  onSecondsLeftChanged: if (visible) progressArc.requestPaint()
  onTotalSecondsChanged: if (visible) progressArc.requestPaint()

  // The ticker skips repaints while hidden; catch the arc up when shown again
  onVisibleChanged: if (visible) progressArc.requestPaint()

  // The ring track is painted once, so repaint it when the theme foreground changes
  Connections {
    target: Commons.Color
    function onForegroundChanged() { trackCanvas.requestPaint() }
  }

  // ---------------------------------------------------------------------------
  // 🎨 Widget Body & Controls
  // ---------------------------------------------------------------------------
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: pomodoroWidgetRoot.sc(Style.space(16))
    spacing: pomodoroWidgetRoot.sc(Style.space(12))

    // -------------------------------------------------------------------------
    // 🏷️ Top Header: Icon, Title & Edit/Move Controls
    // -------------------------------------------------------------------------
    RowLayout {
      Layout.fillWidth: true
      spacing: pomodoroWidgetRoot.sc(Style.space(8))

      Rectangle {
        width: pomodoroWidgetRoot.sc(30)
        height: pomodoroWidgetRoot.sc(30)
        radius: pomodoroWidgetRoot.sc(15)
        color: Qt.rgba(pomodoroWidgetRoot.modeColor.r, pomodoroWidgetRoot.modeColor.g, pomodoroWidgetRoot.modeColor.b, 0.2)
        border.color: Qt.rgba(pomodoroWidgetRoot.modeColor.r, pomodoroWidgetRoot.modeColor.g, pomodoroWidgetRoot.modeColor.b, 0.45)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "\uf252"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(13)
          color: pomodoroWidgetRoot.modeColor
        }
      }

      ColumnLayout {
        spacing: pomodoroWidgetRoot.sc(0)
        Text {
          text: "Flow Pomodoro"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(13)
          font.weight: Font.Bold
          color: Commons.Color.foreground
        }
        Text {
          text: pomodoroWidgetRoot.modeTitle + " · Step " + pomodoroWidgetRoot.cycleStep + " of 4"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(10)
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
        }
      }

      Item { Layout.fillWidth: true }

      // Close Button (Edit Mode)
      Rectangle {
        visible: rootRef && rootRef.layoutEditMode
        width: pomodoroWidgetRoot.sc(22)
        height: pomodoroWidgetRoot.sc(22)
        radius: pomodoroWidgetRoot.sc(11)
        color: closeMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.35) : pomodoroWidgetRoot.fgTint(0.08)
        border.color: Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.5)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "\uf00d"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(10)
          color: Commons.Color.urgent
        }

        MouseArea {
          id: closeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (rootRef && rootRef.toggleWidgetEnabled) {
              rootRef.toggleWidgetEnabled(pomodoroWidgetRoot.widgetId, false, pomodoroWidgetRoot.monitorName)
            }
          }
        }
      }

      // Move Grip Button (Edit Mode)
      Rectangle {
        visible: rootRef && rootRef.layoutEditMode
        width: pomodoroWidgetRoot.sc(22)
        height: pomodoroWidgetRoot.sc(22)
        radius: pomodoroWidgetRoot.sc(11)
        color: customGripMouse.drag.active ? Commons.Color.accent : (customGripMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35) : pomodoroWidgetRoot.fgTint(0.08))
        border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.5)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "\uf0b2"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(10)
          color: customGripMouse.drag.active ? Commons.Color.background : Commons.Color.accent
        }

        MouseArea {
          id: customGripMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.SizeAllCursor
          drag.target: targetItem
          drag.axis: Drag.XAndYAxis
          drag.minimumX: 10
          drag.maximumX: screenWidth - pomodoroWidgetRoot.width - 10
          drag.minimumY: 10
          drag.maximumY: screenHeight - pomodoroWidgetRoot.height - 10
          onPressed: pomodoroWidgetRoot.customGripDragging = true
          onReleased: {
            pomodoroWidgetRoot.customGripDragging = false
            if (rootRef && rootRef.saveWidgetPos) {
              rootRef.saveWidgetPos(pomodoroWidgetRoot.widgetId, Math.round(targetItem.x), Math.round(targetItem.y), Math.round(pomodoroWidgetRoot.width), Math.round(pomodoroWidgetRoot.height), pomodoroWidgetRoot.monitorName)
            }
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // 🔘 Mode Selector Pills
    // -------------------------------------------------------------------------
    RowLayout {
      Layout.fillWidth: true
      spacing: pomodoroWidgetRoot.sc(Style.space(6))

      Repeater {
        model: [
          { mode: "FOCUS", label: "Focus 25m", color: Commons.Color.accent },
          { mode: "SHORT", label: "Short 5m", color: "#10b981" },
          { mode: "LONG", label: "Long 15m", color: "#06b6d4" }
        ]

        Rectangle {
          required property var modelData
          Layout.fillWidth: true
          height: pomodoroWidgetRoot.sc(26)
          radius: pomodoroWidgetRoot.sc(13)
          readonly property bool isSelected: pomodoroWidgetRoot.currentMode === modelData.mode
          color: isSelected ? Qt.rgba(modelData.color.r, modelData.color.g, modelData.color.b, 0.28) : (modePillMouse.containsMouse ? pomodoroWidgetRoot.fgTint(0.08) : pomodoroWidgetRoot.fgTint(0.03))
          border.color: isSelected ? modelData.color : pomodoroWidgetRoot.fgTint(0.1)
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: modelData.label
            font.family: Style.font.family
            font.pixelSize: pomodoroWidgetRoot.sc(10)
            font.weight: isSelected ? Font.Bold : Font.Normal
            color: isSelected ? modelData.color : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.75)
          }

          MouseArea {
            id: modePillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pomodoroWidgetRoot.setMode(modelData.mode, false)
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // ⭕ Circular Progress Ring & Time Readout
    // -------------------------------------------------------------------------
    Item {
      id: ringArea
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 70

      readonly property real ringSize: Math.max(60, Math.min(width, height, 190))
      readonly property real ringStroke: Math.max(4, Math.round(10 * ringSize / 190))
      readonly property real timeFontSize: Math.max(14, Math.round(32 * ringSize / 190))

      Item {
        id: ringBox
        anchors.centerIn: parent
        width: ringArea.ringSize
        height: ringArea.ringSize
        onWidthChanged: { trackCanvas.requestPaint(); progressArc.requestPaint() }

        // Static Background Ring Track
        Canvas {
          id: trackCanvas
          anchors.fill: parent
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var c = width / 2
            var r = c - ringArea.ringStroke
            ctx.lineWidth = ringArea.ringStroke
            ctx.strokeStyle = pomodoroWidgetRoot.fgTint(0.08)
            ctx.beginPath()
            ctx.arc(c, c, r, 0, Math.PI * 2)
            ctx.stroke()
          }
        }

        // Dynamic Active Progress Arc
        Canvas {
          id: progressArc
          anchors.fill: parent
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var c = width / 2
            var r = c - ringArea.ringStroke
            var progress = pomodoroWidgetRoot.progressFraction

            if (progress > 0) {
              ctx.lineWidth = ringArea.ringStroke
              ctx.lineCap = "round"
              ctx.strokeStyle = pomodoroWidgetRoot.modeColor
              ctx.beginPath()
              ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + (Math.PI * 2 * progress))
              ctx.stroke()
            }
          }
        }

        // Center Time & Label Stack
        ColumnLayout {
          anchors.centerIn: parent
          spacing: pomodoroWidgetRoot.sc(2)

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: pomodoroWidgetRoot.formatTime(pomodoroWidgetRoot.secondsLeft)
            font.family: "Monospace"
            font.pixelSize: ringArea.timeFontSize
            font.weight: Font.Bold
            color: Commons.Color.foreground
          }

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: pomodoroWidgetRoot.sc(5)

            Rectangle {
              width: pomodoroWidgetRoot.sc(6)
              height: pomodoroWidgetRoot.sc(6)
              radius: pomodoroWidgetRoot.sc(3)
              color: pomodoroWidgetRoot.isTimerRunning ? pomodoroWidgetRoot.modeColor : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.3)
              Behavior on color { ColorAnimation { duration: 200 } }
            }

            Text {
              text: pomodoroWidgetRoot.isTimerRunning ? pomodoroWidgetRoot.currentMode : "PAUSED"
              font.family: Style.font.family
              font.pixelSize: pomodoroWidgetRoot.sc(10)
              font.weight: Font.Bold
              color: pomodoroWidgetRoot.isTimerRunning ? pomodoroWidgetRoot.modeColor : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
            }
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // 🎮 Controls: Reset, Play/Pause, Skip
    // -------------------------------------------------------------------------
    RowLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      spacing: pomodoroWidgetRoot.sc(Style.space(12))

      Item { Layout.fillWidth: true }

      // Reset Button
      Rectangle {
        width: pomodoroWidgetRoot.sc(36)
        height: pomodoroWidgetRoot.sc(36)
        radius: pomodoroWidgetRoot.sc(18)
        color: resetMouse.containsMouse ? pomodoroWidgetRoot.fgTint(0.15) : pomodoroWidgetRoot.fgTint(0.06)
        border.color: pomodoroWidgetRoot.fgTint(0.12)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "\uf0e2"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(13)
          color: Commons.Color.foreground
        }

        MouseArea {
          id: resetMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: pomodoroWidgetRoot.resetCurrentTimer()
        }
      }

      // Primary Start / Pause Pill Button
      Rectangle {
        implicitWidth: playPillRow.implicitWidth + pomodoroWidgetRoot.sc(28)
        implicitHeight: pomodoroWidgetRoot.sc(38)
        radius: pomodoroWidgetRoot.sc(19)
        color: playMouse.containsMouse ? Qt.lighter(pomodoroWidgetRoot.modeColor, 1.15) : pomodoroWidgetRoot.modeColor

        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Qt.rgba(pomodoroWidgetRoot.modeColor.r, pomodoroWidgetRoot.modeColor.g, pomodoroWidgetRoot.modeColor.b, 0.5)
          shadowBlur: 0.6
          shadowVerticalOffset: 2
        }

        RowLayout {
          id: playPillRow
          anchors.centerIn: parent
          spacing: pomodoroWidgetRoot.sc(Style.space(6))

          Text {
            text: pomodoroWidgetRoot.isTimerRunning ? "\uf04c" : "\uf04b"
            font.family: Style.font.family
            font.pixelSize: pomodoroWidgetRoot.sc(12)
            color: Commons.Color.background
          }

          Text {
            text: pomodoroWidgetRoot.isTimerRunning ? "Pause" : (pomodoroWidgetRoot.secondsLeft < pomodoroWidgetRoot.totalSeconds ? "Resume" : "Start " + (pomodoroWidgetRoot.currentMode === "FOCUS" ? "Focus" : "Break"))
            font.family: Style.font.family
            font.pixelSize: pomodoroWidgetRoot.sc(12)
            font.weight: Font.Bold
            color: Commons.Color.background
          }
        }

        MouseArea {
          id: playMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: pomodoroWidgetRoot.togglePlayPause()
        }
      }

      // Skip Button
      Rectangle {
        width: pomodoroWidgetRoot.sc(36)
        height: pomodoroWidgetRoot.sc(36)
        radius: pomodoroWidgetRoot.sc(18)
        color: skipMouse.containsMouse ? pomodoroWidgetRoot.fgTint(0.15) : pomodoroWidgetRoot.fgTint(0.06)
        border.color: pomodoroWidgetRoot.fgTint(0.12)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "\uf051"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(13)
          color: Commons.Color.foreground
        }

        MouseArea {
          id: skipMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: pomodoroWidgetRoot.skipToNextSession()
        }
      }

      Item { Layout.fillWidth: true }
    }

    // -------------------------------------------------------------------------
    // 🍅 Cycle Step Dots & Daily Sessions Streak
    // -------------------------------------------------------------------------
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: pomodoroWidgetRoot.sc(Style.space(4))

      // 4 Cycle Dots
      RowLayout {
        spacing: pomodoroWidgetRoot.sc(5)

        Repeater {
          model: 4
          Rectangle {
            required property int index
            width: pomodoroWidgetRoot.sc(8)
            height: pomodoroWidgetRoot.sc(8)
            radius: pomodoroWidgetRoot.sc(4)
            color: (index + 1) <= pomodoroWidgetRoot.cycleStep ? pomodoroWidgetRoot.modeColor : pomodoroWidgetRoot.fgTint(0.15)
            border.color: (index + 1) === pomodoroWidgetRoot.cycleStep ? Qt.lighter(pomodoroWidgetRoot.modeColor, 1.3) : "transparent"
            border.width: 1
          }
        }
      }

      Item { Layout.fillWidth: true }

      // Streak Tally Badge
      RowLayout {
        spacing: pomodoroWidgetRoot.sc(4)
        Text {
          text: "\uf06d"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(10)
          color: "#f59e0b" // Amber flame
        }
        Text {
          text: pomodoroWidgetRoot.completedSessions + (pomodoroWidgetRoot.completedSessions === 1 ? " session" : " sessions") + " completed"
          font.family: Style.font.family
          font.pixelSize: pomodoroWidgetRoot.sc(10)
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.65)
        }
      }
    }
  }
}
