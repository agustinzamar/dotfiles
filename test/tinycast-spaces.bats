#!/usr/bin/env bats
# Contract tests for config/tinycast/lib/go-to-native-space.sh.
#
# Real Space switching cannot be exercised from a test (it moves the user's
# desktop and the host may be in use), so the whole environment is stubbed:
#   paneru     -> a state machine reading/writing a cursor file
#   defaults   -> reports the two Tinycast relative-Space hotkeys
#   osascript  -> the "key press" that advances the state machine
# The stub directory goes FIRST on PATH and the script only falls back to
# Homebrew when a tool is missing, so the stubs win.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$DOTFILES_DIR/config/tinycast/lib/go-to-native-space.sh"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"

  # Three native Spaces, mirroring the real ids seen on this machine.
  NATIVES="$BATS_TEST_TMPDIR/natives.json"
  printf '5\n162\n323\n' >"$NATIVES"
  CURSOR="$BATS_TEST_TMPDIR/cursor"
  PRESSES="$BATS_TEST_TMPDIR/presses"
  : >"$PRESSES"

  # paneru query state --json -> the active position and the full id list.
  cat >"$STUB_BIN/paneru" <<'STUB'
#!/bin/sh
NATIVES="${STUB_NATIVES:?}"
CURSOR="${STUB_CURSOR:?}"
pos="$(cat "$CURSOR" 2>/dev/null || echo 1)"
active="$(sed -n "${pos}p" "$NATIVES")"
ids="$(paste -sd, "$NATIVES")"
printf '{"active":{"native_workspace_id":%s},"virtual_workspaces":[%s]}\n' \
  "$active" "$(printf '%s' "$ids" | tr ',' '\n' | sed 's/^/{"native_workspace_id":/; s/$/}/' | paste -sd, -)"
STUB

  # defaults read <plist> hotkey.windowCommand.<action>
  cat >"$STUB_BIN/defaults" <<'STUB'
#!/bin/sh
case "$3" in
  hotkey.windowCommand.previous-space) echo '{"combo":{"_0":{"carbonKeyCode":124,"carbonModifiers":256}}}' ;;
  hotkey.windowCommand.next-space) echo '{"combo":{"_0":{"carbonKeyCode":123,"carbonModifiers":256}}}' ;;
  *) exit 1 ;;
esac
STUB

  # osascript -e 'tell application "System Events" to key code N ...'
  # 124 = forward (previous-space), 123 = backward (next-space).
  cat >"$STUB_BIN/osascript" <<'STUB'
#!/bin/sh
NATIVES="${STUB_NATIVES:?}"
CURSOR="${STUB_CURSOR:?}"
PRESSES="${STUB_PRESSES:?}"
code="$(printf '%s' "$*" | sed -n 's/.*key code \([0-9][0-9]*\).*/\1/p')"
echo "$code" >>"$PRESSES"
pos="$(cat "$CURSOR" 2>/dev/null || echo 1)"
count="$(wc -l <"$NATIVES" | tr -d ' ')"
case "$code" in
  124) [ "$pos" -lt "$count" ] && pos=$((pos + 1)) ;;
  123) [ "$pos" -gt 1 ] && pos=$((pos - 1)) ;;
esac
echo "$pos" >"$CURSOR"
exit 0
STUB

  chmod +x "$STUB_BIN/paneru" "$STUB_BIN/defaults" "$STUB_BIN/osascript"
  echo 1 >"$CURSOR"
}

go() {
  local target="$1"
  run env \
    PATH="$STUB_BIN:$PATH" \
    STUB_NATIVES="$NATIVES" STUB_CURSOR="$CURSOR" STUB_PRESSES="$PRESSES" \
    "$SCRIPT" "$target"
}

@test "already at the target makes no key press" {
  go 1
  [ "$status" -eq 0 ]
  [ ! -s "$PRESSES" ]
}

@test "walks forward to a later position" {
  go 3
  [ "$status" -eq 0 ]
  [ "$(cat "$CURSOR")" -eq 3 ]
}

@test "walks backward to an earlier position" {
  echo 3 >"$CURSOR"
  go 1
  [ "$status" -eq 0 ]
  [ "$(cat "$CURSOR")" -eq 1 ]
}

# The first version accepted any movement instead of only movement that closes
# the distance, so walking backward oscillated and never arrived. It also
# probed the direction blindly, spending an extra no-op press at the edge.
@test "walking backward takes one press and never pushes forward" {
  echo 3 >"$CURSOR"
  go 2
  [ "$status" -eq 0 ]
  [ "$(cat "$CURSOR")" -eq 2 ]
  [ "$(wc -l <"$PRESSES" | tr -d ' ')" -eq 1 ]
  [ "$(grep -c '^124$' "$PRESSES" || true)" -eq 0 ]
}

@test "a target beyond the last Space clamps to the last one" {
  go 9
  [ "$status" -eq 0 ]
  [ "$(cat "$CURSOR")" -eq 3 ]
}

@test "calibrates direction even when starting at the far edge" {
  echo 3 >"$CURSOR"
  go 1
  [ "$status" -eq 0 ]
  [ "$(cat "$CURSOR")" -eq 1 ]
}

