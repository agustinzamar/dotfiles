#!/usr/bin/env bash
# Rectangle, and getting macOS out of its way. Sourced by `dot macos`.

# Let Rectangle bind shortcuts macOS also claims, rather than refusing them.
defaults write com.knollsoft.Rectangle allowAnyShortcut -bool true

# Spectacle-style shortcut set.
defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true

# Repeating a shortcut cycles through the sizes for that position.
defaults write com.knollsoft.Rectangle subsequentExecutionMode -int 1

# Rectangle updates via Homebrew, so it does not need to check for itself.
defaults write com.knollsoft.Rectangle SUEnableAutomaticChecks -bool false

# macOS tiles a window when you drag it to a screen edge, which fights
# Rectangle's own snapping. Turn the built-in behaviour off and leave window
# management to Rectangle.
defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false
defaults write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false
defaults write com.apple.WindowManager EnableTilingOptionAccelerator -bool false

# No margins around tiled windows.
defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false
