#!/usr/bin/env bats
# Contract tests for the `dot git` phase: the GitHub credential helper and the
# ssh-add key registration loop.
#
# SAFETY. `dot git` writes to the *global* git config. Every invocation here is
# boxed with HOME=$scratch **and** GIT_CONFIG_GLOBAL=$scratch/.gitconfig: HOME
# alone still leaves $XDG_CONFIG_HOME/git/config reachable, and on a machine
# where ~/.gitconfig is a symlink into this repo a leak would edit tracked
# source. setup() records the real global config and teardown() proves it was
# never touched. Nothing in this file may invoke bin/dot outside dot_git().

# Every location git would consult for "global" config, plus what it resolves to.
real_global_snapshot() {
  local file
  for file in "${GIT_CONFIG_GLOBAL:-}" "$HOME/.gitconfig" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/git/config"; do
    [[ -n "$file" ]] || continue
    if [[ -e "$file" ]]; then sha256sum "$file"; else echo "absent $file"; fi
  done
  git config --global --list 2>/dev/null || true
}

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOT="$DOTFILES_DIR/bin/dot"
  REAL_GLOBAL_BEFORE=$(real_global_snapshot)

  SCRATCH="$BATS_TEST_TMPDIR/box"
  SCRATCH_HOME="$SCRATCH/home"
  SCRATCH_GITCONFIG="$SCRATCH_HOME/.gitconfig"
  STUB_BIN="$SCRATCH/stub"
  REAL_BIN="$SCRATCH/real"
  mkdir -p "$SCRATCH_HOME/.ssh" "$STUB_BIN" "$REAL_BIN"
  chmod 700 "$SCRATCH_HOME/.ssh"

  # A curated PATH built from symlinks, because `gh` must be absent unless a
  # test asks for it. Prepending a stub directory is not enough: `command -v gh`
  # would still find the real one further down the inherited PATH.
  local tool path
  for tool in bash sh env git date sed grep basename dirname paste cat ls \
    mkdir rm mv cp ln readlink cmp sort uniq head tail tr cut wc find stat \
    chmod mktemp xargs awk uname tput id; do
    if path=$(command -v "$tool" 2>/dev/null); then
      ln -sf "$path" "$REAL_BIN/$tool"
    fi
  done

  SSH_ADD_LOG="$SCRATCH/ssh-add.log"
  : >"$SSH_ADD_LOG"
  stub ssh-add "printf '%s\n' \"\$*\" >>'$SSH_ADD_LOG'; exit 0"
}

teardown() {
  local after
  after=$(real_global_snapshot)
  if [[ "$REAL_GLOBAL_BEFORE" != "$after" ]]; then
    echo "FATAL: this test escaped the box and changed the real global git config"
    diff <(printf '%s\n' "$REAL_GLOBAL_BEFORE") <(printf '%s\n' "$after") || true
    return 1
  fi
}