@test "fails when no key press moves the active Space" {
  cat >"$STUB_BIN/osascript" <<'STUB'
#!/bin/sh
echo noop >>"${STUB_PRESSES:?}"
exit 0
STUB
  chmod +x "$STUB_BIN/osascript"

  go 3
  [ "$status" -eq 1 ]
}

@test "rejects a non-numeric target" {
  go "abc"
  [ "$status" -eq 1 ]
  [ ! -s "$PRESSES" ]
}

# The SketchyBar click handler must reach the same walker; the old version
# synthesized ctrl+left/right, which macOS ignores for its own Space shortcuts.
@test "the SketchyBar click handler delegates to the walker" {
  local wrapper="$DOTFILES_DIR/config/sketchybar/plugins/focus-native-space.sh"
  [ -x "$wrapper" ]

  run env \
    PATH="$STUB_BIN:$PATH" \
    STUB_NATIVES="$NATIVES" STUB_CURSOR="$CURSOR" STUB_PRESSES="$PRESSES" \
    "$wrapper" 3

  [ "$status" -eq 0 ]
  [ "$(cat "$CURSOR")" -eq 3 ]
}

@test "a single Space clamps every target to it without pressing a key" {
  printf '5\n' >"$NATIVES"
  go 2
  [ "$status" -eq 0 ]
  [ "$(cat "$CURSOR")" -eq 1 ]
  [ ! -s "$PRESSES" ]
}

# A dropped press never lands, so "no change" must be retried instead of being
# read as "the Space did not move". This is the intermittent "had to press
# twice" failure.
@test "a dropped key press is retried until the Space moves" {
  DROPPED="$BATS_TEST_TMPDIR/dropped"
  cat >"$STUB_BIN/osascript" <<'STUB'
#!/bin/sh
NATIVES="${STUB_NATIVES:?}"; CURSOR="${STUB_CURSOR:?}"
PRESSES="${STUB_PRESSES:?}"; DROPPED="${STUB_DROPPED:?}"
code="$(printf '%s' "$*" | sed -n 's/.*key code \([0-9][0-9]*\).*/\1/p')"
echo "$code" >>"$PRESSES"
# Swallow the very first press of the whole run.
if [ ! -s "$DROPPED" ]; then echo "$code" >"$DROPPED"; exit 0; fi
pos="$(cat "$CURSOR" 2>/dev/null || echo 1)"
count="$(wc -l <"$NATIVES" | tr -d ' ')"
case "$code" in
  124) [ "$pos" -lt "$count" ] && pos=$((pos + 1)) ;;
  123) [ "$pos" -gt 1 ] && pos=$((pos - 1)) ;;
esac
echo "$pos" >"$CURSOR"
exit 0
STUB
  chmod +x "$STUB_BIN/osascript"

  run env \
    PATH="$STUB_BIN:$PATH" \
    STUB_NATIVES="$NATIVES" STUB_CURSOR="$CURSOR" STUB_PRESSES="$PRESSES" STUB_DROPPED="$DROPPED" \
    "$SCRIPT" 3

  [ "$status" -eq 0 ]
  [ "$(cat "$CURSOR")" -eq 3 ]
  # 2 genuine steps + the 1 swallowed press.
  [ "$(wc -l <"$PRESSES" | tr -d ' ')" -eq 3 ]
}

# Impatient double presses used to spawn two walkers fighting over the same
# Space. Runs are serialized, so the second one finds the work already done.
@test "an overlapping run waits instead of fighting for the same Space" {
  cat >"$STUB_BIN/osascript" <<'STUB'
#!/bin/sh
NATIVES="${STUB_NATIVES:?}"; CURSOR="${STUB_CURSOR:?}"; PRESSES="${STUB_PRESSES:?}"
code="$(printf '%s' "$*" | sed -n 's/.*key code \([0-9][0-9]*\).*/\1/p')"
echo "$code" >>"$PRESSES"
sleep 0.2
pos="$(cat "$CURSOR" 2>/dev/null || echo 1)"
count="$(wc -l <"$NATIVES" | tr -d ' ')"
case "$code" in
  124) [ "$pos" -lt "$count" ] && pos=$((pos + 1)) ;;
  123) [ "$pos" -gt 1 ] && pos=$((pos - 1)) ;;
esac
echo "$pos" >"$CURSOR"
exit 0
STUB
  chmod +x "$STUB_BIN/osascript"

  env PATH="$STUB_BIN:$PATH" \
    STUB_NATIVES="$NATIVES" STUB_CURSOR="$CURSOR" STUB_PRESSES="$PRESSES" \
    "$SCRIPT" 3 >/dev/null 2>&1 &
  local first=$!
  env PATH="$STUB_BIN:$PATH" \
    STUB_NATIVES="$NATIVES" STUB_CURSOR="$CURSOR" STUB_PRESSES="$PRESSES" \
    "$SCRIPT" 3 >/dev/null 2>&1
  wait "$first"

  [ "$(cat "$CURSOR")" -eq 3 ]
  # Exactly the two real steps of one walker; the second made none.
  [ "$(wc -l <"$PRESSES" | tr -d ' ')" -le 2 ]
}

@test "the serialization lock is released after the run" {
  go 2
  [ "$status" -eq 0 ]
  [ ! -e "${TMPDIR:-/tmp}/tinycast-go-to-native-space.lock" ]
}
