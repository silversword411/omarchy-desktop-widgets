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
  id: notesWidgetRoot

  // ---------------------------------------------------------------------------
  // 🏷️ Identity & Placement Settings
  // ---------------------------------------------------------------------------
  widgetId: "quick_notes"
  title: "Scratchpad & Tasks"
  icon: "\uf044"
  showHeader: false // Custom integrated header for tabs & counters

  defaultX: Style.space(24)
  defaultY: 320

  width: 380
  height: 440
  minWidth: 320
  minHeight: 280

  // ---------------------------------------------------------------------------
  // 📂 Data State & Backend Process
  // ---------------------------------------------------------------------------
  property string currentTab: "TASKS" // "TASKS" | "SCRATCHPAD" | "COMMANDS"
  // Shared across the per-monitor copies, see QuickNotesStore.qml
  readonly property var todosList: QuickNotesStore.todosList
  readonly property string scratchpadText: QuickNotesStore.scratchpadText
  readonly property var commandsList: QuickNotesStore.commandsList
  property string currentTag: "#todo"
  readonly property var tagsList: QuickNotesStore.tagsList
  readonly property var availableTags: tagsList.map(function(t) { return t.name })

  // The chosen tag must exist; after a reload or a rename pick the first one.
  function ensureCurrentTag() {
    // availableTags is not built yet when this first fires during construction
    if (!tagsList || tagsList.length === 0 || !availableTags) return
    if (availableTags.indexOf(currentTag) === -1) currentTag = tagsList[0].name
  }
  onTagsListChanged: ensureCurrentTag()
  Component.onCompleted: {
    ensureCurrentTag()
    if (scratchpadEdit.text !== scratchpadText) scratchpadEdit.text = scratchpadText
  }
  onScratchpadTextChanged: if (scratchpadEdit.text !== scratchpadText && !scratchpadEdit.activeFocus) scratchpadEdit.text = scratchpadText

  function tagColor(name) {
    var c = "foreground"
    for (var i = 0; i < tagsList.length; i++) {
      if (tagsList[i].name === name) { c = tagsList[i].color; break }
    }
    if (c === "accent") return Commons.Color.accent
    if (c === "urgent") return Commons.Color.urgent
    if (c === "foreground") return Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.7)
    return Qt.color(c)
  }

  function tagTint(name, alpha) {
    var c = tagColor(name)
    return Qt.rgba(c.r, c.g, c.b, alpha)
  }

  // Logging (card menu): Obsidian Tasks export + optional event log
  readonly property var loggingConfig: QuickNotesStore.loggingConfig
  readonly property string tasksNoteName: QuickNotesStore.tasksNoteName
  readonly property string logNoteName: QuickNotesStore.logNoteName
  property bool loggingOpen: false

  function saveLogging(cfg) {
    QuickNotesStore.loggingConfig = cfg
    runAction(["save_logging", JSON.stringify(cfg)])
  }

  function setLoggingField(key, value) {
    var cfg = Object.assign({}, loggingConfig)
    cfg[key] = value
    saveLogging(cfg)
  }

  // Tag editor (Manage Tags in the card menu)
  property bool tagEditorOpen: false
  property int tagColorEditIndex: -1
  readonly property var tagPalette: ["accent", "urgent", "foreground", "#ffcc40", "#10b981", "#06b6d4", "#a78bfa", "#f472b6", "#fb923c", "#60a5fa"]

  function paletteColor(c) {
    if (c === "accent") return Commons.Color.accent
    if (c === "urgent") return Commons.Color.urgent
    if (c === "foreground") return Commons.Color.foreground
    return Qt.color(c)
  }

  function saveTags(list) {
    QuickNotesStore.tagsList = list
    runAction(["save_tags", JSON.stringify(list)])
  }

  function setTagColor(index, color) {
    if (index < 0 || index >= tagsList.length) return
    var l = tagsList.slice()
    l[index] = { name: l[index].name, color: color }
    saveTags(l)
  }

  function renameTag(index, newName) {
    if (index < 0 || index >= tagsList.length) return
    var n = (newName || "").trim().replace(/\s+/g, "-").replace(/^#+/, "").slice(0, 31)
    if (!n) return
    n = "#" + n
    var old = tagsList[index].name
    if (n === old || availableTags.indexOf(n) !== -1) return
    var l = tagsList.slice()
    l[index] = { name: n, color: l[index].color }
    QuickNotesStore.tagsList = l
    if (currentTag === old) currentTag = n
    runAction(["rename_tag", old, n])
  }

  function addTag() {
    var base = "#new", n = base, k = 2
    while (availableTags.indexOf(n) !== -1) { n = base + k; k++ }
    var l = tagsList.slice()
    l.push({ name: n, color: "accent" })
    saveTags(l)
  }

  function moveTag(from, to) {
    if (from === to || from < 0 || to < 0 || from >= tagsList.length || to >= tagsList.length) return
    var l = tagsList.slice()
    var item = l.splice(from, 1)[0]
    l.splice(to, 0, item)
    saveTags(l)
  }

  // Row being dragged by its grip in the tag editor, and where it would land
  property int tagDragIndex: -1
  property int tagDropIndex: -1

  // Tasks carrying the deleted tag move to the first remaining tag.
  function removeTag(index) {
    if (tagsList.length <= 1 || index < 0 || index >= tagsList.length) return
    var l = tagsList.slice()
    var removed = l.splice(index, 1)[0]
    if (tagColorEditIndex === index) tagColorEditIndex = -1
    QuickNotesStore.tagsList = l
    if (currentTag === removed.name) currentTag = l[0].name
    runAction(["delete_tag", removed.name])
  }
  property string statusMessage: "Synced to notes.md"
  property bool feedbackActive: false

  // Inputs inside the overlays and the task rows are created by delegates, so
  // they are found through the window's focus item rather than by id.
  readonly property Item windowFocusItem: Window.activeFocusItem
  function focusInside(container) {
    var it = windowFocusItem
    while (it) {
      if (it === container) return true
      it = it.parent
    }
    return false
  }
  readonly property bool overlayInputFocused: windowFocusItem !== null
    && (focusInside(tagEditor) || focusInside(loggingPanel) || focusInside(todosListView))

  readonly property bool hasInputFocus: (
    (typeof scratchpadEdit !== "undefined" && scratchpadEdit && scratchpadEdit.activeFocus) ||
    (typeof taskInput !== "undefined" && taskInput && taskInput.activeFocus) ||
    (typeof snipNameInput !== "undefined" && snipNameInput && snipNameInput.activeFocus) ||
    (typeof snipCmdInput !== "undefined" && snipCmdInput && snipCmdInput.activeFocus) ||
    (typeof snipDescInput !== "undefined" && snipDescInput && snipDescInput.activeFocus) ||
    overlayInputFocused
  )

  onHasInputFocusChanged: {
    if (rootRef && "keyboardFocusRequested" in rootRef) {
      if ("keyboardFocusWindow" in rootRef) rootRef.keyboardFocusWindow = hasInputFocus ? notesWidgetRoot.QsWindow.window : null
      rootRef.keyboardFocusRequested = hasInputFocus
    }
  }

  Connections {
    target: (rootRef && "keyboardFocusRequested" in rootRef) ? rootRef : null
    ignoreUnknownSignals: true
    function onKeyboardFocusRequestedChanged() {
      if (rootRef && !rootRef.keyboardFocusRequested) {
        if (typeof scratchpadEdit !== "undefined" && scratchpadEdit && scratchpadEdit.activeFocus) scratchpadEdit.focus = false
        if (typeof taskInput !== "undefined" && taskInput && taskInput.activeFocus) taskInput.focus = false
        if (typeof snipNameInput !== "undefined" && snipNameInput && snipNameInput.activeFocus) snipNameInput.focus = false
        if (typeof snipCmdInput !== "undefined" && snipCmdInput && snipCmdInput.activeFocus) snipCmdInput.focus = false
        if (typeof snipDescInput !== "undefined" && snipDescInput && snipDescInput.activeFocus) snipDescInput.focus = false
        if (notesWidgetRoot.overlayInputFocused && notesWidgetRoot.windowFocusItem) notesWidgetRoot.windowFocusItem.focus = false
      }
    }
  }

  Component.onDestruction: {
    if (rootRef && "keyboardFocusRequested" in rootRef && rootRef.keyboardFocusRequested) {
      rootRef.keyboardFocusRequested = false
    }
  }

  readonly property int pendingCount: {
    var count = 0
    for (var i = 0; i < todosList.length; i++) {
      if (!todosList[i].done) count++
    }
    return count
  }
  readonly property int completedCount: todosList.length - pendingCount
  function runAction(args) { QuickNotesStore.runAction(args) }

  function toggleTodo(id) {
    runAction(["toggle_todo", id.toString()])
  }

  function deleteTodo(id) {
    runAction(["delete_todo", id.toString()])
  }

  // Inline task editing (click the text) and grip drag-reorder
  property int editingTodoId: -1
  property int todoDragIndex: -1
  property int todoDropIndex: -1

  function editTodo(id, text) {
    var t = (text || "").trim()
    editingTodoId = -1
    if (!t) return
    for (var i = 0; i < todosList.length; i++) {
      if (todosList[i].id === id) {
        if (todosList[i].text === t) return
        var l = todosList.slice()
        l[i] = Object.assign({}, l[i], { text: t })
        QuickNotesStore.todosList = l
        break
      }
    }
    runAction(["edit_todo", id.toString(), t])
  }

  function moveTodo(from, to) {
    if (from === to || from < 0 || to < 0 || from >= todosList.length || to >= todosList.length) return
    var l = todosList.slice()
    var item = l.splice(from, 1)[0]
    l.splice(to, 0, item)
    QuickNotesStore.todosList = l
    runAction(["reorder_todos", JSON.stringify(l.map(function(t) { return t.id }))])
  }

  function setTodoTag(id, tag) {
    runAction(["set_tag", id.toString(), tag])
  }

  // Tag menu opened by right-clicking a tag pill: the input pill picks the
  // tag for new tasks (tagMenuTodoId -1), a row pill re-tags that task.
  property bool tagMenuOpen: false
  property int tagMenuTodoId: -1
  property real tagMenuX: 0
  property real tagMenuY: 0

  // Called by WidgetCard before it opens its own menu: a right-click on the
  // input tag pill or a task's tag pill opens the tag menu instead.
  function handleRightClick(x, y) {
    if (tagEditorOpen) return false
    if (inputTagPill.visible && inputTagPill.contains(inputTagPill.mapFromItem(notesWidgetRoot, x, y))) {
      openTagMenu(inputTagPill, -1)
      return true
    }
    if (todosListView.visible) {
      var lp = todosListView.mapFromItem(notesWidgetRoot, x, y)
      var row = todosListView.itemAt(lp.x + todosListView.contentX, lp.y + todosListView.contentY)
      if (row && row.tagPill && row.tagPill.visible && row.tagPill.contains(row.tagPill.mapFromItem(notesWidgetRoot, x, y))) {
        openTagMenu(row.tagPill, row.modelData.id)
        return true
      }
    }
    return false
  }

  function openTagMenu(anchorItem, todoId) {
    var pos = anchorItem.mapToItem(tagMenu.parent, 0, anchorItem.height + 4)
    tagMenuTodoId = todoId
    tagMenuX = Math.max(0, Math.min(pos.x, tagMenu.parent.width - tagMenu.width))
    tagMenuY = Math.max(0, Math.min(pos.y, tagMenu.parent.height - tagMenu.height))
    tagMenuOpen = true
  }

  function pickTag(tag) {
    if (tagMenuTodoId < 0) currentTag = tag
    else setTodoTag(tagMenuTodoId, tag)
    tagMenuOpen = false
  }

  function addTodo(text, tag) {
    if (!text || text.trim() === "") return
    runAction(["add_todo", text.trim(), tag])
  }

  function clearCompleted() {
    runAction(["clear_completed"])
  }

  // Snippets state & management
  property bool snippetEditorOpen: false
  property int editingSnippetId: -1
  property string snippetEditorName: ""
  property string snippetEditorCmd: ""
  property string snippetEditorDesc: ""

  onCurrentTabChanged: {
    if (currentTab !== "COMMANDS") {
      closeSnippetEditor()
    }
    if (typeof scratchpadEdit !== "undefined" && scratchpadEdit) scratchpadEdit.focus = false
    if (typeof taskInput !== "undefined" && taskInput) taskInput.focus = false
    if (typeof snipNameInput !== "undefined" && snipNameInput) snipNameInput.focus = false
    if (typeof snipCmdInput !== "undefined" && snipCmdInput) snipCmdInput.focus = false
    if (typeof snipDescInput !== "undefined" && snipDescInput) snipDescInput.focus = false
  }

  onSnippetEditorOpenChanged: {
    if (snippetEditorOpen) {
      if (typeof snipNameInput !== "undefined" && snipNameInput) {
        snipNameInput.text = snippetEditorName
        snipNameInput.forceActiveFocus()
      }
      if (typeof snipCmdInput !== "undefined" && snipCmdInput) {
        snipCmdInput.text = snippetEditorCmd
      }
      if (typeof snipDescInput !== "undefined" && snipDescInput) {
        snipDescInput.text = snippetEditorDesc
      }
    }
  }

  function openNewSnippetEditor() {
    editingSnippetId = -1
    snippetEditorName = ""
    snippetEditorCmd = ""
    snippetEditorDesc = ""
    if (typeof snipNameInput !== "undefined" && snipNameInput) snipNameInput.text = ""
    if (typeof snipCmdInput !== "undefined" && snipCmdInput) snipCmdInput.text = ""
    if (typeof snipDescInput !== "undefined" && snipDescInput) snipDescInput.text = ""
    snippetEditorOpen = true
  }

  function openEditSnippetEditor(snippet) {
    editingSnippetId = snippet.id !== undefined ? snippet.id : -1
    snippetEditorName = snippet.name || ""
    snippetEditorCmd = snippet.cmd || ""
    snippetEditorDesc = snippet.desc || ""
    if (typeof snipNameInput !== "undefined" && snipNameInput) snipNameInput.text = snippetEditorName
    if (typeof snipCmdInput !== "undefined" && snipCmdInput) snipCmdInput.text = snippetEditorCmd
    if (typeof snipDescInput !== "undefined" && snipDescInput) snipDescInput.text = snippetEditorDesc
    snippetEditorOpen = true
  }

  function closeSnippetEditor() {
    snippetEditorOpen = false
    editingSnippetId = -1
    snippetEditorName = ""
    snippetEditorCmd = ""
    snippetEditorDesc = ""
  }

  function addSnippet(name, cmd, desc) {
    if (!name || !name.trim() || !cmd || !cmd.trim()) return
    runAction(["add_command", name.trim(), cmd.trim(), desc ? desc.trim() : ""])
  }

  function editSnippet(id, name, cmd, desc) {
    if (!name || !name.trim() || !cmd || !cmd.trim()) return
    runAction(["edit_command", id.toString(), name.trim(), cmd.trim(), desc ? desc.trim() : ""])
  }

  function deleteSnippet(id) {
    runAction(["delete_command", id.toString()])
  }

  Timer {
    id: saveDebounce
    interval: 800
    repeat: false
    onTriggered: {
      runAction(["save_scratchpad", scratchpadEdit.text])
      notesWidgetRoot.statusMessage = "✓ Saved to notes.md"
    }
  }

  customMenuContent: Component {
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(3)

      Text {
        text: "QUICK NOTES & DECK ACTIONS"
        font.family: Style.font.family
        font.pixelSize: 9
        font.weight: Font.Bold
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
        Layout.leftMargin: 4
        Layout.topMargin: 2
      }

      // Switch to Tasks Tab
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: tabTaskMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf0ae"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.accent
          }
          Text {
            Layout.fillWidth: true
            text: "Switch to Tasks Tab"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }
        }
        MouseArea {
          id: tabTaskMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            notesWidgetRoot.currentTab = "TASKS"
            notesWidgetRoot.contextMenuOpen = false
          }
        }
      }

      // Switch to Scratchpad Tab
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: tabScratchMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf044"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.accent
          }
          Text {
            Layout.fillWidth: true
            text: "Switch to Scratchpad"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }
        }
        MouseArea {
          id: tabScratchMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            notesWidgetRoot.currentTab = "SCRATCHPAD"
            notesWidgetRoot.contextMenuOpen = false
          }
        }
      }

      // Switch to Snippets Tab
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: tabCmdMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf120"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.accent
          }
          Text {
            Layout.fillWidth: true
            text: "Switch to Snippets Tab"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }
        }
        MouseArea {
          id: tabCmdMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            notesWidgetRoot.currentTab = "COMMANDS"
            notesWidgetRoot.contextMenuOpen = false
          }
        }
      }

      // Add New Snippet
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: addSnipOptMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf067"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.accent
          }
          Text {
            Layout.fillWidth: true
            text: "Add New Snippet"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }
        }
        MouseArea {
          id: addSnipOptMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            notesWidgetRoot.currentTab = "COMMANDS"
            notesWidgetRoot.openNewSnippetEditor()
            notesWidgetRoot.contextMenuOpen = false
          }
        }
      }

      // Manage Tags
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: tagsOptMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf02c"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.accent
          }
          Text {
            Layout.fillWidth: true
            text: "Manage Tags"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }
        }
        MouseArea {
          id: tagsOptMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            notesWidgetRoot.tagColorEditIndex = -1
            notesWidgetRoot.tagEditorOpen = true
            notesWidgetRoot.contextMenuOpen = false
          }
        }
      }

      // Logging
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: logOptMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf15c"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.accent
          }
          Text {
            Layout.fillWidth: true
            text: "Logging"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }
          Text {
            visible: notesWidgetRoot.loggingConfig.obsidian_enabled || notesWidgetRoot.loggingConfig.event_log_enabled
            text: "on"
            font.family: Style.font.family
            font.pixelSize: 9
            color: Commons.Color.accent
          }
        }
        MouseArea {
          id: logOptMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            notesWidgetRoot.loggingOpen = true
            notesWidgetRoot.contextMenuOpen = false
          }
        }
      }

      // Clear Completed Tasks
      Rectangle {
        visible: notesWidgetRoot.completedCount > 0
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: clearOptMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf1f8"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.urgent
          }
          Text {
            Layout.fillWidth: true
            text: "Clear " + notesWidgetRoot.completedCount + " Completed Tasks"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.urgent
          }
        }
        MouseArea {
          id: clearOptMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            notesWidgetRoot.clearCompleted()
            notesWidgetRoot.contextMenuOpen = false
          }
        }
      }

      // Open notes.md in Text Editor
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 6
        color: editMdMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text {
            text: "\uf15c"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.accent
          }
          Text {
            Layout.fillWidth: true
            text: "Open notes.md in Editor"
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.foreground
          }
        }
        MouseArea {
          id: editMdMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            Quickshell.execDetached(["bash", "-c", "xdg-open \"$HOME/.local/state/omarchy/dagyr.desktop-widgets/notes.md\""])
            notesWidgetRoot.contextMenuOpen = false
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 🎨 Layout Body
  // ---------------------------------------------------------------------------
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(10)

    // -------------------------------------------------------------------------
    // 🏷️ Top Header: Icon, Title, Badge & Grip/Close Slot
    // -------------------------------------------------------------------------
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Rectangle {
        width: 30
        height: 30
        radius: 15
        color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2)
        border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.4)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "\uf044"
          font.family: Style.font.family
          font.pixelSize: 13
          color: Commons.Color.accent
        }
      }

      ColumnLayout {
        spacing: 0
        Text {
          text: "Quick Notes & Deck"
          font.family: Style.font.family
          font.pixelSize: 13
          font.weight: Font.Bold
          color: Commons.Color.foreground
        }
        Text {
          text: notesWidgetRoot.pendingCount + " pending · " + notesWidgetRoot.completedCount + " done"
          font.family: Style.font.family
          font.pixelSize: 10
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
        }
      }

      Item { Layout.fillWidth: true }

      // Close button when in layout edit mode
      Rectangle {
        visible: rootRef && rootRef.layoutEditMode
        width: 22
        height: 22
        radius: 11
        color: closeMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.35) : notesWidgetRoot.fgTint(0.08)
        border.color: Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.5)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "\uf00d"
          font.family: Style.font.family
          font.pixelSize: 10
          color: Commons.Color.urgent
        }

        MouseArea {
          id: closeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (rootRef && rootRef.toggleWidgetEnabled) {
              rootRef.toggleWidgetEnabled(notesWidgetRoot.widgetId, false, notesWidgetRoot.monitorName)
            }
          }
        }
      }

      // Drag Grip Button (Move Mode)
      Rectangle {
        visible: rootRef && rootRef.layoutEditMode
        width: 22
        height: 22
        radius: 11
        color: customGripMouse.drag.active ? Commons.Color.accent : (customGripMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35) : notesWidgetRoot.fgTint(0.08))
        border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.5)
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "\uf0b2"
          font.family: Style.font.family
          font.pixelSize: 10
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
          drag.maximumX: screenWidth - notesWidgetRoot.width - 10
          drag.minimumY: 10
          drag.maximumY: screenHeight - notesWidgetRoot.height - 10
          onPressed: notesWidgetRoot.customGripDragging = true
          onReleased: {
            notesWidgetRoot.customGripDragging = false
            if (rootRef && rootRef.saveWidgetPos) {
              rootRef.saveWidgetPos(notesWidgetRoot.widgetId, Math.round(targetItem.x), Math.round(targetItem.y), Math.round(notesWidgetRoot.width), Math.round(notesWidgetRoot.height), notesWidgetRoot.monitorName)
            }
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // 🗂️ Category Tab Pills
    // -------------------------------------------------------------------------
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(6)

      Repeater {
        model: [
          { key: "TASKS", label: "Tasks", icon: "\uf0ae" },
          { key: "SCRATCHPAD", label: "Scratchpad", icon: "\uf044" },
          { key: "COMMANDS", label: "Snippets", icon: "\uf120" }
        ]

        Rectangle {
          required property var modelData
          implicitWidth: tabRow.implicitWidth + 18
          implicitHeight: 26
          radius: 13
          readonly property bool isSelected: notesWidgetRoot.currentTab === modelData.key
          color: tabMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25) : (isSelected ? Commons.Color.accent : notesWidgetRoot.fgTint(0.08))

          RowLayout {
            id: tabRow
            anchors.centerIn: parent
            spacing: Style.space(5)

            Text {
              text: modelData.icon
              font.family: Style.font.family
              font.pixelSize: 10
              color: isSelected ? Commons.Color.background : Commons.Color.accent
            }
            Text {
              text: modelData.label
              font.family: Style.font.family
              font.pixelSize: 11
              font.weight: isSelected ? Font.Bold : Font.Normal
              color: isSelected ? Commons.Color.background : Commons.Color.foreground
            }
          }

          MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: notesWidgetRoot.currentTab = modelData.key
          }
        }
      }

      Item { Layout.fillWidth: true }
    }

    // -------------------------------------------------------------------------
    // 📋 TAB 1: Tasks / Todos
    // -------------------------------------------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: notesWidgetRoot.currentTab === "TASKS"
      spacing: Style.space(8)

      // Add Task Input Row
      Rectangle {
        Layout.fillWidth: true
        height: 34
        radius: 17
        color: notesWidgetRoot.fgTint(0.06)
        border.color: taskInput.activeFocus ? Commons.Color.accent : notesWidgetRoot.fgTint(0.12)
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(6)

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            TextInput {
              id: taskInput
              anchors.fill: parent
              verticalAlignment: TextInput.AlignVCenter
              font.family: Style.font.family
              font.pixelSize: 12
              color: Commons.Color.foreground
              clip: true
              selectByMouse: true
              cursorVisible: activeFocus

              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "Add new task... press Enter"
                font.family: Style.font.family
                font.pixelSize: 12
                color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)
                visible: !taskInput.text && !taskInput.activeFocus
              }

              onAccepted: {
                notesWidgetRoot.addTodo(taskInput.text, notesWidgetRoot.currentTag)
                taskInput.text = ""
              }
            }
          }

          // Tag Pill Cycler (left-click cycles, right-click opens the tag menu
          // via handleRightClick)
          Rectangle {
            id: inputTagPill
            implicitWidth: tagText.implicitWidth + 14
            implicitHeight: 22
            radius: 11
            color: notesWidgetRoot.tagTint(notesWidgetRoot.currentTag, 0.22)
            border.color: notesWidgetRoot.tagColor(notesWidgetRoot.currentTag)
            border.width: 1

            Text {
              id: tagText
              anchors.centerIn: parent
              text: notesWidgetRoot.currentTag
              font.family: Style.font.family
              font.pixelSize: 10
              font.weight: Font.Bold
              color: notesWidgetRoot.tagColor(notesWidgetRoot.currentTag)
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var idx = notesWidgetRoot.availableTags.indexOf(notesWidgetRoot.currentTag)
                notesWidgetRoot.currentTag = notesWidgetRoot.availableTags[(idx + 1) % notesWidgetRoot.availableTags.length]
              }
            }
          }

          // Add Button
          Rectangle {
            width: 24
            height: 24
            radius: 12
            color: addBtnMouse.containsMouse ? Qt.lighter(Commons.Color.accent, 1.2) : Commons.Color.accent

            Text {
              anchors.centerIn: parent
              text: "\uf067"
              font.family: Style.font.family
              font.pixelSize: 10
              color: Commons.Color.background
            }

            MouseArea {
              id: addBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                notesWidgetRoot.addTodo(taskInput.text, notesWidgetRoot.currentTag)
                taskInput.text = ""
              }
            }
          }
        }
      }

      // Tasks List
      ListView {
        id: todosListView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        interactive: notesWidgetRoot.todoDragIndex === -1
        spacing: Style.space(6)
        model: notesWidgetRoot.todosList

        delegate: Rectangle {
          id: todoRow
          required property var modelData
          required property int index
          property alias tagPill: rowTagPill
          readonly property bool beingDragged: notesWidgetRoot.todoDragIndex === index
          readonly property bool editing: notesWidgetRoot.editingTodoId === modelData.id
          readonly property real rowStride: height + todosListView.spacing
          property real dragOffset: 0
          width: todosListView.width
          height: 38
          radius: 10
          z: beingDragged ? 10 : 0
          transform: Translate { y: todoRow.beingDragged ? todoRow.dragOffset : 0 }
          color: todoRow.beingDragged ? notesWidgetRoot.fgTint(0.12) : (taskItemMouse.containsMouse ? notesWidgetRoot.fgTint(0.08) : notesWidgetRoot.fgTint(0.03))
          border.color: todoRow.beingDragged || todoRow.editing ? Commons.Color.accent : notesWidgetRoot.fgTint(0.07)
          border.width: 1

          // Drop marker above the row a dragged task would land on
          Rectangle {
            visible: notesWidgetRoot.todoDragIndex !== -1 && notesWidgetRoot.todoDropIndex === todoRow.index && !todoRow.beingDragged
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: -4
            height: 2
            radius: 1
            color: Commons.Color.accent
          }

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(4)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            // Drag grip: reorder tasks
            Item {
              width: 14
              height: 24
              Text {
                anchors.centerIn: parent
                text: "\uf0c9"
                font.family: Style.font.family
                font.pixelSize: 10
                color: todoGripMouse.containsMouse || todoRow.beingDragged ? Commons.Color.accent : notesWidgetRoot.fgTint(0.3)
              }
              MouseArea {
                id: todoGripMouse
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: todoRow.beingDragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real pressY: 0
                onPressed: function(mouse) {
                  // Measured in the list's frame: the row itself moves with the drag
                  pressY = mapToItem(todosListView, mouse.x, mouse.y).y
                  todoRow.dragOffset = 0
                  notesWidgetRoot.editingTodoId = -1
                  notesWidgetRoot.todoDragIndex = todoRow.index
                  notesWidgetRoot.todoDropIndex = todoRow.index
                }
                onPositionChanged: function(mouse) {
                  if (!pressed) return
                  todoRow.dragOffset = mapToItem(todosListView, mouse.x, mouse.y).y - pressY
                  var target = todoRow.index + Math.round(todoRow.dragOffset / todoRow.rowStride)
                  notesWidgetRoot.todoDropIndex = Math.max(0, Math.min(notesWidgetRoot.todosList.length - 1, target))
                }
                onReleased: {
                  var from = notesWidgetRoot.todoDragIndex
                  var to = notesWidgetRoot.todoDropIndex
                  notesWidgetRoot.todoDragIndex = -1
                  notesWidgetRoot.todoDropIndex = -1
                  todoRow.dragOffset = 0
                  notesWidgetRoot.moveTodo(from, to)
                }
                onCanceled: {
                  notesWidgetRoot.todoDragIndex = -1
                  notesWidgetRoot.todoDropIndex = -1
                  todoRow.dragOffset = 0
                }
              }
            }

            // Custom Checkbox
            Rectangle {
              width: 18
              height: 18
              radius: 6
              color: modelData.done ? Commons.Color.accent : "transparent"
              border.color: modelData.done ? Commons.Color.accent : notesWidgetRoot.fgTint(0.35)
              border.width: 1.5

              Text {
                anchors.centerIn: parent
                visible: modelData.done
                text: "\uf00c"
                font.family: Style.font.family
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Commons.Color.background
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: notesWidgetRoot.toggleTodo(modelData.id)
              }
            }

            // Task Text: click to edit in place, Enter or focus loss saves
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: !todoRow.editing
                text: modelData.text || ""
                font.family: Style.font.family
                font.pixelSize: 12
                font.strikeout: modelData.done
                color: modelData.done ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.4) : Commons.Color.foreground
                elide: Text.ElideRight

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.IBeamCursor
                  onClicked: {
                    notesWidgetRoot.editingTodoId = todoRow.modelData.id
                    todoEditInput.text = todoRow.modelData.text || ""
                    todoEditInput.forceActiveFocus()
                    todoEditInput.cursorPosition = todoEditInput.text.length
                  }
                }
              }

              TextInput {
                id: todoEditInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                visible: todoRow.editing
                font.family: Style.font.family
                font.pixelSize: 12
                color: Commons.Color.foreground
                clip: true
                selectByMouse: true
                cursorVisible: activeFocus
                onActiveFocusChanged: if (!activeFocus && todoRow.editing) notesWidgetRoot.editTodo(todoRow.modelData.id, text)
                onAccepted: focus = false
                Keys.onEscapePressed: {
                  notesWidgetRoot.editingTodoId = -1
                  focus = false
                }
              }
            }

            // Tag Pill (right-click re-tags via handleRightClick)
            Rectangle {
              id: rowTagPill
              visible: modelData.tag !== undefined && modelData.tag !== ""
              implicitWidth: rowTagText.implicitWidth + 10
              implicitHeight: 18
              radius: 9
              color: notesWidgetRoot.tagTint(modelData.tag, 0.2)

              Text {
                id: rowTagText
                anchors.centerIn: parent
                text: modelData.tag || ""
                font.family: Style.font.family
                font.pixelSize: 9
                font.weight: Font.DemiBold
                color: notesWidgetRoot.tagColor(modelData.tag)
              }

            }

            // Delete Button (visible on hover)
            Rectangle {
              width: 20
              height: 20
              radius: 10
              visible: taskItemMouse.containsMouse
              color: delMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.35) : "transparent"

              Text {
                anchors.centerIn: parent
                text: "\uf1f8"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Commons.Color.urgent
              }

              MouseArea {
                id: delMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: notesWidgetRoot.deleteTodo(modelData.id)
              }
            }
          }

          MouseArea {
            id: taskItemMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
          }
        }
      }

      // Bottom Bar
      RowLayout {
        Layout.fillWidth: true
        Layout.rightMargin: 10

        Text {
          text: notesWidgetRoot.completedCount + " completed"
          font.family: Style.font.family
          font.pixelSize: 10
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
        }

        Item { Layout.fillWidth: true }

        Rectangle {
          visible: notesWidgetRoot.completedCount > 0
          implicitWidth: clearRow.implicitWidth + 20
          implicitHeight: 22
          radius: 11
          color: clearMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.25) : Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.08)
          border.color: clearMouse.containsMouse ? Commons.Color.urgent : Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.3)
          border.width: 1

          RowLayout {
            id: clearRow
            anchors.centerIn: parent
            spacing: 5
            Text {
              text: "\uf1f8"
              font.family: Style.font.family
              font.pixelSize: 9
              color: Commons.Color.urgent
            }
            Text {
              id: clearText
              text: "Clear Done"
              font.family: Style.font.family
              font.pixelSize: 10
              font.weight: Font.DemiBold
              color: Commons.Color.urgent
            }
          }

          MouseArea {
            id: clearMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: notesWidgetRoot.clearCompleted()
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // 📝 TAB 2: Scratchpad
    // -------------------------------------------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: notesWidgetRoot.currentTab === "SCRATCHPAD"
      spacing: Style.space(8)

      Rectangle {
        id: scratchpadBox
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: notesWidgetRoot.fgTint(0.04)
        border.color: scratchpadEdit.activeFocus ? Commons.Color.accent : notesWidgetRoot.fgTint(0.1)
        border.width: 1

        MouseArea {
          id: scratchpadOuterClick
          anchors.fill: parent
          cursorShape: Qt.IBeamCursor
          onClicked: {
            scratchpadEdit.forceActiveFocus()
            scratchpadEdit.cursorPosition = scratchpadEdit.text.length
          }
        }

        Flickable {
          id: scratchpadFlickable
          anchors.fill: parent
          anchors.margins: Style.space(10)
          contentWidth: width
          contentHeight: Math.max(height, scratchpadEdit.implicitHeight + 40)
          clip: true

          MouseArea {
            id: scratchpadBlankArea
            width: scratchpadFlickable.contentWidth
            height: Math.max(scratchpadFlickable.height, scratchpadFlickable.contentHeight)
            cursorShape: Qt.IBeamCursor
            onClicked: {
              scratchpadEdit.forceActiveFocus()
              scratchpadEdit.cursorPosition = scratchpadEdit.text.length
            }
          }

          TextEdit {
            id: scratchpadEdit
            width: scratchpadFlickable.width
            font.family: Style.font.family
            font.pixelSize: 12
            color: Commons.Color.foreground
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            cursorVisible: activeFocus
            activeFocusOnTab: true

            Text {
              anchors.fill: parent
              text: "Jot down anything here... auto-syncs to notes.md"
              font.family: Style.font.family
              font.pixelSize: 12
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)
              visible: !scratchpadEdit.text && !scratchpadEdit.activeFocus
            }

            onTextChanged: {
              notesWidgetRoot.statusMessage = "Typing..."
              saveDebounce.restart()
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true

        Text {
          text: notesWidgetRoot.statusMessage
          font.family: Style.font.family
          font.pixelSize: 10
          color: Commons.Color.accent
        }

        Item { Layout.fillWidth: true }

        Text {
          text: scratchpadEdit.text.length + " chars"
          font.family: Style.font.family
          font.pixelSize: 10
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
        }
      }
    }

    // -------------------------------------------------------------------------
    // ⚡ TAB 3: Commands & Snippets
    // -------------------------------------------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: notesWidgetRoot.currentTab === "COMMANDS"
      spacing: Style.space(8)

      // 1. When NOT editing a snippet: show List and "+ New Snippet" button
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: !notesWidgetRoot.snippetEditorOpen
        spacing: Style.space(8)

        // Header Row: Count & Add Button
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "SAVED SNIPPETS"
            font.family: Style.font.family
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
          }

          Rectangle {
            implicitWidth: countText.implicitWidth + 12
            implicitHeight: 18
            radius: 9
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2)
            border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.4)
            border.width: 1

            Text {
              id: countText
              anchors.centerIn: parent
              text: notesWidgetRoot.commandsList.length.toString()
              font.family: Style.font.family
              font.pixelSize: 9
              font.weight: Font.Bold
              color: Commons.Color.accent
            }
          }

          Item { Layout.fillWidth: true }

          // Add Snippet Button
          Rectangle {
            implicitWidth: addSnipRow.implicitWidth + 16
            implicitHeight: 24
            radius: 12
            color: addSnipMouse.containsMouse ? Commons.Color.accent : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2)
            border.color: Commons.Color.accent
            border.width: 1

            RowLayout {
              id: addSnipRow
              anchors.centerIn: parent
              spacing: 4

              Text {
                text: "\uf067"
                font.family: Style.font.family
                font.pixelSize: 9
                color: addSnipMouse.containsMouse ? Commons.Color.background : Commons.Color.accent
              }
              Text {
                text: "New Snippet"
                font.family: Style.font.family
                font.pixelSize: 10
                font.weight: Font.Bold
                color: addSnipMouse.containsMouse ? Commons.Color.background : Commons.Color.accent
              }
            }

            MouseArea {
              id: addSnipMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: notesWidgetRoot.openNewSnippetEditor()
            }
          }
        }

        // Snippets List & Scrollbar Container
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // Empty state
          ColumnLayout {
            anchors.centerIn: parent
            visible: notesWidgetRoot.commandsList.length === 0
            spacing: Style.space(6)

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: "\uf120"
              font.family: Style.font.family
              font.pixelSize: 28
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.2)
            }
            Text {
              Layout.alignment: Qt.AlignHCenter
              text: "No snippets saved yet"
              font.family: Style.font.family
              font.pixelSize: 12
              font.weight: Font.DemiBold
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.5)
            }
            Text {
              Layout.alignment: Qt.AlignHCenter
              text: "Click '+ New Snippet' to add custom commands"
              font.family: Style.font.family
              font.pixelSize: 10
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)
            }
          }

          ListView {
            id: commandsListView
            anchors.fill: parent
            clip: true
            spacing: Style.space(6)
            model: notesWidgetRoot.commandsList

            delegate: Rectangle {
              required property var modelData
              width: commandsListView.width - (scrollTrack.visible ? 8 : 0)
              height: 52
              radius: 10
              color: cmdMouse.containsMouse ? notesWidgetRoot.fgTint(0.08) : notesWidgetRoot.fgTint(0.04)
              border.color: cmdMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.3) : notesWidgetRoot.fgTint(0.08)
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Rectangle {
                  width: 30
                  height: 30
                  radius: 8
                  color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.15)
                  border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.3)
                  border.width: 1

                  Text {
                    anchors.centerIn: parent
                    text: "\uf120"
                    font.family: Style.font.family
                    font.pixelSize: 11
                    color: Commons.Color.accent
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 1

                  Text {
                    Layout.fillWidth: true
                    text: modelData.name || ""
                    font.family: Style.font.family
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: Commons.Color.foreground
                    elide: Text.ElideRight
                  }
                  Text {
                    Layout.fillWidth: true
                    text: modelData.cmd || ""
                    font.family: "Monospace"
                    font.pixelSize: 10
                    color: Qt.lighter(Commons.Color.accent, 1.15)
                    elide: Text.ElideRight
                  }
                }

                // Actions: Run, Edit, Delete
                RowLayout {
                  spacing: 4

                  // Run Button
                  Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: runBtnMouse.containsMouse ? Qt.lighter(Commons.Color.accent, 1.2) : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25)
                    border.color: Commons.Color.accent
                    border.width: 1

                    Text {
                      anchors.centerIn: parent
                      text: "\uf04b"
                      font.family: Style.font.family
                      font.pixelSize: 8
                      color: runBtnMouse.containsMouse ? Commons.Color.background : Commons.Color.accent
                    }

                    MouseArea {
                      id: runBtnMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        Quickshell.execDetached(["bash", "-c", modelData.cmd])
                      }
                    }
                  }

                  // Edit Button
                  Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: editBtnMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35) : notesWidgetRoot.fgTint(0.08)
                    border.color: editBtnMouse.containsMouse ? Commons.Color.accent : notesWidgetRoot.fgTint(0.15)
                    border.width: 1

                    Text {
                      anchors.centerIn: parent
                      text: "\uf044"
                      font.family: Style.font.family
                      font.pixelSize: 10
                      color: editBtnMouse.containsMouse ? Commons.Color.accent : Commons.Color.foreground
                    }

                    MouseArea {
                      id: editBtnMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: notesWidgetRoot.openEditSnippetEditor(modelData)
                    }
                  }

                  // Delete Button
                  Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: delBtnMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.35) : notesWidgetRoot.fgTint(0.08)
                    border.color: delBtnMouse.containsMouse ? Commons.Color.urgent : notesWidgetRoot.fgTint(0.15)
                    border.width: 1

                    Text {
                      anchors.centerIn: parent
                      text: "\uf1f8"
                      font.family: Style.font.family
                      font.pixelSize: 10
                      color: Commons.Color.urgent
                    }

                    MouseArea {
                      id: delBtnMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: notesWidgetRoot.deleteSnippet(modelData.id)
                    }
                  }
                }
              }

              MouseArea {
                id: cmdMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
              }
            }
          }

          // Sleek Custom Scrollbar
          Rectangle {
            id: scrollTrack
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: 2
            color: notesWidgetRoot.fgTint(0.05)
            visible: commandsListView.contentHeight > commandsListView.height

            Rectangle {
              width: parent.width
              radius: 2
              color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.6)
              height: Math.max(16, (commandsListView.height / Math.max(1, commandsListView.contentHeight)) * commandsListView.height)
              y: Math.max(0, Math.min(commandsListView.height - height, (commandsListView.contentY / Math.max(1, commandsListView.contentHeight - commandsListView.height)) * (commandsListView.height - height)))
            }
          }
        }
      }

      // 2. When EDITING or ADDING a snippet: dedicated full editor card
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: notesWidgetRoot.snippetEditorOpen
        radius: 12
        color: notesWidgetRoot.fgTint(0.04)
        border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.4)
        border.width: 1

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(8)

          // Editor Header
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Rectangle {
              width: 24
              height: 24
              radius: 12
              color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2)
              border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.4)
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: notesWidgetRoot.editingSnippetId > 0 ? "\uf044" : "\uf067"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Commons.Color.accent
              }
            }

            Text {
              text: notesWidgetRoot.editingSnippetId > 0 ? "Edit Snippet" : "New Snippet"
              font.family: Style.font.family
              font.pixelSize: 12
              font.weight: Font.Bold
              color: Commons.Color.foreground
            }

            Item { Layout.fillWidth: true }

            // Close button
            Rectangle {
              width: 22
              height: 22
              radius: 11
              color: closeEditMouse.containsMouse ? notesWidgetRoot.fgTint(0.15) : "transparent"

              Text {
                anchors.centerIn: parent
                text: "\uf00d"
                font.family: Style.font.family
                font.pixelSize: 10
                color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.7)
              }

              MouseArea {
                id: closeEditMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: notesWidgetRoot.closeSnippetEditor()
              }
            }
          }

          // Divider
          Rectangle {
            Layout.fillWidth: true
            height: 1
            color: notesWidgetRoot.fgTint(0.08)
          }

          // Field 1: Snippet Name
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: "NAME / TITLE"
              font.family: Style.font.family
              font.pixelSize: 9
              font.weight: Font.Bold
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
            }

            Rectangle {
              Layout.fillWidth: true
              height: 32
              radius: 8
              color: notesWidgetRoot.fgTint(0.06)
              border.color: snipNameInput.activeFocus ? Commons.Color.accent : notesWidgetRoot.fgTint(0.12)
              border.width: 1

              TextInput {
                id: snipNameInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: Style.font.family
                font.pixelSize: 11
                color: Commons.Color.foreground
                clip: true
                selectByMouse: true
                onAccepted: snipCmdInput.forceActiveFocus()

                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  text: "e.g. Restart Shell, Git Status..."
                  font.family: Style.font.family
                  font.pixelSize: 11
                  color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.3)
                  visible: !snipNameInput.text && !snipNameInput.activeFocus
                }
              }
            }
          }

          // Field 2: Shell Command
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: "SHELL COMMAND"
              font.family: Style.font.family
              font.pixelSize: 9
              font.weight: Font.Bold
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
            }

            Rectangle {
              Layout.fillWidth: true
              height: 32
              radius: 8
              color: notesWidgetRoot.fgTint(0.06)
              border.color: snipCmdInput.activeFocus ? Commons.Color.accent : notesWidgetRoot.fgTint(0.12)
              border.width: 1

              TextInput {
                id: snipCmdInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: "Monospace"
                font.pixelSize: 11
                color: Qt.lighter(Commons.Color.accent, 1.2)
                clip: true
                selectByMouse: true
                onAccepted: snipDescInput.forceActiveFocus()

                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  text: "e.g. omarchy-restart-shell, fastfetch..."
                  font.family: "Monospace"
                  font.pixelSize: 11
                  color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.3)
                  visible: !snipCmdInput.text && !snipCmdInput.activeFocus
                }
              }
            }
          }

          // Field 3: Description (Optional)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
              text: "DESCRIPTION (OPTIONAL)"
              font.family: Style.font.family
              font.pixelSize: 9
              font.weight: Font.Bold
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
            }

            Rectangle {
              Layout.fillWidth: true
              height: 30
              radius: 8
              color: notesWidgetRoot.fgTint(0.06)
              border.color: snipDescInput.activeFocus ? Commons.Color.accent : notesWidgetRoot.fgTint(0.12)
              border.width: 1

              TextInput {
                id: snipDescInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: Style.font.family
                font.pixelSize: 11
                color: Commons.Color.foreground
                clip: true
                selectByMouse: true
                onAccepted: saveSnippetBtn.triggerSave()

                Text {
                  anchors.fill: parent
                  verticalAlignment: Text.AlignVCenter
                  text: "Brief description of command"
                  font.family: Style.font.family
                  font.pixelSize: 11
                  color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.3)
                  visible: !snipDescInput.text && !snipDescInput.activeFocus
                }
              }
            }
          }

          // Spacer
          Item { Layout.fillHeight: true }

          // Action Buttons
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            // Delete button (visible when editing existing snippet)
            Rectangle {
              visible: notesWidgetRoot.editingSnippetId > 0
              implicitWidth: delEditRow.implicitWidth + 16
              implicitHeight: 30
              radius: 15
              color: delEditBtnMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.3) : Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.12)
              border.color: Commons.Color.urgent
              border.width: 1

              RowLayout {
                id: delEditRow
                anchors.centerIn: parent
                spacing: 5
                Text {
                  text: "\uf1f8"
                  font.family: Style.font.family
                  font.pixelSize: 10
                  color: Commons.Color.urgent
                }
                Text {
                  text: "Delete"
                  font.family: Style.font.family
                  font.pixelSize: 11
                  font.weight: Font.DemiBold
                  color: Commons.Color.urgent
                }
              }

              MouseArea {
                id: delEditBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  notesWidgetRoot.deleteSnippet(notesWidgetRoot.editingSnippetId)
                  notesWidgetRoot.closeSnippetEditor()
                }
              }
            }

            Item { Layout.fillWidth: true }

            // Cancel Button
            Rectangle {
              implicitWidth: cancelText.implicitWidth + 18
              implicitHeight: 30
              radius: 15
              color: cancelBtnMouse.containsMouse ? notesWidgetRoot.fgTint(0.12) : notesWidgetRoot.fgTint(0.06)
              border.color: notesWidgetRoot.fgTint(0.15)
              border.width: 1

              Text {
                id: cancelText
                anchors.centerIn: parent
                text: "Cancel"
                font.family: Style.font.family
                font.pixelSize: 11
                color: Commons.Color.foreground
              }

              MouseArea {
                id: cancelBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: notesWidgetRoot.closeSnippetEditor()
              }
            }

            // Save Button
            Rectangle {
              id: saveSnippetBtn
              implicitWidth: saveRow.implicitWidth + 18
              implicitHeight: 30
              radius: 15
              readonly property bool canSave: snipNameInput.text.trim().length > 0 && snipCmdInput.text.trim().length > 0
              opacity: canSave ? 1.0 : 0.5
              color: canSave && saveBtnMouse.containsMouse ? Qt.lighter(Commons.Color.accent, 1.2) : Commons.Color.accent

              function triggerSave() {
                var name = snipNameInput.text.trim()
                var cmd = snipCmdInput.text.trim()
                var desc = snipDescInput.text.trim()
                if (!name || !cmd) return
                if (notesWidgetRoot.editingSnippetId > 0) {
                  notesWidgetRoot.editSnippet(notesWidgetRoot.editingSnippetId, name, cmd, desc)
                } else {
                  notesWidgetRoot.addSnippet(name, cmd, desc)
                }
                notesWidgetRoot.closeSnippetEditor()
              }

              RowLayout {
                id: saveRow
                anchors.centerIn: parent
                spacing: 5
                Text {
                  text: "\uf00c"
                  font.family: Style.font.family
                  font.pixelSize: 10
                  color: Commons.Color.background
                }
                Text {
                  text: notesWidgetRoot.editingSnippetId > 0 ? "Save Changes" : "Create Snippet"
                  font.family: Style.font.family
                  font.pixelSize: 11
                  font.weight: Font.Bold
                  color: Commons.Color.background
                }
              }

              MouseArea {
                id: saveBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: saveSnippetBtn.canSave ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: saveSnippetBtn.triggerSave()
              }
            }
          }
        }
      }
    }
  }

  // Click-away catcher for the tag menu
  MouseArea {
    anchors.fill: parent
    z: 99
    visible: notesWidgetRoot.tagMenuOpen
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: notesWidgetRoot.tagMenuOpen = false
  }

  Rectangle {
    id: tagMenu
    x: notesWidgetRoot.tagMenuX
    y: notesWidgetRoot.tagMenuY
    z: 100
    visible: notesWidgetRoot.tagMenuOpen
    width: 110
    height: tagMenuColumn.implicitHeight + 8
    radius: 8
    color: Commons.Color.background
    border.color: notesWidgetRoot.fgTint(0.15)
    border.width: 1

    ColumnLayout {
      id: tagMenuColumn
      anchors.fill: parent
      anchors.margins: 4
      spacing: 2

      Repeater {
        model: notesWidgetRoot.availableTags

        Rectangle {
          required property string modelData
          Layout.fillWidth: true
          implicitHeight: 24
          radius: 6
          readonly property bool isCurrent: notesWidgetRoot.tagMenuTodoId < 0 && notesWidgetRoot.currentTag === modelData
          color: tagItemMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2) : "transparent"

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            text: parent.modelData
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: 10
            font.weight: parent.isCurrent ? Font.Bold : Font.Normal
            color: notesWidgetRoot.tagColor(parent.modelData)
          }

          MouseArea {
            id: tagItemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: notesWidgetRoot.pickTag(parent.modelData)
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 🏷️ Tag Editor Overlay (names and colours of the task tags)
  // ---------------------------------------------------------------------------
  Rectangle {
    id: tagEditor
    anchors.fill: parent
    z: 95
    visible: notesWidgetRoot.tagEditorOpen
    radius: 12
    color: Commons.Color.background
    border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.4)
    border.width: 1

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: notesWidgetRoot.tagColorEditIndex = -1 }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: "\uf02c"
          font.family: Style.font.family
          font.pixelSize: 12
          color: Commons.Color.accent
        }
        Text {
          Layout.fillWidth: true
          text: "Manage Tags"
          font.family: Style.font.family
          font.pixelSize: 12
          font.weight: Font.Bold
          color: Commons.Color.foreground
        }

        Rectangle {
          implicitWidth: doneLabel.implicitWidth + 20
          implicitHeight: 24
          radius: 12
          color: doneMouse.containsMouse ? Qt.lighter(Commons.Color.accent, 1.2) : Commons.Color.accent
          Text {
            id: doneLabel
            anchors.centerIn: parent
            text: "Done"
            font.family: Style.font.family
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Commons.Color.background
          }
          MouseArea {
            id: doneMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              notesWidgetRoot.tagColorEditIndex = -1
              notesWidgetRoot.tagEditorOpen = false
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        text: "Click a swatch to pick a colour. Renaming a tag updates its tasks."
        font.family: Style.font.family
        font.pixelSize: 9
        color: notesWidgetRoot.fgTint(0.5)
        wrapMode: Text.WordWrap
      }

      ListView {
        id: tagEditorList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        interactive: notesWidgetRoot.tagDragIndex === -1
        spacing: 4
        model: notesWidgetRoot.tagsList

        delegate: ColumnLayout {
          id: tagRow
          required property var modelData
          required property int index
          width: tagEditorList.width
          spacing: 4

          readonly property bool pickingColor: notesWidgetRoot.tagColorEditIndex === index
          readonly property bool beingDragged: notesWidgetRoot.tagDragIndex === index
          readonly property real rowStride: 32 + tagEditorList.spacing
          property real dragOffset: 0

          z: beingDragged ? 10 : 0
          transform: Translate { y: tagRow.beingDragged ? tagRow.dragOffset : 0 }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 8
            color: tagRow.beingDragged ? notesWidgetRoot.fgTint(0.12) : notesWidgetRoot.fgTint(0.04)
            border.color: tagNameInput.activeFocus || tagRow.beingDragged ? Commons.Color.accent : notesWidgetRoot.fgTint(0.08)
            border.width: 1

            // Drop marker: a line above this row when a dragged tag would land here
            Rectangle {
              visible: notesWidgetRoot.tagDragIndex !== -1 && notesWidgetRoot.tagDropIndex === tagRow.index && !tagRow.beingDragged
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: -3
              height: 2
              radius: 1
              color: Commons.Color.accent
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 4
              anchors.rightMargin: 6
              spacing: 8

              // Drag grip: reorder tags
              Item {
                width: 14
                height: 24
                Text {
                  anchors.centerIn: parent
                  text: "\uf0c9"
                  font.family: Style.font.family
                  font.pixelSize: 10
                  color: gripMouse.containsMouse || tagRow.beingDragged ? Commons.Color.accent : notesWidgetRoot.fgTint(0.35)
                }
                MouseArea {
                  id: gripMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: tagRow.beingDragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                  property real pressY: 0
                  onPressed: function(mouse) {
                    // Measured in the list's frame: the row itself moves with the drag
                    pressY = mapToItem(tagEditorList, mouse.x, mouse.y).y
                    tagRow.dragOffset = 0
                    notesWidgetRoot.tagColorEditIndex = -1
                    notesWidgetRoot.tagDragIndex = tagRow.index
                    notesWidgetRoot.tagDropIndex = tagRow.index
                  }
                  onPositionChanged: function(mouse) {
                    if (!pressed) return
                    tagRow.dragOffset = mapToItem(tagEditorList, mouse.x, mouse.y).y - pressY
                    var target = tagRow.index + Math.round(tagRow.dragOffset / tagRow.rowStride)
                    notesWidgetRoot.tagDropIndex = Math.max(0, Math.min(notesWidgetRoot.tagsList.length - 1, target))
                  }
                  onReleased: {
                    var from = notesWidgetRoot.tagDragIndex
                    var to = notesWidgetRoot.tagDropIndex
                    notesWidgetRoot.tagDragIndex = -1
                    notesWidgetRoot.tagDropIndex = -1
                    tagRow.dragOffset = 0
                    notesWidgetRoot.moveTag(from, to)
                  }
                  onCanceled: {
                    notesWidgetRoot.tagDragIndex = -1
                    notesWidgetRoot.tagDropIndex = -1
                    tagRow.dragOffset = 0
                  }
                }
              }

              // Colour swatch
              Rectangle {
                width: 18
                height: 18
                radius: 9
                color: notesWidgetRoot.paletteColor(tagRow.modelData.color)
                border.color: tagRow.pickingColor ? Commons.Color.foreground : notesWidgetRoot.fgTint(0.25)
                border.width: tagRow.pickingColor ? 2 : 1
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: notesWidgetRoot.tagColorEditIndex = tagRow.pickingColor ? -1 : tagRow.index
                }
              }

              // Name: the whole row height is clickable to edit
              TextInput {
                id: tagNameInput
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: TextInput.AlignVCenter
                text: tagRow.modelData.name
                font.family: Style.font.family
                font.pixelSize: 11
                color: Commons.Color.foreground
                clip: true
                selectByMouse: true
                activeFocusOnPress: true
                maximumLength: 32
                cursorVisible: activeFocus
                onActiveFocusChanged: if (!activeFocus) notesWidgetRoot.renameTag(tagRow.index, text)
                onAccepted: focus = false
              }

              // Delete
              Rectangle {
                width: 20
                height: 20
                radius: 10
                visible: notesWidgetRoot.tagsList.length > 1
                color: tagDelMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.35) : "transparent"
                Text {
                  anchors.centerIn: parent
                  text: "\uf1f8"
                  font.family: Style.font.family
                  font.pixelSize: 9
                  color: tagDelMouse.containsMouse ? Commons.Color.urgent : notesWidgetRoot.fgTint(0.4)
                }
                MouseArea {
                  id: tagDelMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: notesWidgetRoot.removeTag(tagRow.index)
                }
              }
            }
          }

          // Palette row, shown for the tag whose swatch was clicked
          Rectangle {
            Layout.fillWidth: true
            visible: tagRow.pickingColor
            implicitHeight: paletteRow.implicitHeight + 12
            radius: 8
            color: notesWidgetRoot.fgTint(0.03)
            border.color: notesWidgetRoot.fgTint(0.08)
            border.width: 1

            RowLayout {
              id: paletteRow
              anchors.fill: parent
              anchors.margins: 6
              spacing: 6

              Repeater {
                model: notesWidgetRoot.tagPalette
                Rectangle {
                  required property string modelData
                  width: 18
                  height: 18
                  radius: 9
                  color: notesWidgetRoot.paletteColor(modelData)
                  border.color: tagRow.modelData.color === modelData ? Commons.Color.foreground : notesWidgetRoot.fgTint(0.25)
                  border.width: tagRow.modelData.color === modelData ? 2 : 1
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: notesWidgetRoot.setTagColor(tagRow.index, parent.modelData)
                  }
                }
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.minimumWidth: 64
                implicitHeight: 20
                radius: 6
                color: notesWidgetRoot.fgTint(0.05)
                border.color: hexInput.activeFocus ? Commons.Color.accent : notesWidgetRoot.fgTint(0.12)
                border.width: 1
                TextInput {
                  id: hexInput
                  anchors.fill: parent
                  anchors.leftMargin: 6
                  anchors.rightMargin: 6
                  verticalAlignment: TextInput.AlignVCenter
                  text: tagRow.modelData.color.charAt(0) === "#" ? tagRow.modelData.color : ""
                  font.family: "Monospace"
                  font.pixelSize: 10
                  color: Commons.Color.foreground
                  clip: true
                  selectByMouse: true
                  maximumLength: 7
                  validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                  onAccepted: {
                    var v = text.trim()
                    if (v.charAt(0) !== "#") v = "#" + v
                    if (/^#[0-9a-fA-F]{6}$/.test(v)) notesWidgetRoot.setTagColor(tagRow.index, v.toLowerCase())
                    focus = false
                  }
                  Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "#hex"
                    font.family: "Monospace"
                    font.pixelSize: 10
                    color: notesWidgetRoot.fgTint(0.35)
                    visible: !hexInput.text && !hexInput.activeFocus
                  }
                }
              }
            }
          }
        }
      }

      // Add tag
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 28
        radius: 8
        color: addTagMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.15) : notesWidgetRoot.fgTint(0.04)
        border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
        border.width: 1
        Text {
          anchors.centerIn: parent
          text: "\uf067  Add tag"
          font.family: Style.font.family
          font.pixelSize: 10
          font.weight: Font.Bold
          color: Commons.Color.accent
        }
        MouseArea {
          id: addTagMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: notesWidgetRoot.addTag()
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 📝 Logging Overlay: Obsidian Tasks export and event log
  // ---------------------------------------------------------------------------
  Rectangle {
    id: loggingPanel
    anchors.fill: parent
    z: 95
    visible: notesWidgetRoot.loggingOpen
    radius: 12
    color: Commons.Color.background
    border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.4)
    border.width: 1

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    component LogToggle: Rectangle {
      id: toggleRoot
      property bool checked: false
      signal toggled(bool value)
      width: 34
      height: 18
      radius: 9
      color: checked ? Commons.Color.accent : notesWidgetRoot.fgTint(0.15)
      Rectangle {
        width: 14
        height: 14
        radius: 7
        y: 2
        x: toggleRoot.checked ? parent.width - width - 2 : 2
        color: Commons.Color.background
        Behavior on x { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: toggleRoot.toggled(!toggleRoot.checked)
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          text: "\uf15c"
          font.family: Style.font.family
          font.pixelSize: 12
          color: Commons.Color.accent
        }
        Text {
          Layout.fillWidth: true
          text: "Logging"
          font.family: Style.font.family
          font.pixelSize: 12
          font.weight: Font.Bold
          color: Commons.Color.foreground
        }
        Rectangle {
          implicitWidth: logDoneLabel.implicitWidth + 20
          implicitHeight: 24
          radius: 12
          color: logDoneMouse.containsMouse ? Qt.lighter(Commons.Color.accent, 1.2) : Commons.Color.accent
          Text {
            id: logDoneLabel
            anchors.centerIn: parent
            text: "Done"
            font.family: Style.font.family
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Commons.Color.background
          }
          MouseArea {
            id: logDoneMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: notesWidgetRoot.loggingOpen = false
          }
        }
      }

      // Obsidian folder: both notes are written here
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: folderCol.implicitHeight + 20
        radius: 10
        color: notesWidgetRoot.fgTint(0.04)
        border.color: notesWidgetRoot.fgTint(0.08)
        border.width: 1

        ColumnLayout {
          id: folderCol
          anchors.fill: parent
          anchors.margins: 10
          spacing: 6

          Text {
            text: "Obsidian folder"
            font.family: Style.font.family
            font.pixelSize: 11
            font.weight: Font.Bold
            color: Commons.Color.foreground
          }
          Text {
            Layout.fillWidth: true
            text: "A folder inside your vault. The notes below are written there; Obsidian picks up the changes live."
            font.family: Style.font.family
            font.pixelSize: 9
            color: notesWidgetRoot.fgTint(0.5)
            wrapMode: Text.WordWrap
          }

          Rectangle {
            Layout.fillWidth: true
            implicitHeight: 26
            radius: 6
            color: notesWidgetRoot.fgTint(0.05)
            border.color: obsidianFolderInput.activeFocus ? Commons.Color.accent : notesWidgetRoot.fgTint(0.12)
            border.width: 1
            TextInput {
              id: obsidianFolderInput
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              verticalAlignment: TextInput.AlignVCenter
              text: notesWidgetRoot.loggingConfig.obsidian_folder || ""
              font.family: "Monospace"
              font.pixelSize: 10
              color: Commons.Color.foreground
              clip: true
              selectByMouse: true
              maximumLength: 512
              onActiveFocusChanged: {
                if (!activeFocus && text.trim() !== "" && text.trim() !== notesWidgetRoot.loggingConfig.obsidian_folder) {
                  notesWidgetRoot.setLoggingField("obsidian_folder", text.trim())
                }
              }
              onAccepted: focus = false
            }
          }
        }
      }

      // Live task list
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: tasksNoteRow.implicitHeight + 20
        radius: 10
        color: notesWidgetRoot.fgTint(0.04)
        border.color: notesWidgetRoot.fgTint(0.08)
        border.width: 1

        RowLayout {
          id: tasksNoteRow
          anchors.fill: parent
          anchors.margins: 10
          spacing: 8
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: "Live task list  ·  " + notesWidgetRoot.tasksNoteName
              font.family: Style.font.family
              font.pixelSize: 11
              font.weight: Font.Bold
              color: Commons.Color.foreground
            }
            Text {
              Layout.fillWidth: true
              text: "Kept in sync both ways in the Obsidian Tasks format: - [ ] text #tag ➕ added ✅ done 🆔 id. Tick, edit, add or delete lines in Obsidian and the list follows; keep the 🆔 on a line you edit."
              font.family: Style.font.family
              font.pixelSize: 9
              color: notesWidgetRoot.fgTint(0.5)
              wrapMode: Text.WordWrap
            }
          }
          LogToggle {
            checked: notesWidgetRoot.loggingConfig.obsidian_enabled === true
            onToggled: function(v) { notesWidgetRoot.setLoggingField("obsidian_enabled", v) }
          }
        }
      }

      // Event log
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: eventCol.implicitHeight + 20
        radius: 10
        color: notesWidgetRoot.fgTint(0.04)
        border.color: notesWidgetRoot.fgTint(0.08)
        border.width: 1

        RowLayout {
          id: eventCol
          anchors.fill: parent
          anchors.margins: 10
          spacing: 8
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: "Event log  ·  " + notesWidgetRoot.logNoteName
              font.family: Style.font.family
              font.pixelSize: 11
              font.weight: Font.Bold
              color: Commons.Color.foreground
            }
            Text {
              Layout.fillWidth: true
              text: "Appends one line per add, done, reopen, edit, retag and delete under a heading for each day"
              font.family: Style.font.family
              font.pixelSize: 9
              color: notesWidgetRoot.fgTint(0.5)
              wrapMode: Text.WordWrap
            }
          }
          LogToggle {
            checked: notesWidgetRoot.loggingConfig.event_log_enabled === true
            onToggled: function(v) { notesWidgetRoot.setLoggingField("event_log_enabled", v) }
          }
        }
      }

      Item { Layout.fillHeight: true }
    }
  }
}
