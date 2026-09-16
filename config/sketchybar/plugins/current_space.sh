#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Shows the active paneru virtual workspace on the sketchybar. paneru has no
# sketchybar-event integration, so this item polls on a short update_freq
# (see sketchybarrc-laptop / sketchybarrc-desktop) instead of subscribing to
# a custom event the way the old yabai-backed version did.
#
# Protocol reference: paneru's QUERY_AND_SUBSCRIBE_FORMAT.md documents
# `paneru query active --json` returning an object with a
# `virtual_workspace_number` field (one-based, or null when unknown).

PANERU_ACTIVE=$(paneru query active --json 2>/dev/null)
SPACE_INDEX=$(echo "$PANERU_ACTIVE" | jq -r '.virtual_workspace_number // 1' 2>/dev/null)

# If paneru isn't reachable (daemon not running, IPC error, empty/malformed
# output) the pipeline above can yield an empty string instead of a number,
# which previously left the item's icon blank/invisible. Always fall back to
# a visible default instead of rendering nothing.
[[ "$SPACE_INDEX" =~ ^[0-9]+$ ]] || SPACE_INDEX=1

# Every workspace renders as its number — no special-cased icon glyph for
# space 1.
ICON=$SPACE_INDEX
ICON_PADDING_LEFT=9
ICON_PADDING_RIGHT=10

sketchybar --set $NAME \
    icon=$ICON \
    icon.padding_left=$ICON_PADDING_LEFT \
    icon.padding_right=$ICON_PADDING_RIGHT
