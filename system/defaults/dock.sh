#!/usr/bin/env bash
# Dock contents. Sourced by `dot macos` and `dot dock`.
#
# The Dock is rebuilt from this list, in this order. dockutil needs the full
# path: a bare app name is not resolved.

if ! command -v dockutil >/dev/null 2>&1; then
  echo "dockutil not installed, skipping Dock setup" >&2
  return 0
fi

DOCK_APPS=(
  "/Applications/System Settings.app"
  "/Applications/WhatsApp.app"
  "/Applications/Discord.app"
  "/Applications/Zoom.app"
  "/Applications/Slack.app"
  "/Applications/Google Chrome.app"
  "/Applications/Claude.app"
  "/Applications/OrbStack.app"
  "/Applications/Docker Desktop.app"
  "/Applications/Visual Studio Code.app"
  "/Applications/Ghostty.app"
  "/Applications/PhpStorm.app"
  "/Applications/Spotify.app"
  "/Applications/Telegram.app"
)

dockutil --no-restart --remove all

# Ensure a single Finder entry at the beginning. dockutil may or may not remove
# it with `--remove all`, so explicitly remove any existing entry first.
dockutil --no-restart --remove Finder >/dev/null 2>&1 || true
if [[ -d "/System/Library/CoreServices/Finder.app" ]]; then
  dockutil --no-restart --add "/System/Library/CoreServices/Finder.app" --position 1
fi

# if/fi rather than `&&`: sourced under `set -e`, a final missing app would
# abort the whole run. Apps can be absent when a cask has yet to install.
for dock_app in "${DOCK_APPS[@]}"; do
  if [[ -d "$dock_app" ]]; then
    dockutil --no-restart --add "$dock_app"
  else
    echo "skipping, not installed: $dock_app" >&2
  fi
done

# Trash is recreated automatically by macOS when the Dock restarts.
# `|| true`: killall exits 1 when the Dock is not running, which under the
# caller's `set -e` would abort the run.
killall Dock || true
