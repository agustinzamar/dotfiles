#!/usr/bin/env bats
# Contract tests for SketchyBar's item plugins and the bar config.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PLAYER_PLUGIN="$DOTFILES_DIR/config/sketchybar/plugins/spotifast.sh"
  LOG="$BATS_TEST_TMPDIR/sketchybar.log"
  CLICK_LOG="$BATS_TEST_TMPDIR/media-control.log"
  SENDCMD_LOG="$BATS_TEST_TMPDIR/paneru-sendcmd.log"
  : >"$LOG"
  : >"$CLICK_LOG"
  : >"$SENDCMD_LOG"
}

# The player item reads macOS' MediaRemote feed through media-control and draws
# only while Spotifast owns playback. The stub stands in for that feed, so these
# tests never depend on what this machine happens to be listening to; $SENDER
# drives the click path exactly as sketchybar would.
run_player() {
  local payload="$1" sender="${2:-routine}"
  run env PAYLOAD="$payload" SENDER="$sender" \
    SKETCHYBAR_LOG="$LOG" CLICK_LOG="$CLICK_LOG" PLAYER_PLUGIN="$PLAYER_PLUGIN" \
    /opt/homebrew/bin/zsh -c '
      sketchybar() { printf "%s\n" "$*" >>"$SKETCHYBAR_LOG"; }
      media-control() {
        printf "media-control %s\n" "$*" >>"$CLICK_LOG"
        printf "%s" "$PAYLOAD"
      }
      NAME=spotifast
      source "$PLAYER_PLUGIN"
    '
}

PLAYING_JSON='{"title":"La Despedida","artist":"Carafea","bundleIdentifier":"me.paolino.fastpotify","playing":true}'

# Drives the plugin against a stubbed item state, so the "nothing changed" early
# exit can be exercised without a real bar: $ITEM_STATE stands in for the item
# that `sketchybar --query` reports.
run_player_against_state() {
  run env ITEM_STATE="$1" NOW_PLAYING="$PLAYING_JSON" \
    SKETCHYBAR_LOG="$LOG" PLAYER_PLUGIN="$PLAYER_PLUGIN" \
    /opt/homebrew/bin/zsh -c '
      sketchybar() {
        if [[ "$1" == "--query" ]]; then printf "%s" "$ITEM_STATE"; return; fi
        printf "%s\n" "$*" >>"$SKETCHYBAR_LOG"
      }
      media-control() { printf "%s" "$NOW_PLAYING"; }
      NAME=spotifast
      source "$PLAYER_PLUGIN"
    '
}

@test "the bar config carries the battery item on the shared plugin" {
  local config="$DOTFILES_DIR/config/sketchybar/sketchybarrc"
  /opt/homebrew/bin/zsh -n "$config"
  grep -q -- '--add item battery' "$config"
  grep -q 'PLUGIN_SHARED_DIR/battery.sh' "$config"
  # The bar is transparent and its default label colour is the accent the pills
  # sit on, so the battery must declare its own colour or it renders invisible.
  awk '/--add item battery/,/^$/' "$config" | grep -q 'label.color='
}

# sketchybar lays left-side items out left-to-right in creation order and
# right-side items from the display edge inward (src/bar.c,
# bar_calculate_bounds_top_bottom). The workspace row therefore has to be created
# before front_app, which is why the config builds all nine pills up front: a row
# extended at runtime would be created after front_app and could never sit ahead
# of the cluster.
@test "the workspace row is created before front_app" {
  local config="$DOTFILES_DIR/config/sketchybar/sketchybarrc" row_line front_line
  /opt/homebrew/bin/zsh -n "$config"
  grep -q -- 'for index in {1..9}' "$config"
  grep -q -- '--add item "space.$index" left' "$config"
  ! grep -q -- '--add item "space.$index" right' "$config"
  # The single-space indicator this replaced must be gone, not shadowed.
  ! grep -q 'current_space' "$config"

  row_line="$(grep -n -- '--add item "space.$index" left' "$config" | cut -d: -f1)"
  front_line="$(grep -n -- '--add item front_app left' "$config" | cut -d: -f1)"
  [ -n "$row_line" ]
  [ -n "$front_line" ]
  (( row_line < front_line ))
}