stub() {
  printf '#!/bin/sh\n%s\n' "$2" >"$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

# The only sanctioned way to run the CLI in this file.
dot_git() {
  env -i \
    HOME="$SCRATCH_HOME" \
    GIT_CONFIG_GLOBAL="$SCRATCH_GITCONFIG" \
    GIT_CONFIG_NOSYSTEM=1 \
    PATH="$STUB_BIN:${EXTRA_BIN:+$EXTRA_BIN:}$REAL_BIN" \
    TERM=dumb \
    "$DOT" git "$@"
}

boxed_get() { git config --file "$SCRATCH_GITCONFIG" --get "$1" 2>/dev/null || true; }

# The spec writes this fixture as `!/bin/gh auth git-credential`, but on a
# merged-/usr distro `/bin` is `/usr/bin`, so `/bin/gh` is the *real* gh and the
# value would not be corrupt at all. What matters is that the command does not
# resolve, so the fixture points at a path guaranteed never to exist.
CORRUPT_HELPER='!/nonexistent/bin/gh auth git-credential'

seed_corrupt_helpers() {
  git config --file "$SCRATCH_GITCONFIG" \
    credential.https://github.com.helper "$CORRUPT_HELPER"
  git config --file "$SCRATCH_GITCONFIG" \
    credential.https://gist.github.com.helper "$CORRUPT_HELPER"
}

seed_ssh_keys() {
  printf 'PRIVATE\n' >"$SCRATCH_HOME/.ssh/id_ed25519"
  printf 'PUBLIC\n' >"$SCRATCH_HOME/.ssh/id_ed25519.pub"
  printf 'REVOKED\n' >"$SCRATCH_HOME/.ssh/id_rsa.revoked"
  chmod 600 "$SCRATCH_HOME/.ssh"/id_*
}

# ---------------------------------------------------------------------------
# The box itself
# ---------------------------------------------------------------------------

# If this fails, every other test in the file is meaningless: they would all be
# asserting against the developer's real configuration.
@test "the box redirects global writes into the scratch config" {
  [ ! -e "$SCRATCH_GITCONFIG" ]
  run dot_git
  [ "$status" -eq 0 ]
  [ -f "$SCRATCH_GITCONFIG" ]
  # A key from config/git/config landed in the box, proving the phase ran here.
  [ "$(boxed_get pull.rebase)" = "true" ]
}

# ---------------------------------------------------------------------------
# Credential helper resolution
# ---------------------------------------------------------------------------

@test "gh on PATH becomes the helper for both GitHub hosts" {
  stub gh 'exit 0'
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(boxed_get credential.https://github.com.helper)" = "!$STUB_BIN/gh auth git-credential" ]
  [ "$(boxed_get credential.https://gist.github.com.helper)" = "!$STUB_BIN/gh auth git-credential" ]
}

# The tracked config/git/config hardcodes an absolute Homebrew gh path. Replaying
# it is exactly the "construct the path from a package-manager prefix" the spec
# forbids, so with no gh the keys must simply not exist.
@test "no gh on PATH writes no credential helper at all" {
  run dot_git
  [ "$status" -eq 0 ]
  [ -z "$(boxed_get credential.https://github.com.helper)" ]
  [ -z "$(boxed_get credential.https://gist.github.com.helper)" ]
  ! grep -q 'auth git-credential' "$SCRATCH_GITCONFIG"
  ! grep -q '/opt/homebrew' "$SCRATCH_GITCONFIG"
  # The rest of the phase still ran, so the absence above is a decision.
  [ "$(boxed_get pull.rebase)" = "true" ]
}

@test "a second dot git leaves the global config byte-identical" {
  stub gh 'exit 0'
  run dot_git
  [ "$status" -eq 0 ]
  local first
  first=$(sha256sum "$SCRATCH_GITCONFIG" | cut -d' ' -f1)
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$SCRATCH_GITCONFIG" | cut -d' ' -f1)" = "$first" ]
  [ "$(boxed_get credential.https://github.com.helper)" = "!$STUB_BIN/gh auth git-credential" ]
}

# ---------------------------------------------------------------------------
# Corrupted helper cleanup
# ---------------------------------------------------------------------------

@test "an unresolvable helper is unset when no gh is present" {
  [ ! -e /nonexistent/bin/gh ]
  seed_corrupt_helpers
  run dot_git
  [ "$status" -eq 0 ]
  [ -z "$(boxed_get credential.https://github.com.helper)" ]
  [ -z "$(boxed_get credential.https://gist.github.com.helper)" ]
  ! grep -q 'nonexistent' "$SCRATCH_GITCONFIG"
}

@test "an unresolvable helper is replaced when gh resolves" {
  seed_corrupt_helpers
  stub gh 'exit 0'
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(boxed_get credential.https://github.com.helper)" = "!$STUB_BIN/gh auth git-credential" ]
  [ "$(boxed_get credential.https://gist.github.com.helper)" = "!$STUB_BIN/gh auth git-credential" ]
  ! grep -q 'nonexistent' "$SCRATCH_GITCONFIG"
}

# A helper this repo did not write is somebody else's business.
@test "a foreign credential helper is left alone" {
  git config --file "$SCRATCH_GITCONFIG" \
    credential.https://github.com.helper 'manager-core'
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(boxed_get credential.https://github.com.helper)" = "manager-core" ]
}

# A resolvable helper pointing somewhere else still works, so it is not stale.
@test "a resolvable helper at another path is not unset" {
  local other="$SCRATCH/other"
  mkdir -p "$other"
  printf '#!/bin/sh\nexit 0\n' >"$other/gh"
  chmod +x "$other/gh"
  git config --file "$SCRATCH_GITCONFIG" \
    credential.https://github.com.helper "!$other/gh auth git-credential"
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(boxed_get credential.https://github.com.helper)" = "!$other/gh auth git-credential" ]
}

# ---------------------------------------------------------------------------
# Shell-command composition (threat matrix)
# ---------------------------------------------------------------------------

# git execs the helper string as a shell word, so a path containing whitespace
# would break at use time. Refusing beats writing something that cannot run.
@test "a gh path containing a space is refused, not written" {
  local spaced="$SCRATCH/gh dir"
  mkdir -p "$spaced"
  printf '#!/bin/sh\nexit 0\n' >"$spaced/gh"
  chmod +x "$spaced/gh"

  EXTRA_BIN="$spaced" run dot_git
  [ "$status" -eq 0 ]
  [ -z "$(boxed_get credential.https://github.com.helper)" ]
  [ -z "$(boxed_get credential.https://gist.github.com.helper)" ]
  ! grep -q 'auth git-credential' "$SCRATCH_GITCONFIG"
}

# ---------------------------------------------------------------------------
# ssh-add is platform-gated
# ---------------------------------------------------------------------------

@test "Linux registers keys without the macOS keychain flag" {
  seed_ssh_keys
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(cat "$SSH_ADD_LOG")" = "$SCRATCH_HOME/.ssh/id_ed25519" ]
}

@test "macOS keeps the keychain flag" {
  seed_ssh_keys
  stub uname 'echo Darwin'
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(cat "$SSH_ADD_LOG")" = "--apple-use-keychain $SCRATCH_HOME/.ssh/id_ed25519" ]
}

@test "an unknown platform also drops the keychain flag" {
  seed_ssh_keys
  stub uname 'echo Plan9'
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(cat "$SSH_ADD_LOG")" = "$SCRATCH_HOME/.ssh/id_ed25519" ]
}

@test "public and revoked keys are skipped on every platform" {
  seed_ssh_keys
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run dot_git
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$SSH_ADD_LOG")" -eq 1 ]
  ! grep -q '\.pub' "$SSH_ADD_LOG"
  ! grep -q '\.revoked' "$SSH_ADD_LOG"
}

@test "an ssh directory with no private keys registers nothing and still exits 0" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run dot_git
  [ "$status" -eq 0 ]
  [ ! -s "$SSH_ADD_LOG" ]
}
