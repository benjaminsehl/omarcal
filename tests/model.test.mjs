// Run: node --test tests/
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const src = readFileSync(new URL("../Model.js", import.meta.url), "utf8").replace(/^\.pragma library\s*/, "")
const M = {}
vm.runInNewContext(src + "\nObject.assign(out, {" +
  [...src.matchAll(/^function (\w+)/gm)].map((m) => m[1]).join(",") + "})", { out: M })

const same = (a, b) => assert.deepEqual(JSON.parse(JSON.stringify(a)), b)
const MIN = 60000
const NOW = new Date(2026, 9, 16, 10, 0).getTime() // Fri 16 Oct 2026, 10:00 local

function ev(id, startMin, mins, extra = {}) {
  return { id, uid: id, title: id, start: NOW + startMin * MIN, end: NOW + (startMin + mins) * MIN,
    allDay: false, url: "", service: "", response: "accepted", type: "default", guests: 0, ...extra }
}

test("12-hour detection follows the bar's clock format", () => {
  assert.equal(M.uses12h("h:mm AP"), true)
  assert.equal(M.uses12h("HH:mm"), false)
  assert.equal(M.uses12h("dddd HH:mm"), false)
  assert.equal(M.uses12h("HH:mm 'at' ap"), true)
})

test("time and range labels", () => {
  const e = ev("x", 30, 30)
  assert.equal(M.rangeLabel(e, false), "10:30–11:00")
  assert.equal(M.rangeLabel(e, true), "10:30–11:00 AM")
  assert.equal(M.rangeLabel(ev("y", 90, 60), true), "11:30 AM–12:30 PM")
  assert.equal(M.timeLabel(new Date(2026, 9, 16, 0, 5).getTime(), true), "12:05 AM")
})

test("durations round up and stay short", () => {
  assert.equal(M.durationLabel(30 * 1000), "1 min")
  assert.equal(M.durationLabel(65 * MIN), "1 h 5 min")
  assert.equal(M.durationLabel(120 * MIN), "2 h")
  assert.equal(M.shortDuration(12 * MIN), "12m")
  assert.equal(M.shortDuration(61 * MIN), "1h 1m")
})

test("focus is the next meeting, or the current one", () => {
  assert.equal(M.focusEvent([ev("a", 30, 30), ev("b", 10, 30)], NOW).id, "b")
  assert.equal(M.focusEvent([ev("now", -10, 30), ev("later", 30, 30)], NOW).id, "now")
})

test("focus hands off to the next meeting when it's about to start", () => {
  assert.equal(M.focusEvent([ev("now", -25, 30), ev("next", 4, 30)], NOW).id, "next")
  assert.equal(M.focusEvent([ev("now", -25, 30), ev("next", 4, 30)], NOW, { handoffMin: 2 }).id, "now")
})

test("focus prefers the overlapping meeting you can join", () => {
  const plain = ev("plain", -5, 60)
  const call = ev("call", -20, 60, { url: "https://meet.google.com/a-b-c" })
  assert.equal(M.focusEvent([plain, call], NOW).id, "call")
})

test("focus ignores all-day, declined, focus time and OOO", () => {
  const list = [
    ev("allday", -600, 1440, { allDay: true }),
    ev("declined", 5, 30, { response: "declined" }),
    ev("focus", 10, 60, { type: "focusTime" }),
    ev("ooo", 15, 60, { type: "outOfOffice" }),
    ev("real", 20, 30),
  ]
  assert.equal(M.focusEvent(list, NOW).id, "real")
  assert.equal(M.focusEvent(list, NOW, { showDeclined: true }).id, "declined")
  assert.equal(M.focusEvent([], NOW), null)
})

test("countdown wording", () => {
  assert.equal(M.countdown(ev("a", 12, 30), NOW, false), "in 12 min")
  assert.equal(M.countdown(ev("a", -10, 30), NOW, false), "Now · 20 min left")
  const tomorrow = ev("t", 23 * 60 + 30, 30) // 09:30 tomorrow
  assert.equal(M.countdown(tomorrow, NOW, true), "Tomorrow 9:30 AM")
})

test("urgency: about to start, or just started", () => {
  assert.equal(M.urgent(ev("a", 4, 30), NOW), true)
  assert.equal(M.urgent(ev("a", 6, 30), NOW), false)
  assert.equal(M.urgent(ev("a", -3, 30), NOW), true)
  assert.equal(M.urgent(ev("a", -10, 30), NOW), false)
})

