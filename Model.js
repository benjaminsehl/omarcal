.pragma library

// Pure functions for the calendar widget: what's next, what to call it, how
// to group the rest. No Qt, no I/O — tests/model.test.mjs runs these in node.
//
// An event (as emitted by bin/omarcal):
//   { id, uid, calendarId, calendar, color, primary, title, start, end (ms),
//     allDay, location, url, service, serviceName, htmlLink,
//     response: accepted|tentative|needsAction|declined, guests, organizer,
//     organizerSelf, type, status }

var MINUTE = 60000
var HOUR = 60 * MINUTE
var DAY = 24 * HOUR

var MONTHS = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"]
var WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

// ── Time ────────────────────────────────────────────────────────────────────

function startOfDay(ms) {
  var d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

function addDays(ms, n) {
  var d = new Date(ms)
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n).getTime()
}

function dayKey(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function pad(n) { return n < 10 ? "0" + n : String(n) }

// A clock format with an AM/PM marker means the person reads 12-hour time.
function uses12h(format) {
  return /a|AP/i.test(String(format || "").replace(/'[^']*'/g, ""))
}

function timeLabel(ms, twelve) {
  var d = new Date(ms)
  var h = d.getHours(), m = d.getMinutes()
  if (!twelve) return pad(h) + ":" + pad(m)
  var h12 = h % 12 === 0 ? 12 : h % 12
  return h12 + ":" + pad(m) + (h < 12 ? " AM" : " PM")
}

// "10:30" / "10:30 AM": short and fixed-width enough for the time column.
function compactTime(ms, twelve) {
  var d = new Date(ms)
  if (!twelve) return pad(d.getHours()) + ":" + pad(d.getMinutes())
  var h = d.getHours(), h12 = h % 12 === 0 ? 12 : h % 12
  return h12 + ":" + pad(d.getMinutes())
}

function meridiem(ms) { return new Date(ms).getHours() < 12 ? "AM" : "PM" }

function rangeLabel(ev, twelve) {
  if (ev.allDay) return "All day"
  var sameHalf = !twelve || meridiem(ev.start) === meridiem(ev.end)
  var a = twelve && sameHalf ? compactTime(ev.start, true) : timeLabel(ev.start, twelve)
  return a + "–" + timeLabel(ev.end, twelve)
}

// "12 min", "1 h 5 min", "3 h". Rounds up: a meeting 30 s away is "1 min",
// never "0 min".
function durationLabel(ms) {
  var mins = Math.max(0, Math.ceil(ms / MINUTE))
  if (mins < 60) return mins + " min"
  var h = Math.floor(mins / 60), m = mins % 60
  return m === 0 ? h + " h" : h + " h " + m + " min"
}

// The same, as tight as a bar slot: "12m", "1h 5m".
function shortDuration(ms) {
  var mins = Math.max(0, Math.ceil(ms / MINUTE))
  if (mins < 60) return mins + "m"
  var h = Math.floor(mins / 60), m = mins % 60
  return m === 0 ? h + "h" : h + "h " + m + "m"
}

function dayLabel(ms, now) {
  var diff = Math.round((startOfDay(ms) - startOfDay(now)) / DAY)
  if (diff === 0) return "Today"
  if (diff === 1) return "Tomorrow"
  if (diff === -1) return "Yesterday"
  var d = new Date(ms)
  return WEEKDAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
}

function dateLine(now) {
  var d = new Date(now)
  return WEEKDAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
}

function isoWeek(ms) {
  var d = new Date(ms)
  var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
  var day = t.getUTCDay() || 7
  t.setUTCDate(t.getUTCDate() + 4 - day)
  var yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
  return Math.ceil(((t - yearStart) / DAY + 1) / 7)
}

// ── State of an event ───────────────────────────────────────────────────────

function isOngoing(ev, now) { return !ev.allDay && ev.start <= now && now < ev.end }
function isPast(ev, now) { return ev.end <= now }
function isUpcoming(ev, now) { return ev.start > now }
function isDeclined(ev) { return ev.response === "declined" }
function isTentative(ev) { return ev.response === "tentative" || ev.response === "needsAction" }
function progress(ev, now) {
  if (ev.end <= ev.start) return 0
  return Math.max(0, Math.min(1, (now - ev.start) / (ev.end - ev.start)))
}

// Only things you'd actually go to: timed, not declined, not a focus-time
// block or an out-of-office marker.
function attendable(ev, opts) {
  if (ev.allDay) return false
  if (!opts.showDeclined && isDeclined(ev)) return false
  return ev.type !== "focusTime" && ev.type !== "outOfOffice"
}

function visible(events, opts) {
  var list = []
  for (var i = 0; i < (events || []).length; i++) {
    var ev = events[i]
    if (!opts.showDeclined && isDeclined(ev)) continue
    list.push(ev)
  }
  return list
}

// The one event the panel leads with and the bar talks about.
//
// While a meeting is on, it stays the focus — unless the next one starts
// within `handoffMin` minutes, because by then the useful button is the one
// that joins the next call. Among overlapping meetings, the one with a call
// link wins: it's the one you can do something about.
function focusEvent(events, now, opts) {
  opts = opts || {}
  var handoff = (opts.handoffMin === undefined ? 5 : opts.handoffMin) * MINUTE
  var ongoing = null, next = null
  for (var i = 0; i < (events || []).length; i++) {
    var ev = events[i]
    if (!attendable(ev, opts)) continue
    if (isOngoing(ev, now)) {
      if (!ongoing || (!!ev.url && !ongoing.url) || (!!ev.url === !!ongoing.url && ev.start > ongoing.start)) ongoing = ev
    } else if (isUpcoming(ev, now)) {
      if (!next || ev.start < next.start || (ev.start === next.start && !!ev.url && !next.url)) next = ev
    }
  }
  if (ongoing && next && next.start - now <= handoff) return next
  return ongoing || next
}

// "in 12 min", "Now · 18 min left", "Tomorrow 9:00 AM", "Starting"
function countdown(ev, now, twelve) {
  if (!ev) return ""
  if (isOngoing(ev, now)) return "Now · " + durationLabel(ev.end - now) + " left"
  var until = ev.start - now
  if (until <= 0) return "Starting"
  if (startOfDay(ev.start) === startOfDay(now) || until < 3 * HOUR) return "in " + durationLabel(until)
  return dayLabel(ev.start, now) + " " + timeLabel(ev.start, twelve)
}

// Is it time to act? Close enough to start, or just started.
function urgent(ev, now, soonMin) {
  if (!ev || ev.allDay) return false
  var soon = (soonMin === undefined ? 5 : soonMin) * MINUTE
  if (isUpcoming(ev, now)) return ev.start - now <= soon
  return isOngoing(ev, now) && now - ev.start <= soon
}

// ── Bar ─────────────────────────────────────────────────────────────────────

function elide(text, max) {
  var s = String(text || "")
  if (max <= 0 || s.length <= max) return s
  return s.slice(0, Math.max(1, max - 1)).replace(/\s+$/, "") + "…"
}

// What follows the time in the bar, or "" when nothing is close enough to
// be worth the space. mode: "off" | "countdown" | "title".
function barSuffix(ev, now, opts) {
  opts = opts || {}
  var mode = opts.mode || "title"
  if (!ev || mode === "off") return ""
  var lookahead = (opts.lookaheadMin === undefined ? 60 : opts.lookaheadMin) * MINUTE
  var ongoing = isOngoing(ev, now)
  if (!ongoing && ev.start - now > lookahead) return ""
  var when = ongoing ? shortDuration(ev.end - now) + " left" : "in " + shortDuration(ev.start - now)
  if (mode === "countdown") return when
  return elide(ev.title, opts.titleLength === undefined ? 24 : opts.titleLength) + " " + when
}

function barTooltip(ev, now, twelve) {
  if (!ev) return "Nothing coming up"
  return ev.title + "\n" + rangeLabel(ev, twelve) + " · " + countdown(ev, now, twelve)
}

// ── Agenda ──────────────────────────────────────────────────────────────────

// Days for the list under the focus block:
//   [{ key, label, start, allDay: [ev], timed: [ev] }]
// The focus event is left out (it's already shown above), past events are
// dropped unless asked for, and empty days are skipped — except today, which
// always appears so "nothing else today" has somewhere to be said.
function agenda(events, now, opts) {
  opts = opts || {}
  var focus = opts.focus || null
  var limit = opts.maxEvents || 12
  var days = opts.days || 3
  var today = startOfDay(now)
  var end = addDays(today, days)
  var byDay = {}
  var order = []
  var count = 0

  function bucket(ms) {
    var key = dayKey(ms)
    if (!byDay[key]) {
      byDay[key] = { key: key, label: dayLabel(ms, now), start: startOfDay(ms), allDay: [], timed: [] }
      order.push(key)
    }
    return byDay[key]
  }

  bucket(today)
  var list = visible(events, opts).slice().sort(function(a, b) { return a.start - b.start || a.end - b.end })
  for (var i = 0; i < list.length; i++) {
    var ev = list[i]
    if (focus && ev.id === focus.id && ev.start === focus.start) continue
    if (ev.allDay) {
      // Multi-day all-day events appear on each day they cover, from today.
      for (var d = Math.max(startOfDay(ev.start), today); d < Math.min(ev.end, end); d = addDays(d, 1))
        bucket(d).allDay.push(ev)
      continue
    }
    if (ev.start >= end) continue
    if (!opts.showPast && isPast(ev, now)) continue
    if (count >= limit) continue
    // An event that started before today (overnight) belongs to today.
    bucket(Math.max(ev.start, today)).timed.push(ev)
    count++
  }

  order.sort()
  var out = []
  for (var j = 0; j < order.length; j++) {
    var day = byDay[order[j]]
    if (day.start !== today && day.allDay.length === 0 && day.timed.length === 0) continue
    out.push(day)
  }
  return out
}

function emptyTodayLabel(events, now, opts) {
  var next = focusEvent(events, now, opts)
  if (!next) return "Nothing on your calendar."
  if (startOfDay(next.start) === startOfDay(now)) return ""
  return "Nothing else today."
}

function guestsLabel(ev) {
  var parts = []
  if (ev.serviceName) parts.push(ev.serviceName)
  else if (ev.location) parts.push(ev.location)
  if (ev.guests > 0) parts.push(ev.guests === 1 ? "1 guest" : ev.guests + " guests")
  if (ev.response === "needsAction") parts.push("Not answered")
  else if (ev.response === "tentative") parts.push("Maybe")
  return parts.join(" · ")
}

// Meet keeps you in whichever Google account the browser last used; asking
// for the calendar's account by name saves a wrong-account bounce.
function joinUrl(ev, account) {
  if (!ev || !ev.url) return ""
  if (ev.service !== "meet" || !account || /[?&]authuser=/.test(ev.url)) return ev.url
  return ev.url + (ev.url.indexOf("?") === -1 ? "?" : "&") + "authuser=" + encodeURIComponent(account)
}

function calendarUrl(account) {
  return "https://calendar.google.com/calendar/r" + (account ? "?authuser=" + encodeURIComponent(account) : "")
}

// ── Notifications ───────────────────────────────────────────────────────────

// Events that should ring now: starting within `leadMin` minutes, not yet
// notified (`seen` is a { key: true } map), attendable.
function dueNotifications(events, now, leadMin, seen, opts) {
  var lead = (leadMin === undefined ? 1 : leadMin) * MINUTE
  var due = []
  for (var i = 0; i < (events || []).length; i++) {
    var ev = events[i]
    if (!attendable(ev, opts || {})) continue
    var k = notifyKey(ev)
    if (seen[k]) continue
    var until = ev.start - now
    // A minute of slack on the far side so a tick that lands just after the
    // start still rings, without replaying old meetings after a resume.
    if (until <= lead && until > -MINUTE) due.push(ev)
  }
  return due
}

function notifyKey(ev) { return ev.id + "@" + ev.start }

// ── Theme ───────────────────────────────────────────────────────────────────

// "calendar": each calendar's own colour; "mono": ink only; "accent": the
// theme accent for everything. Tentative/unanswered events draw hollow.
function swatchMode(value) {
  var v = String(value || "").toLowerCase()
  return v === "mono" || v === "accent" ? v : "calendar"
}

// ── Demo data ───────────────────────────────────────────────────────────────

function demoEvents(now, scenario) {
  // Quarter hours, like a real calendar; the first meeting is the next
  // quarter (or the one just started, for "now").
  var quarter = 15 * MINUTE
  var base = Math.ceil(now / quarter) * quarter
  var today = startOfDay(now)
  function at(dayOffset, h, m) { return addDays(today, dayOffset) + h * HOUR + (m || 0) * MINUTE }
  function ev(id, title, start, mins, extra) {
    var e = { id: id, uid: id, calendarId: "me@example.com", calendar: "Work", color: "#7fb2ac", primary: true,
      title: title, start: start, end: start + mins * MINUTE, allDay: false, location: "", url: "", service: "",
      serviceName: "", htmlLink: "https://calendar.google.com/", response: "accepted", guests: 0,
      organizer: "", organizerSelf: false, type: "default", status: "confirmed" }
    for (var k in extra) e[k] = extra[k]
    return e
  }
  var meet = { url: "https://meet.google.com/abc-defg-hij", service: "meet", serviceName: "Google Meet" }
  function withMeet(extra) { var o = {}; for (var k in meet) o[k] = meet[k]; for (var j in extra) o[j] = extra[j]; return o }

  if (scenario === "empty") return []
  var list = []
  if (scenario === "now") {
    list.push(ev("d1", "Design review", base - quarter, 45, withMeet({ guests: 6 })))
  } else {
    list.push(ev("d1", "Design review", base, 30, withMeet({ guests: 6 })))
  }
  list.push(ev("d0", "Standup", base - 90 * MINUTE, 15, withMeet({ guests: 8 })))
  list.push(ev("d2", "1:1 with Alex", base + 60 * MINUTE, 30, withMeet({ guests: 1, response: "needsAction" })))
  list.push(ev("d3", "Lunch", base + 135 * MINUTE, 60, { calendar: "Personal", color: "#f2b705", location: "Café Eins" }))
  list.push(ev("d4", "Roadmap sync", base + 225 * MINUTE, 50,
    { url: "https://us02web.zoom.us/j/123456789", service: "zoom", serviceName: "Zoom", guests: 12, response: "tentative" }))
  list.push({ id: "d5", uid: "d5", calendarId: "holidays", calendar: "Holidays", color: "#a57e55", primary: false,
    title: "Thanksgiving", start: addDays(today, 1), end: addDays(today, 2), allDay: true, location: "", url: "",
    service: "", serviceName: "", htmlLink: "", response: "accepted", guests: 0, organizer: "", organizerSelf: false,
    type: "default", status: "confirmed" })
  list.push(ev("d6", "Planning", at(1, 9, 30), 60, withMeet({ guests: 4 })))
  list.push(ev("d7", "Interview: Product designer", at(1, 14, 0), 45, withMeet({ guests: 3 })))
  return list
}
