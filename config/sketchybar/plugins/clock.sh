#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

sketchybar --set $NAME label="$(date '+%a %b %-d %-H:%M')"
