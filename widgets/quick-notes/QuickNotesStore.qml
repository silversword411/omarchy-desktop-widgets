pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One copy of the Quick Notes data for every monitor's widget. The widget is
// instantiated once per monitor; before this store each copy loaded the data,
// ran its own notes_manager.py process and watched the Obsidian note, so a
// change made in Obsidian was imported (and logged) once per monitor.
Singleton {
  id: store

  property var todosList: []
  property string scratchpadText: ""
  property var commandsList: []
  // {name, color}; color is "accent", "urgent", "foreground" or #rrggbb
  property var tagsList: [
    { name: "#todo", color: "foreground" },
    { name: "#work", color: "accent" },
    { name: "#idea", color: "#ffcc40" },
    { name: "#bug", color: "urgent" }
  ]
  property var loggingConfig: ({ obsidian_enabled: false, obsidian_folder: "", event_log_enabled: false })
  property string tasksNoteName: "Quick Notes Tasks.md"
  property string logNoteName: "Quick Notes Log.md"

  readonly property string notesManagerPath: Qt.resolvedUrl("notes_manager.py").toString().replace(/^file:\/\//, "")

  // Two-way sync: watch the Obsidian task note and import edits made there.
  readonly property string obsidianTasksPath: (loggingConfig.obsidian_enabled === true && loggingConfig.obsidian_folder)
    ? (loggingConfig.obsidian_folder.replace(/^~/, Quickshell.env("HOME")) + "/" + tasksNoteName) : ""

  FileView {
    path: store.obsidianTasksPath
    watchChanges: true
    printErrors: false
    // Our own writes also fire this; the import is a no-op when nothing differs.
    onFileChanged: obsidianImportDebounce.restart()
  }

  Timer {
    id: obsidianImportDebounce
    interval: 400
    repeat: false
    onTriggered: store.runAction(["import_obsidian"])
  }

  Process {
    id: notesProc
    command: [store.notesManagerPath, "load"]
    running: true
    onExited: store.runNextAction()
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var res = JSON.parse(String(line).trim())
          if (res.todos !== undefined) store.todosList = res.todos
          if (res.scratchpad !== undefined) store.scratchpadText = res.scratchpad
          if (res.commands !== undefined) store.commandsList = res.commands
          if (res.logging !== undefined) store.loggingConfig = res.logging
          if (res.tasks_note !== undefined) store.tasksNoteName = res.tasks_note
          if (res.log_note !== undefined) store.logNoteName = res.log_note
          if (res.tags !== undefined && res.tags.length > 0) store.tagsList = res.tags
        } catch (e) {}
      }
    }
  }

  // Actions run one at a time: a second action while one is still writing is
  // queued, not started over the top of it.
  property var actionQueue: []

  function runAction(args) {
    var cmd = [store.notesManagerPath].concat(args)
    if (notesProc.running) {
      actionQueue.push(cmd)
      return
    }
    notesProc.command = cmd
    notesProc.running = true
  }

  function runNextAction() {
    if (notesProc.running || actionQueue.length === 0) return
    notesProc.command = actionQueue.shift()
    notesProc.running = true
  }
}