# --- The paneru workspace row ------------------------------------------------
# The row shows the spaces of the active display only. paneru groups its list by
# native workspace, so the fixture mirrors a real machine: two spaces on native 4
# (the display in use) and four on native 5 (the other one). A row that ignored
# the grouping would render six pills, two of which are not on screen.

ROW_PAYLOAD='[{"active":false,"native_workspace_id":4,"number":1,"windows":[{}]},{"active":true,"native_workspace_id":4,"number":2,"windows":[{}]},{"active":false,"native_workspace_id":5,"number":1,"windows":[]},{"active":false,"native_workspace_id":5,"number":2,"windows":[{}]},{"active":false,"native_workspace_id":5,"number":3,"windows":[{}]},{"active":false,"native_workspace_id":5,"number":4,"windows":[{}]}]'

run_row() {
  # ${1-...} and not ${1:-...}: an empty payload is the "paneru unreachable"
  # case this suite exercises, and :- would substitute the fixture for it.
  local payload="${1-$ROW_PAYLOAD}" sender="${2:-routine}" name="${3:-space.1}"
  run env ROW_PAYLOAD="$payload" SENDER="$sender" NAME="$name" \
    SKETCHYBAR_LOG="$LOG" SENDCMD_LOG="$SENDCMD_LOG" \
    ROW_PLUGIN="$DOTFILES_DIR/config/sketchybar/plugins/workspace_row.sh" \
    /opt/homebrew/bin/zsh -c '
      sketchybar() { printf "%s\n" "$*" >>"$SKETCHYBAR_LOG"; }
      paneru() {
        if [[ "$1" == "query" ]]; then printf "%s" "$ROW_PAYLOAD"; return; fi
        printf "%s\n" "$*" >>"$SENDCMD_LOG"
      }
      source "$ROW_PLUGIN"
    '
}

@test "the row renders only the active display's spaces" {
  run_row
  [ "$status" -eq 0 ]

  grep -q -- '--set space.1 drawing=on' "$LOG"
  grep -q -- '--set space.2 drawing=on' "$LOG"
  grep -q -- '--set space.9 drawing=off' "$LOG"
  # Native 5's spaces exist in the payload but not on the screen in use.
  ! grep -q -- 'space.3 drawing=on' "$LOG"
  ! grep -q -- 'space.4 drawing=on' "$LOG"
}

@test "the row accents the space you are on and neutrals the rest" {
  run_row
  [ "$status" -eq 0 ]

  grep -q -- 'space.2 drawing=on background.color=0xffb7bdf8 icon.color=0xff24273a' "$LOG"
  grep -q -- 'space.1 drawing=on background.color=0x66494d64 icon.color=0xffcad3f5' "$LOG"
}

@test "clicking a pill switches to that paneru space" {
  run_row "$ROW_PAYLOAD" mouse.clicked space.3
  [ "$status" -eq 0 ]

  grep -q -- 'send-cmd window virtualnum 3' "$SENDCMD_LOG"
  # Switching belongs to the daemon, which emits its own workspace event, so the
  # click must not also redraw the row.
  [ ! -s "$LOG" ]
}

@test "an unreachable paneru leaves the row on its last state" {
  run_row ''
  [ "$status" -eq 0 ]

  # A transient hiccup must not blank the row.
  [ ! -s "$LOG" ]
}

@test "a payload with no active space hides every pill" {
  run_row '[{"active":false,"native_workspace_id":4,"number":1,"windows":[]}]'
  [ "$status" -eq 0 ]

  grep -q -- '--set space.1 drawing=off' "$LOG"
  ! grep -q 'drawing=on' "$LOG"
}

@test "front_app maps Ghostty to a terminal icon instead of the default" {
  run env INFO='Ghostty' NAME='front_app' SKETCHYBAR_LOG="$LOG" \
    /opt/homebrew/bin/zsh -c '
      sketchybar() { printf "%s\n" "$*" >>"$SKETCHYBAR_LOG"; }
      source "$DOTFILES_DIR/config/sketchybar/plugins/front_app.sh"
    '
  [ "$status" -eq 0 ]
  grep -q -- 'icon=' "$LOG"
  ! grep -q -- 'icon=' "$LOG"
}

