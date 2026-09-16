#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

sketchybar --set $NAME label="$(date '+%b %-d %-H:%M')"
