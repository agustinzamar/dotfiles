#!/usr/bin/env bats
# Contract tests for the `dot install` guard: package-installing entry points
# run on macOS (Homebrew) and Debian/Ubuntu (apt) and refuse anywhere else.
# The ones that install nothing keep working everywhere.
#
# The sandbox (scratch HOME, curated PATH, `uname` stub, escape guard) lives in
# test/box.bash — read the safety note there before adding a test here.

load box

setup() { box_setup; }
teardown() { box_teardown; }

@test "bare dot install on debian reaches the TTY guard, not a refusal" {
  box_family debian
  run dot_cli install
  [ "$status" -ne 0 ]
  [[ "$output" == *"stdin is not a TTY"* ]]
  [[ "$output" != *"refusing"* ]]
  [ -z "$(find "$SCRATCH_HOME" -mindepth 1)" ]
}

@test "dot install --all --dry-run on debian runs the Debian backend" {
  box_family debian
  run dot_cli install --all --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"refusing"* ]]
  [[ "$output" == *"Full install"* ]]
  [[ "$output" == *"Installation complete"* ]]
}

@test "dot install <topic> --dry-run on debian uses apt, not brew" {
  box_family debian
  run dot_cli install core --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"refusing"* ]]
  [[ "$output" != *"brew bundle"* ]]
  [[ "$output" == *"Debian"* ]]
}

@test "an unknown OS still refuses package installs" {
  box_family unknown
  run dot_cli install --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* ]]
  [[ "$output" != *"Full install"* ]]
  [ -z "$(find "$SCRATCH_HOME" -mindepth 1)" ]
}

@test "an unknown install target still reports the unknown target on debian" {
  box_family debian
  run dot_cli install definitely-not-a-topic
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not an install command or topic"* ]]
  [[ "$output" != *"refusing"* ]]
}

@test "the non-installing subcommands still work on debian" {
  box_family debian
  run dot_cli install code
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS Code not installed"* ]]

  run dot_cli install duti
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping duti"* ]]

  run dot_cli install macos --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "macOS install --all --dry-run is untouched by the guard" {
  box_family macos
  run dot_cli install --all --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"refusing"* ]]
  [[ "$output" == *"brew bundle"* ]]
  [[ "$output" == *"Installation complete"* ]]
}

@test "macOS install <topic> is untouched by the guard" {
  box_family macos
  run dot_cli install core --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"install/topics/core"* ]]
  [[ "$output" != *"refusing"* ]]
}
