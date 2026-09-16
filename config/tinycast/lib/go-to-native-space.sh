#!/usr/bin/env bash
# Move the active native macOS Space to a 1-based position.
#
# macOS ignores synthesized events for its own Space shortcuts, and yabai's
# `space --focus` is a silent no-op on macOS 27, so switching goes through
# Tinycast's own SpaceSwitcher: this walker reads the two relative-Space hotkeys
# from Tinycast's defaults, presses the one that closes the distance, and
# re-reads paneru after every press until the Space actually moved. A press that
# lands on nothing (keystroke dropped, app busy) is retried instead of being read
# as "the Space did not move", which is the intermittent "had to press twice".
#
# Usage: go-to-native-space.sh <position>
#
# Environment overrides (tests and unusual hosts):
#   TINYCAST_DEFAULTS_DOMAIN  defaults domain holding the hotkeys
set -uo pipefail

TARGET="${1:-}"
case "$TARGET" in
  '' | *[!0-9]*) exit 1 ;;
esac
[ "$TARGET" -ge 1 ] || exit 1

DOMAIN="${TINYCAST_DEFAULTS_DOMAIN:-com.tinycast.app}"
LOCK="${TMPDIR:-/tmp}/tinycast-go-to-native-space.lock"

# The stub directory the tests put first on PATH must win; Homebrew is only a
# fallback for hosts whose PATH lacks the tool (launchd, Tinycast's shell action).
tool() {
  local name="$1" candidate
  candidate="$(command -v "$name" 2>/dev/null)" && {
    printf '%s' "$candidate"
    return 0
  }
  for candidate in /opt/homebrew/bin /usr/local/bin; do
    if [ -x "$candidate/$name" ]; then
      printf '%s' "$candidate/$name"
      return 0
    fi
  done
  return 1
}

PANERU="$(tool paneru)" || exit 1
DEFAULTS="$(tool defaults)" || exit 1
OSASCRIPT="$(tool osascript)" || exit 1
JQ="$(tool jq)" || exit 1

# The two relative-Space hotkey key codes Tinycast is configured with.
hotkey() {
  "$DEFAULTS" read "$DOMAIN" "$1" 2>/dev/null |
    "$JQ" -r '((.combo._0 // .combo) | "\(.carbonKeyCode // "")\t\(.carbonModifiers // "")")' 2>/dev/null
}

read -r FORWARD_CODE FORWARD_MODS <<<"$(hotkey hotkey.windowCommand.previous-space)"
read -r BACKWARD_CODE BACKWARD_MODS <<<"$(hotkey hotkey.windowCommand.next-space)"
[ -n "$FORWARD_CODE" ] && [ -n "$BACKWARD_CODE" ] || exit 1

# Carbon modifier bits -> the AppleScript clause that reproduces the hotkey.
modifier_clause() {
  local bits="${1:-}" names= joined="" name
  [ -n "$bits" ] || return 0
  ((bits & 256)) && names+=("command down")
  ((bits & 512)) && names+=("shift down")
  ((bits & 2048)) && names+=("option down")
  ((bits & 4096)) && names+=("control down")
  [ "${#names[@]}" -gt 0 ] || return 0
  for name in "${names[@]}"; do
    joined="${joined:+$joined, }$name"
  done
  printf ' using {%s}' "$joined"
}

press() {
  local clause
  clause="$(modifier_clause "${2:-}")"
  "$OSASCRIPT" -e "tell application \"System Events\" to key code $1$clause" >/dev/null 2>&1
}

state() { "$PANERU" query state --json 2>/dev/null; }

# Distinct native ids in the order paneru reports them: that sequence is what a
# relative-Space hotkey walks through.
native_ids() {
  state | "$JQ" -r '
    [.virtual_workspaces[].native_workspace_id]
    | reduce .[] as $id ([]; if index($id) then . else . + [$id] end)
    | .[]' 2>/dev/null
}

# 1-based position of the active native Space, or failure when it is not listed.
current_pos() {
  local active ids line position=0
  active="$(state | "$JQ" -r '.active.native_workspace_id // empty' 2>/dev/null)"
  [ -n "$active" ] || return 1
  ids="$(native_ids)"
  [ -n "$ids" ] || return 1
  while IFS= read -r line; do
    position=$((position + 1))
    if [ "$line" = "$active" ]; then
      printf '%s' "$position"
      return 0
    fi
  done <<<"$ids"
  return 1
}

# Serialize runs: an impatient double press used to spawn two walkers fighting
# over the same Space. The second one waits, then finds the work already done.
acquire_lock() {
  local waited=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    # A lock left behind by a killed run must not block later runs forever.
    waited=$((waited + 1))
    if [ "$waited" -gt 200 ]; then
      rm -rf "$LOCK" 2>/dev/null || true
      waited=0
    fi
    sleep 0.05
  done
}

release_lock() { rm -rf "$LOCK" 2>/dev/null || true; }
trap release_lock EXIT INT TERM

total="$(native_ids | wc -l | tr -d ' ')"
[ -n "$total" ] && [ "$total" -ge 1 ] || exit 1

# A target past the last Space clamps to it, so the walk never presses at the edge.
target="$TARGET"
[ "$target" -le "$total" ] || target="$total"

acquire_lock

# Re-read under the lock: a run that waited may find the Space already there.
position="$(current_pos)" || exit 1
[ "$position" = "$target" ] && exit 0

# Each step presses once and re-reads; a press that changed nothing is retried.
# The budget only exists so a Space that never moves ends the run instead of
# spinning: it covers three attempts per step plus the steps themselves.
MAX_ATTEMPTS=5
budget=$((total * MAX_ATTEMPTS + MAX_ATTEMPTS))
performed=0

while [ "$position" != "$target" ] && [ "$performed" -lt "$budget" ]; do
  if [ "$position" -lt "$target" ]; then
    press "$FORWARD_CODE" "$FORWARD_MODS"
  else
    press "$BACKWARD_CODE" "$BACKWARD_MODS"
  fi
  performed=$((performed + 1))

  moved="$(current_pos)" || moved="$position"
  [ -n "$moved" ] || moved="$position"
  position="$moved"
done

[ "$position" = "$target" ] || exit 1
exit 0