# --- The Spotifast now-playing item -------------------------------------------
# It replaced Spotify's own widget, which was event-driven and scripted. Neither
# channel exists for Spotifast, so the item is polled from media-control and must
# never claim a track it does not own.

@test "player item uses the bar accent while Spotifast is playing" {
  run_player '{"title":"La Despedida","artist":"Carafea","bundleIdentifier":"me.paolino.fastpotify","playing":true}'
  [ "$status" -eq 0 ]

  grep -q -- '--set spotifast drawing=on' "$LOG"
  grep -q -- 'La Despedida.*Carafea.*label.drawing=yes.*background.color=0xffb7bdf8' "$LOG"
  # Only a playing track is worth moving, so the marquee is on here.
  grep -q -- 'scroll_texts=on' "$LOG"
}

@test "the player keeps its ink readable on the accent surface" {
  run_player '{"title":"La Despedida","artist":"Carafea","bundleIdentifier":"me.paolino.fastpotify","playing":true}'
  [ "$status" -eq 0 ]

  # The accent is a light lilac: the bar's light label default would land at
  # 1.21:1 on it, while the dark ink the other accent pills use measures 8.17:1.
  # A fixed ink cannot serve both surfaces, so it has to travel with the surface.
  grep -q -- 'label.color=0xff24273a' "$LOG"
  grep -q -- 'icon.color=0xff24273a' "$LOG"
}

# The poll runs every 5s and writing an unchanged label restarts the marquee, so
# a state that already matches must produce no label write at all. Every derived
# field is part of that comparison: a run that ignored one left the previous
# state's value behind, which is how the accent pill once drew light ink on a
# light surface and how a paused pill would keep scrolling.
@test "the player pushes the surface when only the surface went stale" {
  run_player_against_state '{"label":{"value":"La Despedida | Carafea","color":"0xffcad3f5"},"geometry":{"background":{"color":"0xffb7bdf8"},"scroll_texts":"on"},"icon":{"color":"0xffcad3f5"}}'
  [ "$status" -eq 0 ]

  grep -q -- 'label.color=0xff24273a' "$LOG"
  grep -q -- 'icon.color=0xff24273a' "$LOG"
}

@test "the player pushes the scroll state when only the scroll went stale" {
  run_player_against_state '{"label":{"value":"La Despedida | Carafea","color":"0xff24273a"},"geometry":{"background":{"color":"0xffb7bdf8"},"scroll_texts":"off"},"icon":{"color":"0xff24273a"}}'
  [ "$status" -eq 0 ]

  grep -q -- 'scroll_texts=on' "$LOG"
}

@test "the player writes no label when the state already matches" {
  run_player_against_state '{"label":{"value":"La Despedida | Carafea","color":"0xff24273a"},"geometry":{"background":{"color":"0xffb7bdf8"},"scroll_texts":"on"},"icon":{"color":"0xff24273a"}}'
  [ "$status" -eq 0 ]

  grep -q -- '--set spotifast drawing=on' "$LOG"
  ! grep -q 'label=' "$LOG"
}

@test "player item drops to the neutral surface while Spotifast is paused" {
  run_player '{"title":"La Despedida","artist":"Carafea","bundleIdentifier":"me.paolino.fastpotify","playing":false}'
  [ "$status" -eq 0 ]

  # The bar carries a single accent, so play state reads as accent vs neutral
  # instead of as two different hues.
  grep -q -- 'La Despedida.*Carafea.*background.color=0x66494d64' "$LOG"
  ! grep -q -- 'background.color=0xffb7bdf8' "$LOG"
  # The neutral surface is dark, so the label keeps the bar's light default.
  grep -q -- 'label.color=0xffcad3f5' "$LOG"
  # Paused means still: the held text parks instead of sliding under the eye.
  grep -q -- 'scroll_texts=off' "$LOG"
}

