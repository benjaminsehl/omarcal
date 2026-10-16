import QtQuick
import qs.Commons
import "Model.js" as Model

// Every colour the widget draws, resolved from the theme. A theme can tune
// any of them in its shell.toml; anything it leaves out follows the theme's
// popup ink and accent, so the widget looks right on themes that have never
// heard of it.
//
//   [calendar]
//   text             = "#dedad2"   # titles, times
//   dim              = "#8f8a82"   # secondary lines         (default: text at 62%)
//   faint            = "#6e6a63"   # labels, idle glyphs     (default: text at 38%)
//   rule             = "#dedad2"   # hairlines
//   rule-alpha       = 0.12
//   signal           = "#f0692b"   # now, starting soon      (default: accent)
//   join-background  = "#f0692b"   # Join, when it's time    (default: signal)
//   join-text        = "#0e0e0d"   #                         (default: popup background)
//   bar-signal       = "#f0692b"   # bar countdown when it's time (default: signal)
//   event-colors     = "calendar"  # calendar | mono | accent
//
// Values may be hex or a role name (foreground, accent, muted, background).
QtObject {
  id: theme

  function raw(key) {
    var v = Color.shellValues["calendar." + key]
    return typeof v === "string" && v.length > 0 ? v : ""
  }

  function role(key, fallback) {
    var v = raw(key)
    return v ? Color.flatColor(v, fallback) : fallback
  }

  function alphaOf(key, fallback) {
    var v = raw(key + "-alpha")
    var n = Number(v)
    return v && isFinite(n) ? Math.max(0, Math.min(1, n)) : fallback
  }

  readonly property color ink: role("text", Color.popups.text)
  readonly property color dim: role("dim", Util.alpha(ink, 0.62))
  readonly property color faint: role("faint", Util.alpha(ink, 0.38))
  readonly property color rule: Util.alpha(role("rule", ink), alphaOf("rule", 0.12))
  readonly property color signal: role("signal", Color.accent)
  readonly property color joinFill: role("join-background", signal)
  readonly property color joinText: role("join-text", Color.popups.background)
  readonly property color barSignal: role("bar-signal", signal)
  readonly property string swatches: Model.swatchMode(raw("event-colors"))

  function swatchColor(ev) {
    if (swatches === "mono") return dim
    if (swatches === "accent") return signal
    return ev && ev.color ? ev.color : dim
  }
}
