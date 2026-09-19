#!/usr/bin/env bats
# Contract tests for SketchyBar's item plugins and both bar variants.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PLAYER_PLUGIN="$DOTFILES_DIR/config/sketchybar/plugins/spotifast.sh"
  LOG="$BATS_TEST_TMPDIR/sketchybar.log"
  CLICK_LOG="$BATS_TEST_TMPDIR/media-control.log"
  : >"$LOG"
  : >"$CLICK_LOG"
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

@test "both bar variants carry the battery item on the shared plugin" {
  local config
  for config in \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-laptop" \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-desktop"; do
    /opt/homebrew/bin/zsh -n "$config"
    grep -q -- '--add item battery' "$config"
    grep -q 'PLUGIN_SHARED_DIR/battery.sh' "$config"
    # The desktop default label colour is dark, which suits the accent pills but
    # renders a transparent item invisible, so the battery must declare its own.
    awk '/--add item battery/,/^$/' "$config" | grep -q 'label.color='
  done
}

# sketchybar lays left-side items out left-to-right in creation order and
# right-side items from the display edge inward (src/bar.c,
# bar_calculate_bounds_top_bottom). The paneru indicator therefore has to be a
# left-side item created before front_app; adding it last among the right-side
# items could never put it there.
@test "the paneru indicator is a left-side item created before front_app" {
  local config current_line front_line
  for config in \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-laptop" \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-desktop"; do
    /opt/homebrew/bin/zsh -n "$config"
    grep -q -- '--add item current_space left' "$config"
    ! grep -q -- '--add item current_space right' "$config"

    current_line="$(grep -n -- '--add item current_space left' "$config" | cut -d: -f1)"
    front_line="$(grep -n -- '--add item front_app left' "$config" | cut -d: -f1)"
    [ -n "$current_line" ]
    [ -n "$front_line" ]
    (( current_line < front_line ))
  done
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
}

@test "player item drops to the neutral surface while Spotifast is paused" {
  run_player '{"title":"La Despedida","artist":"Carafea","bundleIdentifier":"me.paolino.fastpotify","playing":false}'
  [ "$status" -eq 0 ]

  # The bar carries a single accent, so play state reads as accent vs neutral
  # instead of as two different hues.
  grep -q -- 'La Despedida.*Carafea.*background.color=0x66494d64' "$LOG"
  ! grep -q -- 'background.color=0xffb7bdf8' "$LOG"
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

@test "both bar variants poll the shared Spotifast item instead of a notification" {
  local config
  for config in \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-laptop" \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-desktop"; do
    /opt/homebrew/bin/zsh -n "$config"
    grep -q 'PLUGIN_SHARED_DIR/spotifast.sh' "$config"
    grep -q -- '--add item spotifast' "$config"
    grep -q -- '--subscribe spotifast mouse.clicked' "$config"
    # The marquee lives in the config: scroll_texts and label.max_chars must be
    # on the item for SketchyBar to scroll the text the plugin no longer cuts.
    grep -q -- 'scroll_texts=on' "$config"
    grep -q -- 'label.max_chars=35' "$config"
    # Spotifast posts no playback notification, so nothing may subscribe to one.
    ! grep -q 'spotify_change\|zapfast_change' "$config"
  done
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
