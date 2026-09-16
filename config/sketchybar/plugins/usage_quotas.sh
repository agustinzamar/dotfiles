#!/usr/bin/env zsh

# One scheduler fetches the shared snapshot for all three provider items.
set +x
set +v

url="${USAGE_TRACKER_URL:-https://usage.agustinzamar.com.ar}"
payload='{}'
if [[ "${USAGE_TRACKER_TOKEN:-}" != *$'\n'* && "${USAGE_TRACKER_TOKEN:-}" != *$'\r'* ]]; then
    # Keep the optional credential off curl's command line and out of files.
    payload=$(printf '%s' "${USAGE_TRACKER_TOKEN:+Authorization: Bearer $USAGE_TRACKER_TOKEN}" |
        curl --silent --fail --connect-timeout 5 --max-time 15 \
            --header @- "${url%/}/v1/summary" 2>/dev/null) || payload='{}'
fi

FONT_FILE="$HOME/Library/Fonts/JetBrainsMonoNerdFont-Bold.ttf"
IMAGES_SRC="$HOME/.config/sketchybar/images"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/usage-quotas"
have_magick=0
if command -v magick >/dev/null 2>&1 && [[ -f "$FONT_FILE" && -d "$IMAGES_SRC" ]]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null
    [[ -d "$CACHE_DIR" ]] && have_magick=1
fi
updates=()
for provider in codex claude opencode; do
    line1='?'
    line2='?'
    marker='!'
    case "$provider" in
    codex) color=0xffa6da95 ;;
    claude) color=0xfff5a97f ;;
    opencode) color=0xff8aadf4 ;;
    esac
    # Never pass API text to SketchyBar: composite image normally,
    # two-line text fallback without magick.
    parts=$(printf '%s' "$payload" | jq -er --arg provider "$provider" '
            def percent($key):
                ([.windows[]? | select(.key == $key) | .usedPercent][0]) as $n
                    | if ($n | type) == "number" and $n >= 0 and $n <= 100
                      then (($n | round | tostring) + "%") else "?" end;
            .providers[$provider]
            | if type != "object" then error("missing provider") else . end
            | (percent("session") + "\u001f" + percent("weekly") + "\u001f" +
               (if (.entry.error != null and .entry.error != false and .entry.error != "") then "!"
                elif .entry.stale == true then "~" else "" end))
            ' 2>/dev/null) || parts=""
    if [[ -n "$parts" ]]; then
        IFS=$'\x1f' read -r line1 line2 marker <<<"$parts"
    else
        line1='?'
        line2='?'
        marker='!'
    fi
    case "$marker" in
    '!')
        color=0xffed8796
        fill='#ED8796'
        ;;
    '~')
        color=0xffeed49f
        fill='#EED49F'
        ;;
    *) fill='#CAD3F5' ;;
    esac
    case "$line1$line2" in
    *'?'*) [[ "$marker" != '!' ]] && color=0xffed8796 ;;
    esac
    img_tmp="$CACHE_DIR/.$provider.tmp.png"
    img_out="$CACHE_DIR/$provider.png"
    txt_tmp="$CACHE_DIR/.$provider.txt.png"
    # The logos are generated PNGs sitting next to tracked SVGs. Losing one
    # used to degrade this item to plain text until somebody reran
    # rsvg-convert by hand, so rasterize the SVG into the cache instead:
    # a missing generated artifact can no longer silently break the widget.
    logo="$IMAGES_SRC/$provider.png"
    if [[ ! -f "$logo" && -f "$IMAGES_SRC/$provider.svg" ]]; then
        logo="$CACHE_DIR/$provider.logo.png"
        if [[ ! -f "$logo" || "$IMAGES_SRC/$provider.svg" -nt "$logo" ]]; then
            if command -v rsvg-convert >/dev/null 2>&1 &&
                rsvg-convert -w 96 -h 96 "$IMAGES_SRC/$provider.svg" -o "$logo" 2>/dev/null; then
                :
            elif command -v magick >/dev/null 2>&1 &&
                magick -background none "$IMAGES_SRC/$provider.svg" -resize 96x96 "$logo" 2>/dev/null; then
                :
            else
                # Neither rasterizer worked: fall through to the text mode.
                logo="$IMAGES_SRC/$provider.png"
            fi
        fi
    fi
    if ((have_magick)) && [[ -f "$logo" ]] &&
        magick -background none -fill "$fill" -font "$FONT_FILE" -pointsize 30 label:"$line1\n$line2" "$txt_tmp" 2>/dev/null &&
        magick -background none \( "$logo" -resize x40 \) \
            \( -size 16x72 xc:none \) \
            "$txt_tmp" \
            -gravity center +append -extent 140x72 "$img_tmp" 2>/dev/null &&
        mv -f "$img_tmp" "$img_out" 2>/dev/null; then
        # Clear the text fallback: image and text are exclusive modes, and a
        # previous failed run would otherwise leave its label behind.
        updates+=(--set "usage.$provider" "icon.background.image=$img_out" "label=" "label.drawing=off")
    else
        result="$line1"$'\n'"$line2$marker"
        # And drop whatever image the last good run installed, so the item
        # never renders a logo composite and a text label at the same time.
        updates+=(--set "usage.$provider" "icon.background.image=" "label=$result" "label.color=$color" "label.drawing=on")
    fi
done
sketchybar "${updates[@]}"