@test "player item hands over the full text and lets the bar marquee it" {
  run_player '{"title":"Un Titulo Absurdamente Largo Que No Entra","artist":"Un Artista Igualmente Largo","bundleIdentifier":"me.paolino.fastpotify","playing":true}'
  [ "$status" -eq 0 ]

  # SketchyBar only scrolls text that it truncated itself, so the plugin passes
  # the whole string through and leaves label.max_chars + scroll_texts to size
  # and animate it. Truncating here would leave the marquee nothing to move.
  # The stub logs sketchybar's arguments joined, so pull the label back out
  # between its own flag and the next one instead of expecting shell quoting.
  local label
  label="$(sed -n 's/^.* label=\(.*\) label\.drawing=.*$/\1/p' "$LOG" | tail -1)"
  [ -n "$label" ]
  [[ "$label" != *"…"* ]]
  [[ "$label" == *"Absurdamente Largo Que No Entra"* ]]
  [[ "$label" == *"Igualmente Largo"* ]]
}

@test "player item stays hidden when another app owns the MediaRemote feed" {
  run_player '{"title":"Otra Cosa","artist":"Otro","bundleIdentifier":"com.apple.Music","playing":true}'
  [ "$status" -eq 0 ]

  grep -q -- '--set spotifast drawing=off' "$LOG"
  ! grep -q 'label=' "$LOG"
}

@test "player item drops the label when Spotifast holds no track" {
  run_player '{"bundleIdentifier":"me.paolino.fastpotify","playing":false}'
  [ "$status" -eq 0 ]

  grep -q -- 'label= label.drawing=no background.color=0x66494d64' "$LOG"
}

@test "player item hides itself when no MediaRemote reader is installed" {
  run env SKETCHYBAR_LOG="$LOG" PLAYER_PLUGIN="$PLAYER_PLUGIN" \
    SPOTIFAST_MEDIA_CONTROL="spotifast-absent-reader" \
    /opt/homebrew/bin/zsh -c '
      sketchybar() { printf "%s\n" "$*" >>"$SKETCHYBAR_LOG"; }
      NAME=spotifast
      source "$PLAYER_PLUGIN"
    '
  [ "$status" -eq 0 ]

  grep -q -- '--set spotifast drawing=off' "$LOG"
}

@test "clicking the player item toggles Spotifast through media-control" {
  run_player '{"title":"La Despedida","artist":"Carafea","bundleIdentifier":"me.paolino.fastpotify","playing":true}' mouse.clicked
  [ "$status" -eq 0 ]

  grep -q -- 'media-control toggle-play-pause' "$CLICK_LOG"
  ! grep -q 'label=' "$LOG"
}

@test "the bar config polls the shared Spotifast item instead of a notification" {
  local config="$DOTFILES_DIR/config/sketchybar/sketchybarrc"
  /opt/homebrew/bin/zsh -n "$config"
  grep -q 'PLUGIN_SHARED_DIR/spotifast.sh' "$config"
  grep -q -- '--add item spotifast' "$config"
  grep -q -- '--subscribe spotifast mouse.clicked' "$config"
  # The marquee lives in the config: scroll_texts and label.max_chars must be
  # on the item for SketchyBar to scroll the text the plugin no longer cuts.
  grep -q -- 'scroll_texts=on' "$config"
  # The cap is a budget rather than a taste: the label advances 9px per character
  # at 15pt, and the pill shares the notch band with the usage group, so it has to
  # stay far under the 35 characters that used to fit.
  local max_chars
  max_chars="$(sed -n 's/.*label\.max_chars=\([0-9]*\).*/\1/p' "$config")"
  [ -n "$max_chars" ]
  (( max_chars <= 20 ))
  # Spotifast posts no playback notification, so nothing may subscribe to one.
  ! grep -q 'spotify_change\|zapfast_change' "$config"
}

# --- The usage items' provider logos ------------------------------------------
# The logos are generated PNGs sitting next to tracked SVGs (images/README.md).
# Losing one used to degrade all three items to plain text until somebody reran
# rsvg-convert by hand, so the plugin now rasterizes the SVG into its cache.
# These tests need a fake $HOME: the plugin resolves every path from it, and on a
# real machine $HOME/.config/sketchybar is a symlink into the real repo.

