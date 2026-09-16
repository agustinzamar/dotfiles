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

# Max number of characters so it fits nicely to the right of the notch
# MAY NOT WORK WITH NON-ENGLISH CHARACTERS
MAX_LENGTH=35
HALF_LENGTH=$(((MAX_LENGTH + 1) / 2))

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

    # Spotifast is loaded but holds no track: keep the icon, drop the label.
    if [[ -z "$track" ]]; then
        sketchybar --set $NAME background.color=0xffeed49f label.drawing=no
        return
    fi

    local track_length=${#track} artist_length=${#artist}

    # Calculations so it fits nicely
    if [[ $((track_length + artist_length)) -gt $MAX_LENGTH ]]; then
        # If the total length exceeds the max
        if [[ $track_length -gt $HALF_LENGTH && $artist_length -gt $HALF_LENGTH ]]; then
            # If both the track and artist are too long, cut both at half length - 1

            # If MAX_LENGTH is odd, HALF_LENGTH is calculated with an extra space, so give it an extra char
            track="${track:0:$((MAX_LENGTH % 2 == 0 ? HALF_LENGTH - 2 : HALF_LENGTH - 1))}…"
            artist="${artist:0:$((HALF_LENGTH - 2))}…"
        elif [[ $track_length -gt $HALF_LENGTH ]]; then
            # Else if only the track is too long, cut it by the difference of the max length and artist length
            track="${track:0:$((MAX_LENGTH - artist_length - 1))}…"
        elif [[ $artist_length -gt $HALF_LENGTH ]]; then
            artist="${artist:0:$((MAX_LENGTH - track_length - 1))}…"
        fi
    fi

    # The old widget switched on Spotify's "Player State" string; this flag is the
    # whole equivalent.
    if [[ "$playing" == "true" ]]; then
        sketchybar --set $NAME label="${track}  ${artist}" label.drawing=yes background.color=0xffa6da95
    else
        sketchybar --set $NAME label="${track}  ${artist}" label.drawing=yes background.color=0xffeed49f
    fi
}

case "$SENDER" in
"mouse.clicked")
    "$MEDIA_CONTROL" toggle-play-pause
    ;;
*)
    update_track
    ;;
esac
