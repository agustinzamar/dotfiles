#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR=${1:?missing dotfiles directory}
mackup backup dotfiles-custom --force || echo "mackup backup failed; continuing with git"
if [[ -z "$(git -C "$DOTFILES_DIR" status --porcelain)" ]]; then
  echo "No changes to commit."
  exit 0
fi
git -C "$DOTFILES_DIR" add -A
git -C "$DOTFILES_DIR" commit -m "backup: $(date '+%Y-%m-%d %H:%M')"
git -C "$DOTFILES_DIR" push
