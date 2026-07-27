#!/usr/bin/env bash
# macOS system defaults. Sourced by `dot macos`, which globs macos/defaults*.sh.

defaults_write com.apple.finder AppleShowAllExtensions bool true
defaults_write com.apple.finder AppleShowAllFiles bool true
defaults_write com.apple.finder ShowPathbar bool true
defaults_write com.apple.finder _FXShowPosixPathInTitle bool true
defaults_write com.apple.screencapture type string png
defaults_write com.apple.screencapture location string "$HOME/Desktop"
defaults_write NSGlobalDomain AppleShowScrollBars string Always
defaults_write NSGlobalDomain KeyRepeat int 2
defaults_write NSGlobalDomain InitialKeyRepeat int 15
defaults_write com.apple.desktopservices DSDontWriteNetworkStores bool true
defaults_write com.apple.coreservices.useractivityd ActivityCacheAllowed bool false

run killall Finder
