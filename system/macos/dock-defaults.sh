#!/usr/bin/env bash
# Dock contents. Sourced by `dot macos` and `dot dock`.

dockutil --no-restart --remove all
# dockutil --no-restart --add "/Applications/Google Chrome.app"
# dockutil --no-restart --add "PhpStorm"
# dockutil --no-restart --add "Vscode"
# dockutil --no-restart --add "Muxy"
# dockutil --no-restart --add "Ghostty"

killall Dock
