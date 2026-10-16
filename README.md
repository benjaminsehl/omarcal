# Omarcal

The Omarchy clock, made useful. The bar keeps the time and adds the next
meeting when it's close. Click it and you get your Google Calendar: the
meeting that matters now with a **Join** button, and the rest of today and
tomorrow underneath. One key starts a new Google Meet. It's MeetingBar, for
Omarchy.

```
 2:45 AM │ Design review in 15m                      ← bar

 FRIDAY 16 OCTOBER                              W42
 in 15 min                              3:00–3:30 AM
 Design review
 Google Meet · 6 guests
 [          Join Google Meet          ]   ⧉   ▣
 ────────────────────────────────────────────────
 TODAY
   4:00 AM  □ 1:1 with Alex                     ▶
   5:15 AM  ■ Lunch
 TOMORROW
   All day  ■ Thanksgiving
   9:30 AM  ■ Planning                          ▶
 ────────────────────────────────────────────────
 [New meeting]                 Calendar   ⟳   you
```

## Design: what would Rams do?

- **Useful.** No hero date or month grid; nobody opens the clock to find out
  what month it is. The panel leads with the one meeting you're about to go
  to, and its Join button.
- **Unobtrusive.** The date is a small printed label. The bar only mentions a
  meeting within the hour (configurable), and only gets a colour when it's
  time to go.
- **Honest.** Colour carries meaning: the theme's signal colour (Braun orange
  on Rams) marks *it's time*, from 5 minutes before a meeting until 5 minutes
  in, and nothing else. Meetings you haven't answered, or answered "maybe", are
  drawn with a hollow square rather than hidden.
- **Thorough.** Keyboard throughout, notifications that join on click, an
  offline copy, the right Google account picked for Meet (`authuser`), Zoom,
  Teams, Webex, Tuple and other links detected, back-to-back meetings hand
  over to the next one 5 minutes before it starts.
- **As little design as possible.** One typeface, the theme's type scale,
  hairlines. Rarely used actions (sign out) stay quiet until you point at
  them.

## Install

```bash
git clone https://github.com/benjaminsehl/omarcal.git ~/Work/omarcal
cd ~/Work/omarcal && ./install.sh
```

This links the folder into `~/.config/omarchy/plugins/sehl.omarcal` and
enables it. The manifest declares `clonedFrom: omarchy.clock`, so it takes the
clock's slot in the bar and keeps the clock's settings (your `format`). The
Calendar hotkey (`SUPER+CTRL+ALT+D`, `omarchy-shell shell toggle
omarchy.clock`) opens this panel instead. It also points `bar.centerAnchor` at
the plugin; a backup of `shell.json` is written first.

`./uninstall.sh` puts the built-in clock back.

### Connect Google Calendar (one-time setup)

Google only lets apps you've registered read your calendar, so you register
your own OAuth client. Your data goes from Google to your machine and nowhere
else.

