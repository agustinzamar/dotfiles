#!/usr/bin/env bash
# Dock settings. Sourced by `dot dock` (and by `dot install`).

defaults_write com.apple.dock autohide bool true
defaults_write com.apple.dock show-recents bool false
defaults_write com.apple.dock orientation string left

run killall Dock
