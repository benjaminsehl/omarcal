import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// State and actions for the calendar widget. All Google traffic goes through
// bin/omarcal, which prints one JSON object per call; this file never sees a
// token.
Item {
  id: root

  property var settings: ({})

  // ── Public state ──────────────────────────────────────────────────────
  // "loading" → first answer pending; "setup" → no OAuth client file;
  // "signedOut" → client but no token; "ready" → events (maybe stale).
  property string phase: "loading"
  property string account: ""
  property string clientFile: ""
  property var events: []
  property real fetchedAt: 0
  property bool stale: false
  property string lastError: ""
  // When an error has a fix on a web page (e.g. enabling the Calendar API),
  // the page; the panel offers it as a button.
  property string lastErrorUrl: ""
  property string notice: ""
  property bool fetching: false
  property bool authorizing: false
  property bool creating: false
  property string demo: ""
  property var notified: ({})
  property bool twelveHour: false

  property real now: Date.now()

  readonly property var opts: ({
    showDeclined: setting("showDeclined", false) === true,
    handoffMin: intSetting("handoffMinutes", 5, 0, 30)
  })
  readonly property var nextEvent: Model.focusEvent(events, now, opts)
  readonly property bool ready: phase === "ready"

  readonly property string helper: String(Qt.resolvedUrl("bin/omarcal")).replace(/^file:\/\//, "")
  readonly property int days: intSetting("days", 3, 1, 14)
  readonly property int refreshMinutes: intSetting("refreshMinutes", 5, 1, 60)
  readonly property int notifyMinutes: intSetting("notifyMinutesBefore", 1, -1, 30)

  // ── Helpers ───────────────────────────────────────────────────────────
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function say(text) {
    notice = String(text || "")
    noticeClear.restart()
  }

  function fail(reply) {
    var msg = reply && reply.message ? reply.message : "Something went wrong"
    lastError = msg
    lastErrorUrl = reply && reply.url ? reply.url : ""
  }

  function run(args, onDone) {
    var p = procComponent.createObject(root, { args: args })
    p.onDone = onDone
    p.running = true
  }

  Component {
    id: procComponent

    Process {
      id: proc
      property var args: []
      property var onDone: null
      property var lines: []
      command: [root.helper].concat(args)
      stdout: SplitParser { onRead: function(line) { proc.lines.push(line) } }
      stderr: SplitParser { onRead: function(line) { if (line.trim() !== "") console.warn("omarcal: " + line) } }
      onExited: function(code) {
        var reply = null
        for (var i = proc.lines.length - 1; i >= 0 && !reply; i--) {
          try { reply = JSON.parse(proc.lines[i]) } catch (e) {}
        }
        if (!reply) reply = { ok: false, error: "internal", message: "omarcal exited " + code + " without an answer" }
        if (proc.onDone) proc.onDone(reply)
        proc.destroy()
      }
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────
  function refresh() {
    if (demo !== "") return
    if (fetching) return
    fetching = true
    var args = ["events", "--days", String(days)]
    var cals = String(setting("calendars", "")).trim()
    if (cals !== "") args.push("--calendars", cals)
    run(args, function(reply) {
      fetching = false
      if (reply.ok) {
        events = reply.events || []
        account = reply.account || account
        fetchedAt = reply.fetchedAt || Date.now()
        stale = reply.stale === true
        lastError = reply.warning || ((reply.errors || []).length ? reply.errors.join("\n") : "")
        lastErrorUrl = ""
        phase = "ready"
        checkNotifications()
      } else if (reply.error === "no-client") {
        phase = "setup"
        events = []
        probeStatus()
      } else if (reply.error === "no-token") {
        phase = "signedOut"
        events = []
        lastError = reply.message !== "Not signed in" ? reply.message : ""
      } else {
        if (phase === "loading") phase = "ready"
        fail(reply)
      }
    })
  }

  // Shown on the setup screen, so the path in the instructions is the real one.
  function probeStatus() {
    run(["status"], function(reply) {
      clientFile = reply.clientFile || ""
      if (reply.configured && phase === "setup") phase = reply.authorized ? "ready" : "signedOut"
      if (reply.account) account = reply.account
    })
  }

  function signIn() {
    if (authorizing) return
    authorizing = true
    lastError = ""
    say("Continue in your browser")
    run(["auth"], function(reply) {
      authorizing = false
      if (!reply.ok) { fail(reply); return }
      account = reply.account || ""
      phase = "ready"
      say(account ? "Connected as " + account : "Connected")
      if (reply.missingScopes && reply.missingScopes.length)
        lastError = "Some permissions were not granted; creating meetings may not work."
      refresh()
    })
  }

  function signOut() {
    run(["logout"], function() {
      events = []
      account = ""
      phase = "signedOut"
      say("Signed out")
    })
  }

  function open(url) {
    if (!url) return
    var mode = String(setting("openWith", "browser"))
    if (mode === "webapp") Quickshell.execDetached(["omarchy-launch-webapp", url])
    else Quickshell.execDetached(["xdg-open", url])
  }

  function copy(text, label) {
    if (!text) return
    Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy", "copy", String(text)])
    say((label || "Link") + " copied")
  }

  function join(ev) {
    var url = Model.joinUrl(ev, account)
    if (url) open(url)
    else if (ev && ev.htmlLink) open(ev.htmlLink)
  }

  function joinFocus() {
    if (nextEvent && nextEvent.url) { join(nextEvent); return true }
    return false
  }

  // For hotkeys: there's no panel to show the outcome in, so anything other
  // than a call opening is said in a notification.
  function joinNext() {
    if (demo === "" && phase !== "ready") { toast("Calendar isn't connected", "Open the calendar in the bar to set it up."); return "not connected" }
    var ev = Model.joinable(events, now, opts)
    if (!ev) { toast("No meeting to join", "Nothing with a call link coming up."); return "none" }
    join(ev)
    return ev.title
  }

  function newMeetingNow() {
    if (demo === "" && phase !== "ready" && String(setting("newMeeting", "event")) !== "instant") {
      toast("Calendar isn't connected", "Opening meet.google.com/new instead.")
    }
    newMeeting(true)
  }

  function toast(title, body, argv) {
    var cmd = ["notify-send", "-a", "Calendar", "-h", "string:omarchy-glyph:󰃭"]
    if (argv) cmd.push("-h", "string:omarchy-exec-argv:" + JSON.stringify(argv))
    cmd.push(String(title), String(body || ""))
    Quickshell.execDetached(cmd)
  }

  function opener(url) {
    return String(setting("openWith", "browser")) === "webapp" ? ["omarchy-launch-webapp", url] : ["xdg-open", url]
  }

  function openCalendar() { open(Model.calendarUrl(account)) }

  // "event": a Meet on your calendar starting now (link copied, call opened).
  // "instant": meet.google.com/new, no calendar entry and no API call.
  function newMeeting(fromHotkey) {
    var mode = String(setting("newMeeting", "event"))
    if (mode === "instant" || !ready || demo !== "") {
      open("https://meet.google.com/new" + (account ? "?authuser=" + encodeURIComponent(account) : ""))
      return
    }
    if (creating) return
    creating = true
    run(["new", "--title", String(setting("newMeetingTitle", "Meet")), "--minutes", String(intSetting("newMeetingMinutes", 30, 5, 240))], function(reply) {
      creating = false
      if (!reply.ok) {
        fail(reply)
        if (fromHotkey) toast("Couldn't create a meeting", reply.message || "", reply.url ? opener(reply.url) : null)
        return
      }
      var url = Model.joinUrl({ url: reply.url, service: "meet" }, reply.account || account)
      copy(reply.url, "Meet link")
      open(url)
      if (fromHotkey) toast("Meet link copied", reply.url, opener(url))
      refresh()
    })
  }

  // ── Notifications ─────────────────────────────────────────────────────
  function checkNotifications() {
    if (notifyMinutes < 0 || !ready) return
    var due = Model.dueNotifications(events, now, notifyMinutes, notified, opts)
    if (due.length === 0) return
    var seen = {}
    for (var k in notified) seen[k] = true
    for (var i = 0; i < due.length; i++) {
      var ev = due[i]
      seen[Model.notifyKey(ev)] = true
      notify(ev)
    }
    notified = seen
  }

  function notify(ev) {
    var url = Model.joinUrl(ev, account) || ev.htmlLink || ""
    var body = Model.rangeLabel(ev, twelveHour)
      + (ev.url ? " · Click to join" + (ev.serviceName ? " " + ev.serviceName : "") : "")
    var argv = ["notify-send", "-a", "Calendar", "-h", "string:omarchy-glyph:󰃭"]
    if (url) argv.push("-h", "string:omarchy-exec-argv:" + JSON.stringify(opener(url)))
    argv.push(ev.title, body)
    Quickshell.execDetached(argv)
  }

  // ── Demo (screenshots, development) ───────────────────────────────────
  function setDemo(scenario) {
    demo = String(scenario || "")
    if (demo === "" || demo === "off") {
      demo = ""
      events = []
      account = ""
      fetchedAt = 0
      phase = "loading"
      refresh()
      return "off"
    }
    if (demo === "setup" || demo === "signedOut") { phase = demo; events = []; return demo }
    account = "you@example.com"
    events = Model.demoEvents(Date.now(), demo)
    fetchedAt = Date.now()
    stale = false
    lastError = ""
    phase = "ready"
    return demo
  }

  // ── Clocks ────────────────────────────────────────────────────────────
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.now = clock.date.getTime()
      root.checkNotifications()
    }
  }

  Timer {
    interval: root.refreshMinutes * 60000
    running: root.demo === "" && (root.phase === "ready" || root.phase === "loading")
    repeat: true
    onTriggered: root.refresh()
  }

  // A suspended laptop wakes with the minute clock still right but the event
  // list hours old; a jump in wall time is the cheapest way to notice.
  property real lastTick: Date.now()
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: {
      var t = Date.now()
      if (t - root.lastTick > 120000) { root.now = t; root.refresh() }
      root.lastTick = t
    }
  }

  Timer { id: noticeClear; interval: 3500; onTriggered: root.notice = "" }

  Component.onCompleted: refresh()
}
