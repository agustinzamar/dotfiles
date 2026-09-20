#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# The paneru workspace row: one pill per virtual workspace of the active display.
#
# paneru groups its workspace list by native workspace (the macOS Space), so the
# list carries every display's spaces at once. A row that rendered all of them
# would show spaces that are not on screen, so this keeps only the group whose
# entry is active.
#
# The config builds a fixed 9-pill row and this script only toggles it:
# sketchybar lays left items out left-to-right in creation order, so a pill added
# at runtime would be created after front_app and would land on the wrong side of
# the cluster.
#
# Protocol reference: paneru's QUERY_AND_SUBSCRIBE_FORMAT.md documents
# `paneru query virtual-workspaces --json` as a list of
# {number, native_workspace_id, active, windows[]}, and addresses the switch as
# `paneru send-cmd window virtualnum <n>`.
#
# Colour follows the bar's single-accent rule: the accent surface means "you are
# here", and because that surface is light its ink flips to the dark one, the
# same way the player pill's does. Every other space takes the neutral surface
# with the bar's light ink.

MAX_SPACES=9

# A click switches the space. Redrawing as well would fight the daemon, which
# emits its own workspace event for the switch.
if [[ "$SENDER" == "mouse.clicked" ]]; then
    case "$NAME" in
    space.[1-9]) paneru send-cmd window virtualnum "${NAME#space.}" 2>/dev/null ;;
    esac
    exit 0
fi

PAYLOAD=$(paneru query virtual-workspaces --json 2>/dev/null)

# An unreachable daemon yields nothing, and a row that blanks itself on a
# transient hiccup is worse than a row that briefly shows stale numbers.
[[ -z "$PAYLOAD" ]] && exit 0

# No active entry means paneru could not resolve an active display. That is a
# real state, so every pill hides rather than keeping its last number: the
# fallback-to-visible rule the single indicator needed only existed because an
# empty icon left a floating box behind, and drawing=off is explicit here.
ACTIVE_NATIVE=$(jq -r '[.[]? | select(.active == true)][0].native_workspace_id // empty' <<<"$PAYLOAD" 2>/dev/null)

STATES=$(jq -r --argjson max "$MAX_SPACES" --argjson native "${ACTIVE_NATIVE:-null}" '
        ([.[]? | select($native != null and .native_workspace_id == $native)]) as $row
        | range(1; $max + 1) as $i
        | "\($i) \([$row[] | select(.number == $i)] | length > 0) \([$row[] | select(.number == $i and .active == true)] | length > 0)"
    ' <<<"$PAYLOAD" 2>/dev/null)

UPDATES=()
while read -r index visible active; do
    [[ -z "$index" ]] && continue
    if [[ "$visible" != "true" ]]; then
        UPDATES+=(--set "space.$index" drawing=off)
    elif [[ "$active" == "true" ]]; then
        UPDATES+=(--set "space.$index" drawing=on background.color=0xffb7bdf8 icon.color=0xff24273a)
    else
        UPDATES+=(--set "space.$index" drawing=on background.color=0x66494d64 icon.color=0xffcad3f5)
    fi
done <<<"$STATES"

if (( ${#UPDATES[@]} > 0 )); then
    sketchybar "${UPDATES[@]}"
fi
