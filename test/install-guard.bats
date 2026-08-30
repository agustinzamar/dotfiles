#!/usr/bin/env bats
# Contract tests for the `dot install` guard: the entry points that install
# Homebrew packages must refuse on a host that has no Homebrew to install them
# with, and the ones that install nothing must keep working everywhere.
#
# The sandbox (scratch HOME, curated PATH, `uname` stub, escape guard) lives in
# test/box.bash — read the safety note there before adding a test here.

load box

setup() { box_setup; }
teardown() { box_teardown; }

@test "bare dot install on debian refuses before the TTY guard" {
  box_family debian
  run dot_cli install
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* ]]
  [[ "$output" == *"macOS"* ]]
  # The refusal must come first: the TTY guard is about how to install, not
  # about whether this host can be installed to at all.
  [[ "$output" != *"stdin is not a TTY"* ]]
  [ -z "$(find "$SCRATCH_HOME" -mindepth 1)" ]
}

@test "dot install --all on debian refuses and runs no phase" {
  box_family debian
  run dot_cli install --all
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* ]]
  [[ "$output" != *"Full install"* ]]
  [[ "$output" != *"Bootstrap"* ]]
  [ -z "$(find "$SCRATCH_HOME" -mindepth 1)" ]
}

@test "dot install --profile on debian refuses and never reaches the TUI" {
  box_family debian
  printf '{"components":{}}\n' >"$SCRATCH/profile.json"
  run dot_cli install --profile "$SCRATCH/profile.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* ]]
  [[ "$output" != *"dot-tui"* ]]
  [ -z "$(find "$SCRATCH_HOME" -mindepth 1)" ]
}

@test "a Brewfile topic on debian refuses, as a subcommand and bare" {
  box_family debian
  run dot_cli install core
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* ]]
  [[ "$output" != *"brew bundle"* ]]

  run dot_cli media --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing"* ]]
  [[ "$output" != *"brew bundle"* ]]
}

@test "the non-installing subcommands still work on debian" {
  box_family debian
  run dot_cli install code
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS Code not installed"* ]]

  run dot_cli install duti
  [ "$status" -eq 0 ]
  [[ "$output" == *"duti not installed"* ]]

  run dot_cli install macos --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"macos.sh"* ]]
}

@test "an unknown install target still reports the unknown target on debian" {
  box_family debian
  run dot_cli install definitely-not-a-topic
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not an install command or topic"* ]]
  [[ "$output" != *"refusing"* ]]
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
