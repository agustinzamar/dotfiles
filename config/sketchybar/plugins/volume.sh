#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# $INFO only arrives once a real volume_change event has fired; before that
# (e.g. right after a sketchybar reload) it is empty, which used to render
# a bare "%" with no number. Fall back to querying the real system volume.
if [[ -z "$INFO" ]]; then
    INFO=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
fi

case ${INFO} in
0)
    ICON=""
    ICON_PADDING_RIGHT=21
    ;;
[0-9])
    ICON=""
    ICON_PADDING_RIGHT=12
    ;;
*)
    ICON=""
    ICON_PADDING_RIGHT=6
    ;;
esac

sketchybar --set $NAME icon=$ICON icon.padding_right=$ICON_PADDING_RIGHT label="$INFO%"
