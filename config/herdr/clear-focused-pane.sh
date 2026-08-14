#!/bin/sh
# Send Ctrl+L to the focused Herdr pane.
#
# Herdr binds ctrl+l to focus_pane_right, so the raw byte never reaches a pane.
# The socket API writes to the pane PTY directly and bypasses that grab.
set -eu

PATH="/opt/homebrew/bin:$PATH"
export PATH

pane=$(herdr pane current | jq -r '.result.pane.pane_id')
[ -n "$pane" ] && [ "$pane" != "null" ] || exit 1

exec herdr pane send-keys "$pane" ctrl+l
