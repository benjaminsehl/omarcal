#!/bin/bash
# Put the built-in clock back and unlink the plugin. Leaves your OAuth client
# and token in place; run `bin/omarcal logout` first to revoke the token.
set -euo pipefail

id="sehl.omarcal"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
dest="$config/omarchy/plugins/$id"
shell_json="$config/omarchy/shell.json"

# Disabling a clone restores its source (omarchy.clock) in the same slot.
omarchy plugin disable "$id" || true

if [[ -f $shell_json ]] && command -v jq >/dev/null; then
  if [[ $(jq -r '.bar.centerAnchor // ""' "$shell_json") == "$id" ]]; then
    cp "$shell_json" "$shell_json.bak.$(date +%s)"
    tmp="$(mktemp)"
    jq '.bar.centerAnchor = "omarchy.clock"' "$shell_json" > "$tmp" && mv "$tmp" "$shell_json"
  fi
fi

toggle="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr/omarcal.lua"
if [[ -f $toggle ]]; then
  rm "$toggle"
  command -v hyprctl >/dev/null && hyprctl reload >/dev/null
  echo "removed hotkeys"
fi

[[ -L $dest ]] && rm "$dest" && echo "unlinked $dest"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
