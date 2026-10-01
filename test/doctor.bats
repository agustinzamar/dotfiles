#!/usr/bin/env bats
# Contract tests for `dot doctor`'s platform-conditional health checks.
#
# The sandbox (scratch HOME, curated PATH, `uname` stub, escape guard) lives in
# test/box.bash — read the safety note there before adding a test here. `brew`
# is deliberately absent from that PATH: whether it is required at all is
# exactly what this file is about.

load box

setup() { box_setup; }
teardown() { box_teardown; }

# doctor walks the link map, so every applicable row must already be linked
# before a "healthy" assertion means anything. --all bypasses the component and
# requirement gates, which is what makes a complete tree reachable in a box.
linked_box() {
  box_family "$1"
  dot_cli link --all >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# The package manager is platform-conditional (task 4.1)
# ---------------------------------------------------------------------------

@test "doctor on debian does not require Homebrew" {
  linked_box debian
  run dot_cli doctor
  [ "$status" -eq 0 ]
  [[ "$output" != *"missing: brew"* ]]
  [[ "$output" == *"dotfiles: healthy"* ]]
}

@test "doctor on macOS without Homebrew reports it missing and fails" {
  linked_box macos
  run dot_cli doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing: brew"* ]]
}

@test "doctor on macOS with every requirement satisfied is healthy" {
  linked_box macos
  stub brew 'exit 0'
  run dot_cli doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles: healthy"* ]]
  [[ "$output" != *"missing:"* ]]
}

# ---------------------------------------------------------------------------
# The universal requirements are never relaxed (task 4.2)
# ---------------------------------------------------------------------------

@test "doctor requires jq on debian" {
  linked_box debian
  rm "$REAL_BIN/jq"
  run dot_cli doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing: jq"* ]]
}

@test "doctor requires git on debian" {
  linked_box debian
  rm "$REAL_BIN/git"
  run dot_cli doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing: git"* ]]
}

@test "doctor requires dot on PATH on debian" {
  linked_box debian
  rm "$REAL_BIN/dot"
  run dot_cli doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"not on PATH: dot"* ]]
}

@test "an unknown OS enforces the universal set and no package manager" {
  linked_box unknown
  run dot_cli doctor
  [ "$status" -eq 0 ]
  [[ "$output" != *"missing: brew"* ]]
  [[ "$output" != *"missing: apt-get"* ]]
  [[ "$output" == *"dotfiles: healthy"* ]]
}

@test "an unknown OS still fails without jq" {
  linked_box unknown
  rm "$REAL_BIN/jq"
  run dot_cli doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing: jq"* ]]
}

# ---------------------------------------------------------------------------
# Link health honors OS applicability (task 4.3)
# ---------------------------------------------------------------------------

@test "doctor reports no broken macOS-only target on debian" {
  linked_box debian
  run dot_cli doctor
  [ "$status" -eq 0 ]
  [[ "$output" != *"broken:"* ]]
  [[ "$output" != *"Library"* ]]
}

@test "doctor on macOS still reports a broken Library target" {
  linked_box macos
  stub brew 'exit 0'
  # The row is gated on `code`, so the fixture has to declare the tool before
  # its absence is a fault rather than the gate doing its job.
  stub code 'exit 0'
  rm "$SCRATCH_HOME/Library/Application Support/Code/User/settings.json"
  run dot_cli doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken: $SCRATCH_HOME/Library/Application Support/Code/User/settings.json"* ]]
}

@test "doctor ignores a requirement-gated row whose tool is absent" {
  # --all force-links the gated rows too, so the missing target below cannot be
  # mistaken for "never linked because its tool is missing".
  linked_box macos
  stub brew 'exit 0'
  rm "$SCRATCH_HOME/.config/zsh/exports/yazi.zsh"
  run dot_cli doctor
  [ "$status" -eq 0 ]
  [[ "$output" != *"zsh/exports/yazi.zsh"* ]]
  [[ "$output" == *"dotfiles: healthy"* ]]
}
