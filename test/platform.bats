#!/usr/bin/env bats
# Contract tests for install/platform.sh — the OS detection primitives that
# every platform-conditional branch in this repo reads.
#
# Detection is driven entirely by PATH stubs (including `uname`) so the result
# is a property of the declared fixture, never of the machine running the suite.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
}

# Declare an executable that detection may find on PATH.
stub() {
  printf '#!/bin/sh\n%s\n' "$2" >"$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

# Evaluate a snippet in a shell whose PATH holds ONLY the declared stubs, so a
# binary is visible to detection if and only if a test asked for it. `set -u`
# mirrors bin/dot, the real consumer.
platform_sh() {
  env -i PATH="$STUB_BIN" HOME="${PLATFORM_HOME:-$HOME}" "$BASH" -c \
    'set -u; . "$1/install/platform.sh"; shift; eval "$@"' _ "$DOTFILES_DIR" "$@"
}

# The file git actually treats as the global config, and its bytes.
global_git_snapshot() {
  local file="${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}"
  git config --global --list 2>/dev/null || true
  [[ -f "$file" ]] && sha256sum "$file"
  return 0
}

# ---------------------------------------------------------------------------
# os_family
# ---------------------------------------------------------------------------

@test "os_family reports macos on Darwin" {
  stub uname 'echo Darwin'
  run platform_sh os_family
  [ "$status" -eq 0 ]
  [ "$output" = "macos" ]
}

@test "os_family reports debian on a Linux with apt-get" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run platform_sh os_family
  [ "$status" -eq 0 ]
  [ "$output" = "debian" ]
}

# ASSUMPTION (design.md, spec.md): no Arch host and no hosted Arch runner
# exists, so this branch is covered by a stub and nothing else.
@test "os_family reports arch on a Linux with pacman and no apt-get" {
  stub uname 'echo Linux'
  stub pacman 'exit 0'
  run platform_sh os_family
  [ "$status" -eq 0 ]
  [ "$output" = "arch" ]
}

@test "os_family prefers debian when both apt-get and pacman are present" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  stub pacman 'exit 0'
  run platform_sh os_family
  [ "$status" -eq 0 ]
  [ "$output" = "debian" ]
}

@test "os_family degrades to unknown on a Linux with no recognised manager" {
  stub uname 'echo Linux'
  run platform_sh os_family
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "os_family degrades to unknown on an unrecognised kernel without erroring" {
  stub uname 'echo Plan9'
  run platform_sh os_family
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

# uname itself missing is the harshest degrade case: still a token, still exit 0.
@test "os_family degrades to unknown when uname is not even installed" {
  run platform_sh os_family
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

# ---------------------------------------------------------------------------
# os_pkg_manager
# ---------------------------------------------------------------------------

@test "os_pkg_manager reports brew when brew is on PATH" {
  stub uname 'echo Darwin'
  stub brew 'exit 0'
  run platform_sh os_pkg_manager
  [ "$status" -eq 0 ]
  [ "$output" = "brew" ]
}

@test "os_pkg_manager reports apt-get on a Linux without brew" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run platform_sh os_pkg_manager
  [ "$status" -eq 0 ]
  [ "$output" = "apt-get" ]
}

@test "os_pkg_manager reports pacman when it is the only manager" {
  stub uname 'echo Linux'
  stub pacman 'exit 0'
  run platform_sh os_pkg_manager
  [ "$status" -eq 0 ]
  [ "$output" = "pacman" ]
}

# The whole point of the primitive: absence is reported, never assumed to be brew.
@test "os_pkg_manager prints nothing and fails when no manager is present" {
  stub uname 'echo Linux'
  run platform_sh os_pkg_manager
  [ "$status" -ne 0 ]
  [ "$output" = "" ]
}

# ---------------------------------------------------------------------------
# platform_binary
# ---------------------------------------------------------------------------

@test "platform_binary renames bat and fd on debian" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run platform_sh platform_binary bat
  [ "$status" -eq 0 ]
  [ "$output" = "batcat" ]
  run platform_sh platform_binary fd
  [ "$status" -eq 0 ]
  [ "$output" = "fdfind" ]
}

@test "platform_binary leaves every other name alone on debian" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run platform_sh platform_binary rg
  [ "$status" -eq 0 ]
  [ "$output" = "rg" ]
}

@test "platform_binary is the identity on macos" {
  stub uname 'echo Darwin'
  run platform_sh platform_binary bat
  [ "$status" -eq 0 ]
  [ "$output" = "bat" ]
  run platform_sh platform_binary fd
  [ "$status" -eq 0 ]
  [ "$output" = "fd" ]
}

@test "platform_binary is the identity on arch and unknown" {
  stub uname 'echo Linux'
  stub pacman 'exit 0'
  run platform_sh platform_binary bat
  [ "$status" -eq 0 ]
  [ "$output" = "bat" ]

  rm -f "$STUB_BIN/pacman"
  run platform_sh platform_binary fd
  [ "$status" -eq 0 ]
  [ "$output" = "fd" ]
}

# ---------------------------------------------------------------------------
# Detection is side-effect free (threat matrix: ambient global config)
# ---------------------------------------------------------------------------

@test "ten detection runs are identical and write nothing to HOME or the global git config" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'

  # A pristine HOME rather than the real one: a write the real home already
  # happens to contain would otherwise hide inside the before/after diff.
  local scratch_home="$BATS_TEST_TMPDIR/pristine-home"
  mkdir -p "$scratch_home"

  local cfg_before cfg_after
  cfg_before=$(global_git_snapshot)

  PLATFORM_HOME="$scratch_home" run platform_sh \
    'for _ in 1 2 3 4 5 6 7 8 9 10; do printf "%s/%s\n" "$(os_family)" "$(os_pkg_manager)"; done'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 10 ]
  # Every line is the same non-trivial pair, so the primitives really ran.
  [ "$(printf '%s\n' "${lines[@]}" | sort -u)" = "debian/apt-get" ]

  cfg_after=$(global_git_snapshot)
  [ "$cfg_before" = "$cfg_after" ]
  [ -z "$(ls -A "$scratch_home")" ]
}

# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------

# The primitives are useless unless the CLI has them. Ordering matters: the
# module is sourced after common.sh, alongside every other install/ module.
# Behavioural coverage lives in test/git.bats — dropping this line makes
# `dot git` die with `os_family: command not found`.
@test "bin/dot sources the platform module after common.sh" {
  local dot="$DOTFILES_DIR/bin/dot" common platform
  common=$(grep -n 'install/common\.sh"$' "$dot" | head -1 | cut -d: -f1)
  platform=$(grep -n 'install/platform\.sh"$' "$dot" | head -1 | cut -d: -f1)
  [ -n "$common" ]
  [ -n "$platform" ]
  [ "$platform" -gt "$common" ]
}

# Caching must not turn into staleness within a run: the cached answer has to be
# the answer the first call computed, not an empty or reset one.
@test "the cached family survives repeated calls inside one shell" {
  stub uname 'echo Darwin'
  run platform_sh 'os_family; os_family; platform_binary bat; os_family'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "macos" ]
  [ "${lines[1]}" = "macos" ]
  [ "${lines[2]}" = "bat" ]
  [ "${lines[3]}" = "macos" ]
}
