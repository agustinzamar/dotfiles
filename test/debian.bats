#!/usr/bin/env bats
# Contract tests for install/debian.sh — the Ubuntu backend that translates
# Brewfile topics into apt plus official upstream installers.
#
# All installers run with DRY_RUN=true, so no test touches apt, the network,
# or HOME. OS family is a PATH stub (`uname` + `apt-get`), never the host.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB_BIN="$BATS_TEST_TMPDIR/deb-bin"
  mkdir -p "$STUB_BIN"
  export DRY_RUN=true
  export DOTFILES_DIR
}

stub() {
  printf '#!/bin/sh\n%s\n' "$2" >"$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

# Source the installer stack with only stub binaries visible.
debian_sh() {
  env -i PATH="$STUB_BIN:/usr/bin:/bin" HOME="$BATS_TEST_TMPDIR/home" \
    DOTFILES_DIR="$DOTFILES_DIR" DRY_RUN=true "$BASH" -c \
    'set -u; . "$0/install/common.sh"; . "$0/install/platform.sh"; . "$0/install/debian.sh"; eval "$1"' \
    "$DOTFILES_DIR" "$1"
}

@test "apt mapping covers the terminal basics" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  for id in zsh git gh fzf zoxide eza ripgrep bat jq btop neovim lazygit; do
    run debian_sh "debian_apt_package_for $id"
    [ "$status" -eq 0 ] || { echo "no apt mapping for $id"; return 1; }
    [ -n "$output" ]
  done
}

@test "fd and bat map to their debian-renamed packages" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run debian_sh "debian_apt_package_for fd"
  [ "$status" -eq 0 ]
  [ "$output" = "fd-find" ]
  run debian_sh "debian_apt_package_for bat"
  [ "$status" -eq 0 ]
  [ "$output" = "bat" ]
}

@test "custom tools have no apt mapping" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  for id in oh-my-posh mise rust yazi superfile pay-respects topgrade; do
    run debian_sh "debian_apt_package_for $id"
    [ "$status" -ne 0 ]
  done
}

@test "macOS-only ids are skipped, portable ids are not" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  for id in sketchybar duti dockutil mole orbstack; do
    run debian_sh "debian_is_macos_only $id"
    [ "$status" -eq 0 ] || { echo "$id should be macOS-only"; return 1; }
  done
  run debian_sh "debian_is_macos_only git"
  [ "$status" -ne 0 ]
  run debian_sh "debian_is_macos_only fzf"
  [ "$status" -ne 0 ]
}

@test "debian_install_one dry-runs apt for a mapped id" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run debian_sh "debian_install_one fzf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt-get install"* ]]
  [[ "$output" == *"fzf"* ]]
}

@test "debian_install_one dry-runs the oh-my-posh installer" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run debian_sh "debian_install_one oh-my-posh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ohmyposh"* ]] || [[ "$output" == *"oh-my-posh"* ]]
}

@test "debian_install_one dry-runs the opencode installer" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run debian_sh "debian_install_one anomalyco/tap/opencode"
  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode.ai"* ]] || [[ "$output" == *"already installed"* ]]
}

@test "debian_install_one skips macOS-only ids without failing" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run debian_sh "debian_install_one sketchybar"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
  run debian_sh "debian_install_one duti"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "debian bootstrap dry-runs apt essentials, never Xcode" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  run debian_sh "debian_bootstrap"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt"* ]]
  [[ "$output" != *"Xcode"* ]]
  [[ "$output" == *"zsh"* ]]
  [[ "$output" == *"git"* ]]
}

@test "rust goes through rustup, never apt" {
  stub uname 'echo Linux'
  stub apt-get 'exit 0'
  stub rustc 'echo "rustc 1.93.1 (test)"'
  stub cargo 'exit 0'
  run debian_sh "debian_install_one rust"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rustup"* ]] || [[ "$output" == *"Rust"* ]]
  [[ "$output" != *"apt-get install -y rustc"* ]]
}
