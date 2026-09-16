#!/usr/bin/env bats
# Contract tests for SketchyBar's native macOS Spaces integration.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PLUGIN="$DOTFILES_DIR/config/sketchybar/plugins/native_spaces.sh"
  PLAYER_PLUGIN="$DOTFILES_DIR/config/sketchybar/plugins/spotifast.sh"
  LOG="$BATS_TEST_TMPDIR/sketchybar.log"
  CLICK_LOG="$BATS_TEST_TMPDIR/media-control.log"
  : >"$LOG"
  : >"$CLICK_LOG"
}

run_native_spaces() {
  local state="$1"
  run env PANERU_OUTPUT="$state" SKETCHYBAR_LOG="$LOG" PLUGIN="$PLUGIN" \
    /opt/homebrew/bin/zsh -c '
      paneru() { printf "%s" "$PANERU_OUTPUT"; }
      sketchybar() { printf "%s\n" "$*" >>"$SKETCHYBAR_LOG"; }
      NAME=native_space.1
      source "$PLUGIN"
    '
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

@test "native spaces groups virtual rows by native id and highlights the active native" {
  run_native_spaces '{"active":{"native_workspace_id":162},"virtual_workspaces":[{"number":1,"native_workspace_id":5},{"number":2,"native_workspace_id":5},{"number":1,"native_workspace_id":162,"active":true}]}'
  [ "$status" -eq 0 ]

  grep -q -- '--set native_space.1' "$LOG"
  grep -q -- 'native_space.1.*icon.drawing=on.*icon=.*label.drawing=off.*background.color=0x66494d64' "$LOG"
  grep -q -- 'native_space.1.*click_script=.*focus-native-space.sh 1' "$LOG"
  grep -q -- 'native_space.2.*icon.drawing=on.*icon=.*label.drawing=off.*background.color=0xfff5a97f' "$LOG"
  grep -q -- 'native_space.2.*click_script=.*focus-native-space.sh 2' "$LOG"
  grep -q -- 'native_space.3.*drawing=off' "$LOG"
}

@test "native spaces highlights the first native when it is active" {
  run_native_spaces '{"active":{"native_workspace_id":5},"virtual_workspaces":[{"number":1,"native_workspace_id":5},{"number":2,"native_workspace_id":5},{"number":1,"native_workspace_id":162}]}'
  [ "$status" -eq 0 ]

  grep -q -- 'native_space.1.*icon=.*background.color=0xfff5a97f' "$LOG"
  grep -q -- 'native_space.2.*icon=.*background.color=0x66494d64' "$LOG"
}

@test "native spaces shows numbers with no icon from the third slot on" {
  run_native_spaces '{"active":{"native_workspace_id":30},"virtual_workspaces":[{"number":1,"native_workspace_id":10},{"number":1,"native_workspace_id":20},{"number":1,"native_workspace_id":30},{"number":1,"native_workspace_id":40}]}'
  [ "$status" -eq 0 ]

  grep -q -- 'native_space.1.*icon.drawing=on.*icon=' "$LOG"
  grep -q -- 'native_space.2.*icon.drawing=on.*icon=' "$LOG"
  grep -q -- 'native_space.3.*drawing=on.*icon.drawing=off.*label.drawing=on.*label=3' "$LOG"
  grep -q -- 'native_space.4.*drawing=on.*icon.drawing=off.*label.drawing=on.*label=4' "$LOG"
}

@test "native spaces caps the visible pool at ten slots" {
  local state
  state="$(/opt/homebrew/bin/jq -cn '{active: {native_workspace_id: 1}, virtual_workspaces: [range(1;12) | {number: 1, native_workspace_id: .}]}')"
  run_native_spaces "$state"
  [ "$status" -eq 0 ]

  [ "$(grep -c -- '--set native_space.' "$LOG")" -eq 10 ]
  grep -q -- 'native_space.1.*drawing=on.*icon.drawing=on.*icon=' "$LOG"
  grep -q -- 'native_space.2.*drawing=on.*icon.drawing=on.*icon=' "$LOG"
  grep -q -- 'native_space.10.*drawing=on.*icon.drawing=off.*label=10' "$LOG"
  ! grep -q -- 'native_space.11' "$LOG"
}

@test "native spaces hides the whole pool when paneru returns invalid data" {
  run_native_spaces 'not-json'
  [ "$status" -eq 0 ]

  [ "$(grep -c -- 'drawing=off' "$LOG")" -eq 10 ]
}

@test "both bar variants define the native spaces item pool and updater" {
  local config
  for config in \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-laptop" \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-desktop"; do
    /opt/homebrew/bin/zsh -n "$config"
    grep -q 'native_spaces.sh' "$config"
    grep -q 'native_space.1' "$config"
  done
}

# sketchybar lays left-side items out left-to-right in creation order and
# right-side items from the display edge inward (src/bar.c,
# bar_calculate_bounds_top_bottom). The paneru indicator therefore has to be a
# left-side item created after the native_space pool and before front_app;
# adding it last among the right-side items could never put it there.
@test "the paneru indicator sits between the native space pool and front_app" {
  local config current_line native_line front_line
  for config in \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-laptop" \
    "$DOTFILES_DIR/config/sketchybar/sketchybarrc-desktop"; do
    /opt/homebrew/bin/zsh -n "$config"
    grep -q -- '--add item "native_space.\$slot" left' "$config"
    grep -q -- '--add item current_space left' "$config"
    ! grep -q -- '--add item current_space right' "$config"

    native_line="$(grep -n -- '--add item "native_space.\$slot" left' "$config" | cut -d: -f1)"
    current_line="$(grep -n -- '--add item current_space left' "$config" | cut -d: -f1)"
    front_line="$(grep -n -- '--add item front_app left' "$config" | cut -d: -f1)"
    [ -n "$native_line" ]
    [ -n "$current_line" ]
    [ -n "$front_line" ]
    (( native_line < current_line ))
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

@test "player item shows the track in green while Spotifast is playing" {
  run_player '{"title":"La Despedida","artist":"Carafea","bundleIdentifier":"me.paolino.fastpotify","playing":true}'
  [ "$status" -eq 0 ]

  grep -q -- '--set spotifast drawing=on' "$LOG"
  grep -q -- 'La Despedida.*Carafea.*label.drawing=yes.*background.color=0xffa6da95' "$LOG"
}

@test "player item turns amber while Spotifast is paused" {
  run_player '{"title":"La Despedida","artist":"Carafea","bundleIdentifier":"me.paolino.fastpotify","playing":false}'
  [ "$status" -eq 0 ]

  grep -q -- 'La Despedida.*Carafea.*background.color=0xffeed49f' "$LOG"
  ! grep -q -- 'background.color=0xffa6da95' "$LOG"
}

@test "player item truncates a long track and artist to fit the bar" {
  run_player '{"title":"Un Titulo Absurdamente Largo Que No Entra","artist":"Un Artista Igualmente Largo","bundleIdentifier":"me.paolino.fastpotify","playing":true}'
  [ "$status" -eq 0 ]

  # The stub logs sketchybar's arguments joined, so pull the label back out
  # between its own flag and the next one instead of expecting shell quoting.
  local label
  label="$(sed -n 's/^.* label=\(.*\) label\.drawing=.*$/\1/p' "$LOG" | tail -1)"
  [ -n "$label" ]
  [[ "$label" == *"…"* ]]
  [[ "$label" != *"Absurdamente Largo Que No Entra"* ]]
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

  grep -q -- 'background.color=0xffeed49f label.drawing=no' "$LOG"
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
  ln -s "$HOME/Library/Fonts/JetBrainsMonoNerdFont-Bold.ttf" \
    "$USAGE_HOME/Library/Fonts/JetBrainsMonoNerdFont-Bold.ttf"
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
