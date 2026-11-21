pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One folder listing for every Folder View copy. The widget is instantiated
// once per monitor and all copies show the same saved folder, yet each used
// to run get-folder.sh at start and every 10 s on its own.
Singleton {
  id: store

  property string currentFolder: ""
  property string currentFolderName: "Desktop"
  property string parentFolder: ""
  property var folderItems: []
  property bool isLoading: false
  readonly property bool picking: pickProc.running

  // Emitted when the pick dialog returns a folder; the copy that opened it saves the setting
  signal folderPicked(string path)

  readonly property string folderScriptPath: {
    var u = Qt.resolvedUrl("../../get-folder.sh").toString()
    return decodeURIComponent(u.replace(/^file:\/\//, ""))
  }

  // A new array resets every copy's GridView (delegates and icons rebuilt,
  // scroll position lost), so polls only assign listings that changed
  property string folderItemsJson: "[]"
  function setFolderItems(items) {
    var list = Array.isArray(items) ? items : []
    var json = JSON.stringify(list)
    if (json === folderItemsJson) return
    folderItemsJson = json
    folderItems = list
  }

  function loadFolder(path) {
    if (!path) return
    currentFolder = path
    if (folderProc.running) folderProc.kill()
    folderProc.command = [store.folderScriptPath, path]
    isLoading = true
    folderProc.running = true
  }

  function pickFolder() {
    if (pickProc.running) return
    isLoading = true
    pickProc.running = true
  }

  function refreshFolder() {
    if (!folderProc.running && currentFolder !== "") {
      folderProc.command = [store.folderScriptPath, currentFolder]
      folderProc.running = true
    }
  }

  function applyListing(data) {
    currentFolder = data.folder || currentFolder
    currentFolderName = data.folder_name || "Folder"
    parentFolder = data.parent || ""
    setFolderItems(data.items)
  }

  Process {
    id: folderProc
    command: [store.folderScriptPath, store.currentFolder || "~/Desktop"]
    running: false
    onStarted: store.lastListMs = Date.now()
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line).trim()
        if (!str) return
        try {
          var data = JSON.parse(str)
          if (data.status === "ok") store.applyListing(data)
        } catch (e) {
          console.warn("[FolderStore] Parse error:", e)
        }
        store.isLoading = false
      }
    }
    onExited: store.isLoading = false
  }

  Process {
    id: pickProc
    command: [store.folderScriptPath, "pick"]
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var str = String(line).trim()
        if (!str) return
        try {
          var data = JSON.parse(str)
          if (data.status === "ok") {
            store.applyListing(data)
            store.folderPicked(store.currentFolder)
          }
        } catch (e) {
          console.warn("[FolderStore] Pick parse error:", e)
        }
        store.isLoading = false
      }
    }
    onExited: store.isLoading = false
  }

  // Copies on screen and copies with their menu open: refresh only while some
  // copy can be seen and no menu is open over the grid
  property var visibleCopies: ({})
  property var menuOpenCopies: ({})
  readonly property bool anyVisible: Object.keys(visibleCopies).length > 0
  readonly property bool anyMenuOpen: Object.keys(menuOpenCopies).length > 0
  function setVisible(key, visible) {
    var m = Object.assign({}, visibleCopies)
    if (visible) m[key] = true
    else delete m[key]
    visibleCopies = m
    // Coming back refreshes right away only if the listing is already stale
    if (visible && Date.now() - lastListMs >= folderRefreshTimer.interval && !isLoading && !pickProc.running) refreshFolder()
  }
  function setMenuOpen(key, open) {
    var m = Object.assign({}, menuOpenCopies)
    if (open) m[key] = true
    else delete m[key]
    menuOpenCopies = m
  }

  property real lastListMs: 0
  Timer {
    id: folderRefreshTimer
    interval: 10000
    running: store.anyVisible && !store.isLoading && !store.anyMenuOpen && !pickProc.running && store.currentFolder !== ""
    repeat: true
    onTriggered: store.refreshFolder()
  }
}
