import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock, made useful: the bar keeps the time and adds what's next when
// it's close; the panel answers "what do I have, and can I join it?".
//
// Design notes — after Rams:
//   * Useful: the panel leads with the one meeting that matters now, and
//     its Join button. Everything else is a list you can read in a glance.
//   * Unobtrusive: no hero date, no month grid. The date is a printed label.
//   * Honest: colour means something. The signal colour marks "it's time"
//     and nothing else; tentative meetings are drawn hollow, not hidden.
//   * Thorough: keyboard all the way (Enter joins, n new, c copy, o open,
//     r refresh), notifications that join on click, offline cache.
//   * As little design as possible: one typeface, the theme's scale, hairlines.
Panel {
  id: root
  moduleName: "sehl.omarcal"
  ipcTarget: "sehl.omarcal"
  manageIpc: false

  // ── Look ──────────────────────────────────────────────────────────────
  CalendarTheme { id: theme }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color hoverFill: Style.hoverFillFor(theme.ink, Color.accent)

  // ── Clock ─────────────────────────────────────────────────────────────
  readonly property string clockFormat: vertical
    ? String(setting("verticalFormat", "HH\n—\nmm"))
    : String(setting("format", "HH:mm"))
  readonly property bool twelve: setting("twelveHour", null) !== null
    ? setting("twelveHour", false) === true
    : Model.uses12h(setting("format", "HH:mm"))
  readonly property string timeText: Qt.formatDateTime(clock.date,
    clockFormat.replace(/ww/g, "'" + Model.isoWeek(clock.date.getTime()) + "'"))

  // ── Calendar state ────────────────────────────────────────────────────
  readonly property real now: cal.now
  readonly property var focusEv: cal.nextEvent
  readonly property bool focusUrgent: Model.urgent(focusEv, now, intSetting("soonMinutes", 5))
  readonly property bool focusOngoing: !!focusEv && Model.isOngoing(focusEv, now)
  readonly property string barSuffix: cal.ready ? Model.barSuffix(focusEv, now, {
    mode: String(setting("barNext", "title")),
    lookaheadMin: intSetting("barLookaheadMinutes", 60),
    titleLength: intSetting("barTitleLength", 24)
  }) : ""
  readonly property var days: Model.agenda(cal.events, now, {
    focus: focusEv,
    days: cal.days,
    maxEvents: intSetting("maxEvents", 12),
    showPast: setting("showPast", false) === true,
    showDeclined: setting("showDeclined", false) === true
  })
  readonly property string emptyToday: Model.emptyTodayLabel(cal.events, now, cal.opts)

  function intSetting(name, fallback) {
    var n = parseInt(String(setting(name, fallback)), 10)
    return isFinite(n) ? n : fallback
  }

  // ── Keyboard cursor ───────────────────────────────────────────────────
  property bool cursorActive: false
  property string cursorKey: ""

  readonly property var navKeys: {
    var keys = []
    if (cal.lastErrorUrl !== "") { keys.push("fix"); keys.push("retry") }
    if (cal.phase === "signedOut") keys.push("connect")
    if (cal.phase === "setup") { keys.push("console"); keys.push("recheck") }
    if (!cal.ready) return keys
    if (focusEv) keys.push("join")
    for (var d = 0; d < days.length; d++) {
      var list = days[d].allDay.concat(days[d].timed)
      for (var i = 0; i < list.length; i++) keys.push("ev:" + Model.notifyKey(list[i]))
    }
    keys.push("new"); keys.push("calendar"); keys.push("refresh"); keys.push("signout")
    return keys
  }

  function hasCursor(key) { return cursorActive && cursorKey === key }
  function hover(key) { cursorActive = true; cursorKey = key }

  function moveCursor(dy) {
    if (navKeys.length === 0) return
    var i = navKeys.indexOf(cursorKey)
    i = i === -1 ? 0 : Math.max(0, Math.min(navKeys.length - 1, i + dy))
    cursorKey = navKeys[i]
    scrollToCursor()
  }

  function eventByKey(key) {
    var all = cal.events
    for (var i = 0; i < all.length; i++) if ("ev:" + Model.notifyKey(all[i]) === key) return all[i]
    return null
  }

  function activate(key) {
    if (key === "join") activateEvent(focusEv)
    else if (key === "connect") cal.signIn()
    else if (key === "console") cal.open("https://console.cloud.google.com/apis/credentials")
    else if (key === "recheck" || key === "retry") cal.refresh()
    else if (key === "fix") cal.open(cal.lastErrorUrl)
    else if (key === "new") cal.newMeeting()
    else if (key === "calendar") cal.openCalendar()
    else if (key === "refresh") cal.refresh()
    else if (key === "signout") cal.signOut()
    else if (key.indexOf("ev:") === 0) activateEvent(eventByKey(key))
  }

  // A row with a call joins it; one without opens it in Google Calendar.
  function activateEvent(ev) {
    if (!ev) return
    cal.join(ev)
    if (setting("closeOnJoin", true) !== false) close()
  }

  function scrollToCursor() {
    Qt.callLater(function() {
      var item = findNavItem(column, cursorKey)
      if (!item) return
      var margin = Style.space(6)
      var top = item.mapToItem(flick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < flick.contentY + margin) flick.contentY = Math.max(0, top - margin)
      else if (bottom > flick.contentY + flick.height - margin) flick.contentY = Math.min(maxY, bottom + margin - flick.height)
    })
  }

  function findNavItem(item, key) {
    if (!item) return null
    if (item.navKey === key && item.visible) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var found = findNavItem(kids[i], key)
      if (found) return found
    }
    return null
  }

  // Summoning by hotkey moves no pointer; keep the bar's hover reveal from
  // sticking behind the panel (same as the built-in clock).
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorKey = navKeys.length ? navKeys[0] : ""
      flick.contentY = 0
      cal.now = Date.now()
      if (Date.now() - cal.fetchedAt > 60000) cal.refresh()
      Qt.callLater(function() {
        if (root.opened) root.setCenterHoverRevealSuppressed(true)
        keyCatcher.forceActiveFocus()
      })
    } else {
      setCenterHoverRevealSuppressed(false)
    }
  }
  onNavKeysChanged: if (navKeys.indexOf(cursorKey) === -1) cursorKey = navKeys.length ? navKeys[0] : ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: cal
    settings: root.settings
    twelveHour: root.twelve
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { cal.refresh(); return "ok" }
    function join(): string { return cal.joinFocus() ? "ok" : "no meeting to join" }
    function newMeeting(): string { cal.newMeeting(); return "ok" }
    function openCalendar(): string { cal.openCalendar(); return "ok" }
    function signIn(): string { cal.signIn(); return "ok" }
    function demo(scenario: string): string { return cal.setDemo(scenario) }
    function status(): string {
      return JSON.stringify({
        phase: cal.phase, account: cal.account, events: cal.events.length,
        fetchedAt: cal.fetchedAt, stale: cal.stale, error: cal.lastError,
        next: root.focusEv ? { title: root.focusEv.title, start: root.focusEv.start, url: root.focusEv.url } : null,
        bar: root.barSuffix
      })
    }
  }

  // ── Bar ───────────────────────────────────────────────────────────────
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    fixedWidth: root.vertical ? -1 : barRow.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? verticalColumn.implicitHeight + scaledVerticalPadding : -1
    tooltipText: cal.ready && root.focusEv ? Model.barTooltip(root.focusEv, root.now, root.twelve) : ""

    onPressed: function(b) {
      if (b === Qt.RightButton) { if (!cal.joinFocus()) root.toggle() }
      else if (b === Qt.MiddleButton) cal.newMeeting()
      else root.toggle()
    }

    Row {
      id: barRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(9)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.timeText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      // A short rule between the time and the meeting, like the divider on
      // a Braun faceplate.
      Rectangle {
        visible: root.barSuffix !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(1, Style.spacing.hairline)
        height: Math.round(button.fontSize * 0.9)
        color: Util.alpha(button.foreground, 0.3)
      }

      Text {
        visible: root.barSuffix !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.barSuffix
        color: root.focusUrgent ? theme.barSignal : Util.alpha(button.foreground, 0.72)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: 160 } }
      }
    }

    Column {
      id: verticalColumn
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(4)

      Repeater {
        model: root.timeText.split("\n")
        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: button.foreground
        }
      }

      Rectangle {
        visible: root.focusUrgent
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(5)
        height: width
        radius: Style.cornerRadius > 0 ? width / 2 : 0
        color: theme.barSignal
      }
    }
  }

  // ── Panel ─────────────────────────────────────────────────────────────
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(intSetting("panelWidth", 380)))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dy !== 0 ? dy : dx)
      }
      onActivateRequested: {
        if (root.cursorActive) root.activate(root.cursorKey)
        else if (root.focusEv) root.activateEvent(root.focusEv)
        else if (cal.phase === "signedOut") cal.signIn()
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var k = t.toLowerCase()
        if (k === "n") cal.newMeeting()
        else if (k === "o") cal.openCalendar()
        else if (k === "r") cal.refresh()
        else if (k === "c") {
          var ev = root.cursorKey.indexOf("ev:") === 0 ? root.eventByKey(root.cursorKey) : root.focusEv
          if (ev && ev.url) cal.copy(ev.url, ev.serviceName ? ev.serviceName + " link" : "Link")
        }
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          // ── Printed label: the date, small. The bar already says the time.
          Item {
            width: parent.width
            implicitHeight: dateLabel.implicitHeight

            Text {
              id: dateLabel
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: Model.dateLine(root.now).toUpperCase()
              color: theme.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Text {
              anchors.right: parent.right
              anchors.baseline: dateLabel.baseline
              textFormat: Text.PlainText
              text: "W" + Model.isoWeek(root.now)
              color: theme.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: cal.lastError !== "" ? cal.lastError : cal.notice
            color: cal.lastError !== "" ? Color.urgent : theme.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          RowLayout {
            visible: cal.lastErrorUrl !== ""
            width: parent.width
            spacing: Style.space(8)
            ActionButton {
              navKey: "fix"
              text: cal.lastErrorUrl.indexOf("calendar-json") !== -1 ? "Enable Calendar API" : "Open in Google Cloud"
              onClicked: cal.open(cal.lastErrorUrl)
            }
            Item { Layout.fillWidth: true }
            ActionButton { navKey: "retry"; text: cal.fetching ? "Checking…" : "Check again"; quiet: true; onClicked: cal.refresh() }
          }

          // ── Not set up ─────────────────────────────────────────────────
          Hint {
            visible: cal.phase === "loading"
            text: "Loading…"
          }

          Column {
            visible: cal.phase === "setup"
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Connect Google Calendar"
              color: theme.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Hint {
              text: "Google only talks to apps you register. It takes a few minutes, once.\n\n"
                + "1. In a Google Cloud project, enable the Google Calendar API.\n"
                + "2. Google Auth Platform → Get started (Internal, for a Workspace account).\n"
                + "3. Clients → Create client → Desktop app → Download JSON.\n"
                + "4. Save it as:"
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: cal.clientFile || "~/.config/omarcal/client_secret.json"
              color: theme.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              ActionButton { navKey: "console"; text: "Open Google Cloud"; onClicked: root.activate("console") }
              Item { Layout.fillWidth: true }
              ActionButton { navKey: "recheck"; text: "Check again"; quiet: true; onClicked: cal.refresh() }
            }
          }

          Column {
            visible: cal.phase === "signedOut"
            width: parent.width
            spacing: Style.space(10)

            Hint { text: "See what's next and join calls from here." }

            ActionButton {
              navKey: "connect"
              text: cal.authorizing ? "Waiting for the browser…" : "Connect Google Calendar"
              enabled: !cal.authorizing
              onClicked: cal.signIn()
            }
          }

          // ── The one that matters now ───────────────────────────────────
          Column {
            id: focusBlock
            visible: cal.ready && !!root.focusEv
            width: parent.width
            spacing: Style.space(6)
            readonly property var ev: root.focusEv

            Item {
              width: parent.width
              implicitHeight: whenText.implicitHeight

              Text {
                id: whenText
                anchors.left: parent.left
                textFormat: Text.PlainText
                text: focusBlock.ev ? Model.countdown(focusBlock.ev, root.now, root.twelve) : ""
                color: root.focusUrgent ? theme.signal : theme.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.right: parent.right
                anchors.baseline: whenText.baseline
                textFormat: Text.PlainText
                text: focusBlock.ev ? Model.rangeLabel(focusBlock.ev, root.twelve) : ""
                color: theme.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: focusBlock.ev ? focusBlock.ev.title : ""
              color: theme.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }

            Text {
              visible: text !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: focusBlock.ev ? Model.guestsLabel(focusBlock.ev) : ""
              color: theme.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            // Elapsed time, only while it's on: a hairline that fills.
            Rectangle {
              visible: root.focusOngoing
              width: parent.width
              height: Math.max(1, Style.space(2))
              color: theme.rule
              Rectangle {
                width: Math.round(parent.width * (focusBlock.ev ? Model.progress(focusBlock.ev, root.now) : 0))
                height: parent.height
                color: theme.signal
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
              }
            }

            Item { width: 1; height: Style.space(4) }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              JoinButton {
                navKey: "join"
                Layout.fillWidth: true
                live: root.focusUrgent || root.focusOngoing
                text: !focusBlock.ev ? ""
                  : focusBlock.ev.url ? "Join" + (focusBlock.ev.serviceName ? " " + focusBlock.ev.serviceName : "")
                  : "Open in Calendar"
                onClicked: root.activateEvent(focusBlock.ev)
              }

              PanelActionButton {
                visible: !!focusBlock.ev && !!focusBlock.ev.url
                iconText: "󰆏"
                tooltipText: "Copy link (c)"
                foreground: theme.dim
                hoverColor: theme.ink
                fontFamily: root.fontFamily
                onClicked: cal.copy(focusBlock.ev.url, focusBlock.ev.serviceName ? focusBlock.ev.serviceName + " link" : "Link")
              }

              PanelActionButton {
                visible: !!focusBlock.ev && !!focusBlock.ev.url && !!focusBlock.ev.htmlLink
                iconText: "󰃭"
                tooltipText: "Open in Google Calendar"
                foreground: theme.dim
                hoverColor: theme.ink
                fontFamily: root.fontFamily
                onClicked: { cal.open(focusBlock.ev.htmlLink); root.close() }
              }
            }
          }

          // ── The rest, by day ──────────────────────────────────────────
          Rule { visible: cal.ready && !!root.focusEv }

          Repeater {
            model: cal.ready && cal.fetchedAt > 0 ? root.days : []

            Column {
              id: dayBlock
              required property var modelData
              required property int index
              width: column.width
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: dayBlock.modelData.label.toUpperCase()
                color: theme.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                bottomPadding: Style.space(4)
                topPadding: dayBlock.index > 0 ? Style.space(8) : 0
              }

              Repeater {
                model: dayBlock.modelData.allDay.concat(dayBlock.modelData.timed)
                EventRow {
                  required property var modelData
                  width: dayBlock.width
                  ev: modelData
                }
              }

              Hint {
                visible: dayBlock.index === 0 && dayBlock.modelData.timed.length === 0
                  && dayBlock.modelData.allDay.length === 0
                text: root.emptyToday !== "" ? root.emptyToday : "Nothing else today."
                color: theme.faint
                font.pixelSize: Style.font.bodySmall
                bottomPadding: Style.space(2)
              }
            }
          }

          // ── Footer ────────────────────────────────────────────────────
          Rule { visible: cal.ready }

          RowLayout {
            visible: cal.ready
            width: parent.width
            spacing: Style.space(4)

            ActionButton {
              navKey: "new"
              text: cal.creating ? "Creating…" : "New meeting"
              tooltipText: String(root.setting("newMeeting", "event")) === "instant"
                ? "Open meet.google.com/new (n)"
                : "Put a Google Meet on your calendar now, copy the link and join (n)"
              enabled: !cal.creating
              onClicked: cal.newMeeting()
            }

            Item { Layout.fillWidth: true }

            FooterButton { navKey: "calendar"; text: "Calendar"; tooltipText: "Open Google Calendar (o)"; onClicked: { cal.openCalendar(); root.close() } }

            PanelActionButton {
              id: refreshButton
              property string navKey: "refresh"
              hasCursor: root.hasCursor("refresh")
              iconText: cal.stale ? "󰖪" : "󰑐"
              tooltipText: (cal.stale ? "Offline — showing the last copy. " : "")
                + (cal.fetchedAt > 0 ? "Updated " + Model.durationLabel(root.now - cal.fetchedAt).replace(/^1 min$/, "just now") + (root.now - cal.fetchedAt < 60000 ? "" : " ago") : "")
                + " (r)"
              foreground: cal.stale ? Color.urgent : theme.faint
              hoverColor: theme.ink
              fontFamily: root.fontFamily
              onHovered: function(on) { if (on) root.hover("refresh") }
              onClicked: cal.refresh()

              RotationAnimation on rotation {
                running: cal.fetching
                from: 0; to: 360; duration: 900
                loops: Animation.Infinite
              }
              onRotationChanged: if (!cal.fetching && rotation !== 0) rotation = 0
            }

            // Which account this is, which is worth knowing; signing out,
            // which is rare, only says so when you point at it.
            FooterButton {
              id: accountButton
              navKey: "signout"
              text: (pointing || hasCursor || cal.account === "") ? "Sign out" : cal.account.replace(/@.*/, "")
              tooltipText: cal.account !== "" ? cal.account : ""
              onClicked: cal.signOut()
            }
          }
        }
      }
    }
  }

  // ── Components ──────────────────────────────────────────────────────────

  component Hint: Text {
    width: parent ? parent.width : implicitWidth
    textFormat: Text.PlainText
    color: theme.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }

  component Rule: Rectangle {
    width: parent ? parent.width : 0
    height: Math.max(1, Style.spacing.hairline)
    color: theme.rule
  }

  component ActionButton: Button {
    property string navKey: ""
    property bool quiet: false
    bordered: !quiet
    hasCursor: root.hasCursor(navKey)
    foreground: quiet && !hasCursor ? theme.dim : theme.ink
    fontFamily: root.fontFamily
    fontSize: Style.font.body
    onHovered: function(on) { if (on) root.hover(navKey) }
  }

  component FooterButton: Button {
    property string navKey: ""
    property bool pointing: false
    hasCursor: root.hasCursor(navKey)
    foreground: hasCursor ? theme.ink : theme.dim
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    onHovered: function(on) { pointing = on; if (on) root.hover(navKey) }
  }

  // The panel's one primary control. At rest it is an outlined key; when
  // it's time to go it fills with the signal colour, like a lit switch.
  component JoinButton: Rectangle {
    id: join
    signal clicked()
    property string navKey: ""
    property string text: ""
    property bool live: false
    readonly property bool hot: joinMouse.containsMouse || root.hasCursor(navKey)

    implicitHeight: Math.max(Style.spacing.controlHeight, joinLabel.implicitHeight + Style.spacing.controlPaddingY * 2) + Style.space(4)
    radius: Style.cornerRadius
    color: live
      ? (joinMouse.pressed ? Qt.darker(theme.joinFill, 1.15) : (hot ? Qt.lighter(theme.joinFill, 1.08) : theme.joinFill))
      : (joinMouse.pressed ? Style.pressedFillFor(theme.ink, Color.accent) : (hot ? root.hoverFill : "transparent"))
    border.width: live ? 0 : Math.max(1, Style.normalBorderWidth)
    border.color: hot && !live ? Style.focusBorderFor(theme.ink, Color.accent) : Style.normalBorderFor(theme.ink, Color.accent)
    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
      id: joinLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: join.text
      color: join.live ? theme.joinText : theme.ink
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: join.live
    }

    MouseArea {
      id: joinMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hover(join.navKey)
      onClicked: join.clicked()
    }
  }

  component EventRow: CursorSurface {
    id: row
    property var ev: null
    readonly property string navKey: ev ? "ev:" + Model.notifyKey(ev) : ""
    readonly property bool ongoing: ev ? Model.isOngoing(ev, root.now) : false
    readonly property bool past: ev ? !ev.allDay && Model.isPast(ev, root.now) : false
    readonly property bool tentative: ev ? Model.isTentative(ev) : false
    readonly property bool declined: ev ? Model.isDeclined(ev) : false
    readonly property bool revealed: hasCursor || rowMouse.containsMouse

    hasCursor: root.hasCursor(navKey)
    foreground: theme.ink
    fill: root.hoverFill
    implicitHeight: Style.space(30)

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hover(row.navKey)
      onClicked: root.activateEvent(row.ev)
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        Layout.preferredWidth: Math.max(timeMetrics.width, allDayMetrics.width)
        text: !row.ev ? "" : row.ev.allDay ? "All day" : Model.timeLabel(row.ev.start, root.twelve)
        color: row.ongoing ? theme.signal : (row.ev && row.ev.allDay || row.past ? theme.faint : theme.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.features: { "tnum": 1 }
        Layout.alignment: Qt.AlignVCenter
      }

      // Filled: you're going. Hollow: not answered yet, or maybe.
      Rectangle {
        Layout.preferredWidth: Style.space(7)
        Layout.preferredHeight: Style.space(7)
        Layout.alignment: Qt.AlignVCenter
        radius: Style.cornerRadius > 0 ? Style.space(2) : 0
        readonly property color swatch: theme.swatchColor(row.ev)
        color: row.tentative || row.declined ? "transparent" : swatch
        border.width: row.tentative || row.declined ? Math.max(1, Style.space(1)) : 0
        border.color: swatch
        opacity: row.past || row.declined ? 0.5 : 1
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: row.ev ? row.ev.title : ""
        color: row.past || row.declined ? theme.faint : (row.tentative ? theme.dim : theme.ink)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.strikeout: row.declined
        elide: Text.ElideRight
        Layout.alignment: Qt.AlignVCenter
      }

      // At rest: whether there's a call. On hover: what you can do with it.
      Text {
        visible: !row.revealed && !!row.ev && !!row.ev.url
        text: "󰕧"
        color: row.ongoing ? theme.signal : theme.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      PanelActionButton {
        visible: row.revealed && !!row.ev && !!row.ev.url
        iconText: "󰆏"
        tooltipText: "Copy link (c)"
        foreground: theme.dim
        hoverColor: theme.ink
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(on) { if (on) root.hover(row.navKey) }
        onClicked: cal.copy(row.ev.url, row.ev.serviceName ? row.ev.serviceName + " link" : "Link")
      }

      PanelActionButton {
        visible: row.revealed && !!row.ev && !!row.ev.url && !!row.ev.htmlLink
        iconText: "󰃭"
        tooltipText: "Open in Google Calendar"
        foreground: theme.dim
        hoverColor: theme.ink
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(on) { if (on) root.hover(row.navKey) }
        onClicked: { cal.open(row.ev.htmlLink); root.close() }
      }
    }
  }

  TextMetrics {
    id: timeMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    text: root.twelve ? "00:00 PM" : "00:00"
  }

  TextMetrics {
    id: allDayMetrics
    font: timeMetrics.font
    text: "All day"
  }
}
