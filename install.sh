#!/bin/bash
# Link this folder into the Omarchy shell plugin directory and swap it in for
# the built-in clock. Re-running is safe.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="sehl.omarcal"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
dest="$config/omarchy/plugins/$id"
shell_json="$config/omarchy/shell.json"

mkdir -p "$(dirname "$dest")"
if [[ -L $dest ]]; then
  ln -sfn "$here" "$dest"
elif [[ -e $dest ]]; then
  echo "install: $dest exists and is not a symlink; leaving it alone" >&2
  exit 1
else
  ln -s "$here" "$dest"
fi
echo "linked $dest -> $here"
chmod +x "$here/bin/omarcal"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
sleep 1
# The manifest declares clonedFrom omarchy.clock, so enabling takes the
# clock's slot and keeps its settings (format etc.), and the Calendar hotkey
# (omarchy-shell shell toggle omarchy.clock) reaches this panel instead.
omarchy plugin enable "$id" "$@"
echo "enabled $id"

# The centre section is laid out around bar.centerAnchor; point it here.
if [[ -f $shell_json ]] && command -v jq >/dev/null; then
  if [[ $(jq -r '.bar.centerAnchor // ""' "$shell_json") == "omarchy.clock" ]]; then
    cp "$shell_json" "$shell_json.bak.$(date +%s)"
    tmp="$(mktemp)"
    jq --arg id "$id" '.bar.centerAnchor = $id' "$shell_json" > "$tmp" && mv "$tmp" "$shell_json"
    echo "bar.centerAnchor -> $id"
  fi
fi

client="$config/omarcal/client_secret.json"
if [[ ! -f $client ]]; then
  echo
  echo "Next: save your Google OAuth Desktop-app client JSON as"
  echo "  $client"
  echo "then open the panel and choose Connect (see README.md)."
fi
