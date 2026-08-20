#!/usr/bin/env zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Shows the focused yabai space on the sketchybar. yabai triggers
# `space_change` (see config/yabai/yabairc); we query yabai for the focused
# space index so this stays correct regardless of which display is active.

update_space() {
    SPACE_INDEX=$(yabai -m query --spaces --display | jq 'map(select(.focused == 1))[0].index // 1')

    case $SPACE_INDEX in
    1)
        ICON=󰀏
        ICON_PADDING_LEFT=7
        ICON_PADDING_RIGHT=7
        ;;
    *)
        ICON=$SPACE_INDEX
        ICON_PADDING_LEFT=9
        ICON_PADDING_RIGHT=10
        ;;
    esac

    sketchybar --set $NAME \
        icon=$ICON \
        icon.padding_left=$ICON_PADDING_LEFT \
        icon.padding_right=$ICON_PADDING_RIGHT
}

case "$SENDER" in
"mouse.clicked")
    # Focus the clicked space, then refresh.
    SPACE_INDEX=$(yabai -m query --spaces --display | jq 'map(select(.focused == 1))[0].index // 1')
    yabai -m space --focus "$SPACE_INDEX" 2>/dev/null
    sketchybar --remove '/.*/'
    source $HOME/.config/sketchybar/sketchybarrc
    ;;
*)
    update_space
    ;;
esac
