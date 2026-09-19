#!/usr/bin/env sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# The bar runs one accent colour; the charge level is already
# carried by the numeric label, so the icon keeps no gradient.
ICON_COLOR=0xffb7bdf8

PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ "$PERCENTAGE" = "" ]; then
    # No battery on this machine: hide rather than leave an empty slot.
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

case ${PERCENTAGE} in
[8-9][0-9] | 100)
    ICON=""
    ;;
7[0-9])
    ICON=""
    ;;
[4-6][0-9])
    ICON=""
    ;;
[1-3][0-9])
    ICON=""
    ;;
[0-9])
    ICON=""
    ;;
esac

if [[ $CHARGING != "" ]]; then
    ICON=""
fi

sketchybar --set "$NAME" \
    drawing=on \
    icon="$ICON" \
    label="${PERCENTAGE}%" \
    icon.color="${ICON_COLOR}"
