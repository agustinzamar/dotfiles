#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR=${1:?missing dotfiles directory}
git -C "$DOTFILES_DIR" pull
brew update
brew upgrade
"$DOTFILES_DIR/install.sh" "${@:2}"