usage_payload() {
  printf '%s' '{"providers":{"codex":{"windows":[{"key":"session","usedPercent":12}],"entry":{}},"claude":{"windows":[{"key":"session","usedPercent":34}],"entry":{}},"opencode":{"windows":[{"key":"session","usedPercent":56}],"entry":{}}}}'
}

setup_usage_home() {
  USAGE_HOME="$BATS_TEST_TMPDIR/usage-home"
  rm -rf "$USAGE_HOME"
  mkdir -p "$USAGE_HOME/Library/Fonts" "$USAGE_HOME/.config/sketchybar/images" "$USAGE_HOME/.cache"
  cp "$DOTFILES_DIR/config/sketchybar/images/"*.svg "$USAGE_HOME/.config/sketchybar/images/"
  ln -s "$HOME/Library/Fonts/JetBrainsMonoNerdFont-Medium.ttf" \
    "$USAGE_HOME/Library/Fonts/JetBrainsMonoNerdFont-Medium.ttf"
}

run_usage_plugin() {
  run env HOME="$USAGE_HOME" PAYLOAD="$(usage_payload)" \
    SKETCHYBAR_LOG="$LOG" USAGE_PLUGIN="$DOTFILES_DIR/config/sketchybar/plugins/usage_quotas.sh" \
    /opt/homebrew/bin/zsh -c '
      curl() { printf "%s" "$PAYLOAD"; }
      sketchybar() { printf "%s\n" "$*" >>"$SKETCHYBAR_LOG"; }
      source "$USAGE_PLUGIN"
    '
}

@test "usage plugin rasterizes a missing provider logo instead of degrading to text" {
  command -v magick >/dev/null 2>&1 || skip "needs ImageMagick to composite"
  setup_usage_home
  # Only the tracked SVGs are there: the generated PNGs were lost.
  [ ! -f "$USAGE_HOME/.config/sketchybar/images/codex.png" ]

  run_usage_plugin
  [ "$status" -eq 0 ]

  [ -f "$USAGE_HOME/.cache/usage-quotas/codex.logo.png" ]
  grep -q "usage.codex icon.background.image=$USAGE_HOME/.cache/usage-quotas/codex.png label= label.drawing=off" "$LOG"
}

@test "usage plugin falls back to text only when there is no logo to rasterize" {
  command -v magick >/dev/null 2>&1 || skip "needs ImageMagick to composite"
  setup_usage_home
  rm -f "$USAGE_HOME/.config/sketchybar/images/"*.svg

  run_usage_plugin
  [ "$status" -eq 0 ]

  [ ! -f "$USAGE_HOME/.cache/usage-quotas/codex.logo.png" ]
  grep -q "usage.codex icon.background.image= label=" "$LOG"
  grep -q -- "label.drawing=on" "$LOG"
}

@test "the usage widgets carry no background of their own" {
  local config="$DOTFILES_DIR/config/sketchybar/sketchybarrc" block
  /opt/homebrew/bin/zsh -n "$config"
  block="$(sed -n '/--add item "usage\.\$provider"/,/update_freq=0/p' "$config")"
  [ -n "$block" ]

  # The plugin separates the logo from the percentages inside one composite, so
  # a surface here framed dead space and widened this group into the player pill.
  grep -q -- 'background.drawing=off' <<<"$block"
  grep -q -- 'icon.padding_right=8' <<<"$block"
  grep -q -- 'label.padding_right=8' <<<"$block"

  # The plugin composites a 152px wide image and SketchyBar scales it into the
  # icon, so an icon.width below that product clips the trailing "%" off it.
  local scale width
  scale="$(sed -n 's/.*icon\.background\.image\.scale=\([0-9.]*\).*/\1/p' "$config")"
  width="$(sed -n 's/.*icon\.width=\([0-9]*\).*/\1/p' "$config")"
  [ -n "$scale" ]
  [ -n "$width" ]
  awk -v s="$scale" -v w="$width" 'BEGIN { exit !(w >= 152 * s) }'
}
