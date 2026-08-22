#!/bin/bash
# move-desktop.sh left|right
# Reorder the current desktop in Mission Control via synthetic mouse drag.
# ponytail: fakes a drag on the spaces bar (no scripting addition); breaks if
# Apple changes the Mission Control AX layout. With SIP off, replace with:
#   yabai -m space --move prev|next
set -u

dir="${1:-}"
[ "$dir" = "left" ] || [ "$dir" = "right" ] || exit 1

slbl=$(yabai -m query --spaces | jq -r '[.[] | select(."has-focus").label][0] // ""')
wid=$(yabai -m query --windows | jq -r '[.[] | select(."has-focus").id][0] // empty')
cur=$(yabai -m query --spaces | jq -r '[.[] | select(."has-focus").index][0]')
total=$(yabai -m query --spaces | jq 'length')
case "$dir" in
  left)  tgt=$((cur - 1)) ;;
  right) tgt=$((cur + 1)) ;;
esac

# Always restore focus — opening Mission Control steals it.
restore() {
  if [ -n "$slbl" ]; then
    yabai -m space --focus "$slbl" 2>/dev/null || true
  fi
}
trap restore EXIT

[ "$tgt" -lt 1 ] && exit 0
[ "$tgt" -gt "$total" ] && exit 0

osascript -e 'tell application "Mission Control" to launch' >/dev/null
sleep 0.7

# Hover over the spaces bar to expand collapsed thumbnails.
screen_w=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null \
  || system_profiler SPDisplaysDataType | awk -F: '/Resolution/{gsub(/[^0-9]/,"",$2); print $2; exit}')
[ -n "$screen_w" ] && cliclick m:"$((screen_w / 2)),40" w:500 >/dev/null

# Get bounds of the current and target desktop thumbnails in the spaces bar.
coords=$(CUR="$cur" TGT="$tgt" osascript <<'EOF' 2>/dev/null
set cur to (system attribute "CUR") as integer
set tgt to (system attribute "TGT") as integer
tell application "System Events"
	tell process "Dock"
		repeat with gg in (groups of group "Mission Control")
			try
				set lst to list 1 of group "Spaces Bar" of gg
				set names to name of every button of lst
				if names contains ("Desktop " & cur) then
					set {sx0, sy0} to position of button ("Desktop " & cur) of lst
					set {sw0, sh0} to size of button ("Desktop " & cur) of lst
					set {dx0, dy0} to position of button ("Desktop " & tgt) of lst
					set {dw0, dh0} to size of button ("Desktop " & tgt) of lst
					return {sx0, sy0, sw0, sh0, dx0, dy0, dw0, dh0}
				end if
			end try
		end repeat
	end tell
end tell
EOF
)
[ -z "$coords" ] && { echo "debug: no coords for Desktop $cur (maybe fullscreen space?)"; exit 0; }

IFS=', ' read -r sx sy sw sh tx ty tw th <<<"$coords"
scx=$((sx + sw / 2)); scy=$((sy + sh / 2))
tcx=$((tx + tw / 2)); tcy=$((ty + th / 2))
# Aim past the target center so the drop lands on the correct side.
[ "$dir" = "left" ] && tcx=$((tcx - tw / 4)) || tcx=$((tcx + tw / 4))

# Drag source onto target.
cliclick m:"$scx,$scy" w:200 dd:. w:300 m:"$((scx + (tcx - scx) / 2)),$tcy" w:200 m:"$tcx,$tcy" w:400 du:.
sleep 0.3
osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1
