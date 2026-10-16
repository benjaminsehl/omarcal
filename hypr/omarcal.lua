-- Omarcal hotkeys, loaded by ~/.local/state/omarchy/toggles/hypr/omarcal.lua
-- (written by install.sh). ⌘ is SUPER and ⌥ is ALT; on a Windows keyboard,
-- Win + Alt.

-- ⌘⌥J: join the current or next meeting that has a call link.
o.bind("SUPER + ALT + J", "Join next meeting", "omarchy-shell sehl.omarcal joinNext")

-- ⌘⌥⇧J: put a Google Meet on the calendar now, copy its link and open it.
o.bind("SUPER + ALT + SHIFT + J", "New Google Meet", "omarchy-shell sehl.omarcal newMeetingNow")