test("bar suffix only when something is close", () => {
  const e = ev("Design review", 12, 30)
  assert.equal(M.barSuffix(e, NOW, { mode: "title" }), "Design review in 12m")
  assert.equal(M.barSuffix(e, NOW, { mode: "countdown" }), "in 12m")
  assert.equal(M.barSuffix(e, NOW, { mode: "off" }), "")
  assert.equal(M.barSuffix(ev("far", 120, 30), NOW, { lookaheadMin: 60 }), "")
  assert.equal(M.barSuffix(ev("Standup", -5, 15), NOW, {}), "Standup 10m left")
  assert.equal(M.barSuffix(ev("A very long meeting title indeed", 5, 15), NOW, { titleLength: 10 }), "A very lo… in 5m")
})

test("agenda groups by day, drops the past and the focus event", () => {
  const focus = ev("focus", 10, 30)
  const list = [
    ev("past", -120, 30),
    focus,
    ev("later", 120, 30),
    ev("tomorrow", 24 * 60, 30),
    ev("holiday", -600, 1440 * 2, { allDay: true, start: M.startOfDay(NOW), end: M.addDays(M.startOfDay(NOW), 2) }),
  ]
  const days = M.agenda(list, NOW, { focus, days: 3 })
  same(days.map((d) => d.label), ["Today", "Tomorrow"])
  same(days[0].timed.map((e) => e.id), ["later"])
  same(days[1].timed.map((e) => e.id), ["tomorrow"])
  same(days.map((d) => d.allDay.map((e) => e.id)), [["holiday"], ["holiday"]])
})

test("agenda keeps today even when it's empty and skips empty later days", () => {
  const days = M.agenda([ev("t", 48 * 60, 30)], NOW, { days: 3 })
  assert.equal(days.length, 2)
  assert.equal(days[0].label, "Today")
  assert.equal(days[0].timed.length, 0)
  assert.equal(days[1].label, "Sunday 18 October")
})

test("agenda respects maxEvents and hides declined", () => {
  const list = [ev("a", 30, 10), ev("b", 60, 10, { response: "declined" }), ev("c", 90, 10), ev("d", 120, 10)]
  const days = M.agenda(list, NOW, { maxEvents: 2 })
  same(days[0].timed.map((e) => e.id), ["a", "c"])
})

test("join URL asks Meet for the calendar's account", () => {
  const e = ev("m", 5, 30, { url: "https://meet.google.com/abc-defg-hij", service: "meet" })
  assert.equal(M.joinUrl(e, "me@x.com"), "https://meet.google.com/abc-defg-hij?authuser=me%40x.com")
  assert.equal(M.joinUrl({ ...e, url: e.url + "?authuser=1" }, "me@x.com"), e.url + "?authuser=1")
  const z = ev("z", 5, 30, { url: "https://zoom.us/j/1", service: "zoom" })
  assert.equal(M.joinUrl(z, "me@x.com"), "https://zoom.us/j/1")
  assert.equal(M.joinUrl(ev("none", 5, 30), "me@x.com"), "")
})

test("notifications ring once, near the start", () => {
  const e = ev("a", 1, 30)
  assert.equal(M.dueNotifications([e], NOW, 1, {}).length, 1)
  assert.equal(M.dueNotifications([e], NOW, 1, { [M.notifyKey(e)]: true }).length, 0)
  assert.equal(M.dueNotifications([ev("b", 3, 30)], NOW, 1, {}).length, 0)
  assert.equal(M.dueNotifications([ev("old", -5, 30)], NOW, 1, {}).length, 0)
})

test("guests label", () => {
  assert.equal(M.guestsLabel({ serviceName: "Google Meet", guests: 6, response: "accepted" }), "Google Meet · 6 guests")
  assert.equal(M.guestsLabel({ serviceName: "", location: "Room 4", guests: 1, response: "needsAction" }), "Room 4 · 1 guest · Not answered")
})

test("ISO week", () => {
  assert.equal(M.isoWeek(NOW), 42)
  assert.equal(M.isoWeek(new Date(2027, 0, 1).getTime()), 53)
})

test("demo data is well formed", () => {
  for (const s of ["", "now", "empty"]) {
    const list = M.demoEvents(NOW, s)
    for (const e of list) assert.ok(e.end > e.start && e.title)
  }
  assert.equal(M.focusEvent(M.demoEvents(NOW, "now"), NOW).id, "d1")
})
