#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=${1:-false}
run() {
  if "$DRY_RUN"; then
    printf '+ '; printf '%q ' "$@"; printf '\n'
  else
    "$@"
  fi
}

defaults_write() { run defaults write "$1" "$2" "-$3" "$4"; }

defaults_write com.apple.finder AppleShowAllExtensions bool true
defaults_write com.apple.finder AppleShowAllFiles bool true
defaults_write com.apple.finder ShowPathbar bool true
defaults_write com.apple.finder _FXShowPosixPathInTitle bool true
defaults_write com.apple.dock autohide bool true
defaults_write com.apple.dock show-recents bool false
defaults_write com.apple.dock orientation string left
defaults_write com.apple.screencapture type string png
defaults_write com.apple.screencapture location string "$HOME/Desktop"
defaults_write NSGlobalDomain AppleShowScrollBars string Always
defaults_write NSGlobalDomain KeyRepeat int 2
defaults_write NSGlobalDomain InitialKeyRepeat int 15
defaults_write com.apple.desktopservices DSDontWriteNetworkStores bool true
defaults_write com.apple.coreservices.useractivityd ActivityCacheAllowed bool false
run killall Finder
run killall Dock
