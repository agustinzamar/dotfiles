#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Now-playing item for Spotifast.
#
# The item this replaces was fed by Spotify's own distributed notification
# (com.spotify.client.PlaybackStateChanged) and toggled playback through
# `tell application "Spotify" to playpause`. Spotifast offers neither: it posts
# no notification of its own and ships no AppleScript dictionary, so the state
# is read from media-control, the same MediaRemote feed that drives macOS' own
# Now Playing widget, and the click action goes back out through it. The bundle
# id is the only reliable owner check: the app is Spotifast, but its executable
# is still `fastpotify` and its bundle id is still me.paolino.fastpotify.
SPOTIFAST_BUNDLE_ID="me.paolino.fastpotify"

# The label is deliberately NOT truncated here. The marquee is drawn by
# SketchyBar's own scroll_texts + label.max_chars pair, both set on the item in
# the config, and it only scrolls text that SketchyBar itself truncated. Cutting
# the string in this script would leave the bar nothing to move.
#
# Colour carries exactly one bit: the bar's single accent means "playing", the
# neutral surface means "paused". No second hue is introduced; only the ink flips
# with the surface, because the accent is light and the neutral one is dark.

hide_item() {
    sketchybar --set $NAME drawing=off
}

# Same override convention as MANIFEST_BREW in install/manifest.sh: point this at
# a stub to drive the item without a real MediaRemote feed.
MEDIA_CONTROL=${SPOTIFAST_MEDIA_CONTROL:-media-control}

# No reader means nothing honest to draw: hide rather than invent a state.
if ! command -v "$MEDIA_CONTROL" >/dev/null 2>&1; then
    hide_item
    exit 0
fi

NOW_PLAYING="$("$MEDIA_CONTROL" get 2>/dev/null)"

# The feed belongs to whichever app owns playback right now, which may well be
# something else entirely. Anything that is not Spotifast is not this item.
if [[ "$(jq -r '.bundleIdentifier // empty' <<<"$NOW_PLAYING" 2>/dev/null)" != "$SPOTIFAST_BUNDLE_ID" ]]; then
    hide_item
    exit 0
fi

sketchybar --set $NAME drawing=on

update_track() {
    local track artist playing
    track="$(jq -r '.title // empty' <<<"$NOW_PLAYING" 2>/dev/null)"
    artist="$(jq -r '.artist // empty' <<<"$NOW_PLAYING" 2>/dev/null)"
    # media-control reports a boolean; older adapter builds exposed playbackRate.
    playing="$(jq -r 'if has("playing") then .playing else ((.playbackRate // 0) > 0) end' <<<"$NOW_PLAYING" 2>/dev/null)"

    # Ink travels with the surface. The accent is a light lilac, so the bar's
    # light label default lands at 1.21:1 on it, while the dark ink the other
    # accent pills already use (the active workspace pill, front_app) measures 8.17:1. A
    # single fixed ink cannot serve both surfaces: the dark one on the neutral
    # surface would invert the problem at 1.77:1.
    local label_text="" background=0x66494d64 ink=0xffcad3f5 scroll=off
    if [[ -n "$track" ]]; then
        label_text="${track} | ${artist}"
        # The old widget switched on Spotify's "Player State" string; this flag
        # is the whole equivalent. Spotifast loaded but holding no track keeps
        # the icon and the neutral surface, with the label dropped below.
        if [[ "$playing" == "true" ]]; then
            background=0xffb7bdf8
            ink=0xff24273a
            # Only a playing track is worth moving: the marquee reads as a
            # play-state affordance, so the paused pill holds its text still.
            # Writing the label resets the scroll offset, and the pause always
            # writes one (the surface and the ink change with it), so the text
            # parks at its start instead of wherever the pause caught it.
            scroll=on
        fi
    fi

    local label_drawing=no
    [[ -n "$label_text" ]] && label_drawing=yes

    # Writing an unchanged label restarts the marquee, and this item is polled
    # every 5s, so only push when something actually changed. Every derived field
    # belongs in this comparison — the surface, both ink colours and the scroll —
    # because a run that ignored one would leave the previous state's value on
    # the current state.
    local current
    current="$(sketchybar --query "$NAME" 2>/dev/null)"
    if [[ "$(jq -r '.label.value // empty' <<<"$current" 2>/dev/null)" == "$label_text" ]] &&
        [[ "$(jq -r '.geometry.background.color // empty' <<<"$current" 2>/dev/null)" == "$background" ]] &&
        [[ "$(jq -r '.label.color // empty' <<<"$current" 2>/dev/null)" == "$ink" ]] &&
        [[ "$(jq -r '.icon.color // empty' <<<"$current" 2>/dev/null)" == "$ink" ]] &&
        [[ "$(jq -r '.geometry.scroll_texts // empty' <<<"$current" 2>/dev/null)" == "$scroll" ]]; then
        return
    fi

    sketchybar --set "$NAME" \
        label="$label_text" \
        label.drawing="$label_drawing" \
        background.color="$background" \
        label.color="$ink" \
        icon.color="$ink" \
        scroll_texts="$scroll"
}

case "$SENDER" in
"mouse.clicked")
    "$MEDIA_CONTROL" toggle-play-pause
    ;;
*)
    update_track
    ;;
esac