1. In the [Google Cloud console](https://console.cloud.google.com/), create
   or pick a project and enable the **Google Calendar API**.
2. **Google Auth Platform → Get started.** If you're on a Google Workspace
   account, choose **Internal**: no review, and tokens don't expire. With a
   personal account, choose External and add yourself as a **test user**.
   Tokens for External apps in "Testing" expire after 7 days, so you'll be
   asked to connect again each week unless you publish the app (for your own
   use, that doesn't need Google's review).
3. **Clients → Create client → Desktop app**, then **Download JSON**.
4. Save it as `~/.config/omarcal/client_secret.json`.
5. Open the panel and choose **Connect Google Calendar**. Sign in in the
   browser; the tab says "Connected" when it's done.

Permissions requested: `calendar.events` (read events, and create the Meet
for **New meeting**) and `calendar.calendarlist.readonly` (which calendars
you have).

If your Workspace admin blocks unverified third-party apps, ask them to allow
your client ID, or create the project inside your organisation's Cloud
account.

Files:

| Path | What |
|---|---|
| `~/.config/omarcal/client_secret.json` | your OAuth client (you put it there) |
| `~/.local/state/omarcal/token.json` | refresh token, mode 0600 |
| `~/.cache/omarcal/events.json` | last good fetch, shown when offline |

## Use

| | |
|---|---|
| Left click | open the panel |
| Right click | join the current/next meeting (opens the panel if there's no link) |
| Middle click | new meeting |
| `Enter` | join the meeting at the top (or the selected row) |
| `↑↓` / `jk` | move |
| `n` | new meeting |
| `c` | copy the selected meeting's link |
| `o` | open Google Calendar |
| `r` | refresh |
| `Esc` | close |

Clicking a row joins its call, or opens it in Google Calendar if it has no
link. Hover a row to copy its link or open it in Calendar.

**New meeting** puts a 30-minute "Meet" on your primary calendar starting
now, copies the link, and opens the call. Set `newMeeting` to `instant` to
open `meet.google.com/new` instead, with no calendar entry.

A notification arrives a minute before each meeting; click it to join.

## Settings

Set them inline on the widget's entry in `~/.config/omarchy/shell.json`, or
with `omarchy bar set sehl.omarcal <key> <value>`.

| Key | Default | |
|---|---|---|
| `format` | `HH:mm` | clock format (Qt); an `AP` makes the panel 12-hour too |
| `barNext` | `title` | `title` (Design review in 12m), `countdown` (in 12m) or `off` |
| `barLookaheadMinutes` | `60` | mention a meeting in the bar this far ahead |
| `barTitleLength` | `24` | longest title in the bar |
| `soonMinutes` | `5` | signal colour this long before (and after) a start |
| `handoffMinutes` | `5` | switch from the current meeting to the next this long before it |
| `days` | `3` | days to fetch and list |
| `maxEvents` | `12` | most meetings to list |
| `calendars` | `""` | comma-separated calendar IDs (`primary` works); blank: the ones checked in Google Calendar |
| `showDeclined` | `false` | |
| `showPast` | `false` | include today's finished meetings, greyed |
| `refreshMinutes` | `5` | |
| `notifyMinutesBefore` | `1` | `-1` turns notifications off |
| `newMeeting` | `event` | `event` or `instant` |
| `newMeetingTitle` | `Meet` | |
| `newMeetingMinutes` | `30` | |
| `openWith` | `browser` | `browser` (xdg-open) or `webapp` (`omarchy-launch-webapp`) |
| `closeOnJoin` | `true` | |
| `twelveHour` | from `format` | force the panel's 12/24-hour time |

## Theming

The panel is an ordinary Omarchy popup, so it already follows your theme's
`[popups]`, `[controls]`, `[font]` and `[spacing]`. Any theme can tune the
calendar itself with a `[calendar]` section in its `shell.toml`. Every key is
optional and falls back to the theme's popup text and accent, so the widget
looks right on themes that have never heard of it:

```toml
[calendar]
text            = "#dedad2"   # titles, times
dim             = "#8f8c87"   # secondary text      (default: text at 62%)
faint           = "#5d5c58"   # labels, idle glyphs (default: text at 38%)
rule            = "#2f2f2d"   # hairlines
rule-alpha      = 1.0         #                     (default: text at 12%)
signal          = "#f0692b"   # now / starting soon (default: accent)
join-background = "#f0692b"   # Join, when it's time (default: signal)
join-text       = "#0e0e0d"   #                     (default: popup background)
bar-signal      = "#f0692b"   # the bar countdown when it's time
event-colors    = "calendar"  # calendar | mono | accent
```

Values can be hex or a role name (`foreground`, `accent`, `muted`,
`background`). The Rams theme ships this section (from `tools/build.py`).

## Development

```bash
node --test tests/                          # Model.js
python3 -m unittest discover -s tests       # bin/omarcal (link detection, parsing)

omarchy-shell sehl.omarcal demo default     # canned data: default | now | empty | setup | signedOut
omarchy-shell sehl.omarcal demo off
omarchy-shell sehl.omarcal status           # JSON: phase, next meeting, bar text
omarchy-shell sehl.omarcal join | newMeeting | refresh | open | toggle
```

- `bin/omarcal` is the only thing that talks to Google (Python standard
  library, no dependencies). Each command prints one JSON object; try
  `bin/omarcal status` or `bin/omarcal events --days 1`.
- `Model.js` is pure (what's next, labels, grouping) and tested in node.
- `Service.qml` runs the helper, timers and notifications; `BarWidget.qml`
  is the bar label and panel; `CalendarTheme.qml` resolves every colour.
- Hot reload doesn't always pick up changes to the nested types
  (`Service.qml`, `Model.js`). `omarchy restart shell` does.
