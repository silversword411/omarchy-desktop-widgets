pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One traffic sampler for every Network Traffic widget copy. The widget is
// instantiated once per monitor; each copy used to read /proc/net/dev every
// 1.5 s and run get-network.sh on its own. Speeds, totals, history and the
// device list live here; the copies only draw them.
Singleton {
  id: sampler

  readonly property int pollIntervalMs: 1500
  // Buffer sized for the longest time scale (1 hour) the widget offers
  readonly property int historyLength: Math.round(3600 * 1000 / pollIntervalMs) + 1

  property real netRxSpeed: 0
  property real netTxSpeed: 0
  property string netRxSpeedStr: "0.0 KB/s"
  property string netTxSpeedStr: "0.0 KB/s"
  property string netRxTotalStr: ""
  property string netTxTotalStr: ""
  property string netIface: "Network"
  property var netRxHistory: emptyHistory()
  property var netTxHistory: emptyHistory()

  property var availableDevices: []
  property string selectedDeviceId: "AUTO"
  property string activeIface: ""
  // Device switch requested while the info script was already running; applied
  // when that run exits instead of being dropped
  property string pendingDeviceId: ""

  readonly property string netScriptPath: {
    var u = Qt.resolvedUrl("../../get-network.sh").toString()
    return decodeURIComponent(u.replace(/^file:\/\//, ""))
  }

  function emptyHistory() {
    var arr = []
    for (var i = 0; i < historyLength; i++) arr.push(0)
    return arr
  }

  // Mirrors format_speed() in get-network.sh
  function formatSpeed(bps) {
    if (bps < 1024) return bps.toFixed(0) + " B/s"
    if (bps < 1024 * 1024) return (bps / 1024).toFixed(1) + " KB/s"
    if (bps < 1024 * 1024 * 1024) return (bps / (1024 * 1024)).toFixed(1) + " MB/s"
    return (bps / (1024 * 1024 * 1024)).toFixed(2) + " GB/s"
  }

  // Mirrors format_bytes() in get-network.sh
  function formatBytes(n) {
    var units = ["B", "KB", "MB", "GB", "TB"]
    for (var i = 0; i < units.length; i++) {
      if (n < 1024) return n.toFixed(1) + " " + units[i]
      n /= 1024
    }
    return n.toFixed(1) + " PB"
  }

  // Copies on screen: the metadata script only runs while at least one is
  property var visibleCopies: ({})
  readonly property bool anyVisible: Object.keys(visibleCopies).length > 0
  function setVisible(key, visible) {
    var m = Object.assign({}, visibleCopies)
    if (visible) m[key] = true
    else delete m[key]
    visibleCopies = m
    // Coming back refreshes right away only if the last run is stale
    if (visible && Date.now() - lastNetInfoMs >= netMetaTimer.interval) refreshNetInfo()
  }

  function refreshNetInfo() {
    if (!netInfoProc.running) netInfoProc.running = true
  }

  function selectNetworkDevice(devId) {
    selectedDeviceId = devId
    netRxHistory = emptyHistory()
    netTxHistory = emptyHistory()
    if (netInfoProc.running) {
      pendingDeviceId = devId
    } else {
      netInfoProc.command = [sampler.netScriptPath, devId]
      netInfoProc.running = true
    }
  }

  // Interface metadata (monitored interface, display name, device list). Runs
  // at startup, on device switch/refresh, when a device menu opens, when the
  // monitored interface disappears, and every netMetaTimer interval.
  property real lastNetInfoMs: 0
  Process {
    id: netInfoProc
    command: [sampler.netScriptPath]
    running: true
    // Device argument is a one-shot switch request; later polls must run without it
    onStarted: {
      sampler.lastNetInfoMs = Date.now()
      command = [sampler.netScriptPath]
    }
    onExited: {
      if (sampler.pendingDeviceId) {
        var devId = sampler.pendingDeviceId
        sampler.pendingDeviceId = ""
        command = [sampler.netScriptPath, devId]
        running = true
      }
    }
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var data = JSON.parse(String(line).trim())
          if (data.iface) sampler.netIface = data.iface
          if (data.available_devices) sampler.availableDevices = data.available_devices
          // A run that predates a pending switch reports the old selection; skip it
          if (sampler.pendingDeviceId) return
          if (data.selected_iface) sampler.selectedDeviceId = data.selected_iface
          if (data.active_iface) sampler.activeIface = data.active_iface
        } catch (e) {}
      }
    }
  }

  Timer {
    id: netMetaTimer
    interval: 30000
    running: sampler.anyVisible
    repeat: true
    onTriggered: sampler.refreshNetInfo()
  }

  // Traffic sampling. Keeps running while hidden so the history stays continuous.
  property real lastRxBytes: 0
  property real lastTxBytes: 0
  property real lastSampleMs: 0
  property string lastSampleIface: ""

  function sampleTraffic(devText) {
    var iface = activeIface
    if (!iface || iface === "none") return
    var rx = -1
    var tx = -1
    var lines = devText.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var sep = lines[i].indexOf(":")
      if (sep < 0 || lines[i].substring(0, sep).trim() !== iface) continue
      var cols = lines[i].substring(sep + 1).trim().split(/\s+/)
      if (cols.length >= 9) {
        rx = Number(cols[0])
        tx = Number(cols[8])
      }
      break
    }

    var now = Date.now()
    var rxSpeed = 0
    var txSpeed = 0
    if (rx < 0) {
      // Monitored interface is gone (unplugged, renamed); let the script re-resolve
      refreshNetInfo()
    } else {
      // Same rules as the script's cache: no rate across a gap, switch or counter reset
      var dt = (now - lastSampleMs) / 1000
      if (iface === lastSampleIface && dt > 0 && dt < 10 && rx >= lastRxBytes && tx >= lastTxBytes) {
        rxSpeed = Math.round((rx - lastRxBytes) / dt)
        txSpeed = Math.round((tx - lastTxBytes) / dt)
      }
      lastRxBytes = rx
      lastTxBytes = tx
      netRxTotalStr = formatBytes(rx)
      netTxTotalStr = formatBytes(tx)
    }
    lastSampleMs = now
    lastSampleIface = rx < 0 ? "" : iface

    netRxSpeed = rxSpeed
    netTxSpeed = txSpeed
    netRxSpeedStr = formatSpeed(rxSpeed)
    netTxSpeedStr = formatSpeed(txSpeed)

    var rxList = netRxHistory.slice(1)
    rxList.push(rxSpeed)
    netRxHistory = rxList

    var txList = netTxHistory.slice(1)
    txList.push(txSpeed)
    netTxHistory = txList
  }

  FileView {
    id: netDevFile
    path: "/proc/net/dev"
    onLoaded: sampler.sampleTraffic(text())
  }

  Timer {
    interval: sampler.pollIntervalMs
    running: true
    repeat: true
    onTriggered: netDevFile.reload()
  }
}
