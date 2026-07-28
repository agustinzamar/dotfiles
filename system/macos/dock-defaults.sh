#!/usr/bin/env bash
# Dock contents. Sourced by `dot macos` and `dot dock`.
#
# The Dock is rebuilt from this list, in this order. dockutil needs the full
# path: a bare app name is not resolved.

DOCK_APPS=(
  "/Applications/WhatsApp.app"
  "/Applications/Discord.app"
  "/Applications/Google Chrome.app"
  "/Applications/OrbStack.app"
  "/Applications/PhpStorm.app"
  "/Applications/Visual Studio Code.app"
  "/Applications/Muxy.app"
  "/Applications/Ghostty.app"
)

dockutil --no-restart --remove all

# if/fi rather than `&&`: sourced under `set -e`, a final missing app would
# abort the whole run. Apps can be absent when a cask has yet to install.
for dock_app in "${DOCK_APPS[@]}"; do
  if [[ -d "$dock_app" ]]; then
    dockutil --no-restart --add "$dock_app"
  else
    echo "skipping, not installed: $dock_app" >&2
  fi
done

# `|| true`: killall exits 1 when the Dock is not running, which under the
# caller's `set -e` would abort the run.
killall Dock || true
