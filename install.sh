#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE=personal
ONLY=all
DRY_RUN=false

usage() {
  sed -n 's/^# //p' "$0"
}

# Usage: ./install.sh [--profile personal|work] [--only shell] [--dry-run]
while (($#)); do
  case "$1" in
    --profile) PROFILE=${2:?missing profile}; shift 2 ;;
    --only) ONLY=${2:?missing section}; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

run() {
  if "$DRY_RUN"; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

log() { printf '\n==> %s\n' "$*"; }

if [[ "$ONLY" == all ]]; then
  log "Installing Homebrew"
  if command -v brew >/dev/null 2>&1; then
    :
  elif "$DRY_RUN"; then
    echo '+ install Homebrew'
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  log "Installing packages ($PROFILE)"
  run brew bundle --file="$DOTFILES_DIR/Brewfile"
  if [[ -f "$DOTFILES_DIR/Brewfile.$PROFILE" ]]; then
    run brew bundle --file="$DOTFILES_DIR/Brewfile.$PROFILE"
  fi
fi

"$DOTFILES_DIR/scripts/links.sh" "$DOTFILES_DIR" "$ONLY" "$DRY_RUN"
"$DOTFILES_DIR/scripts/zsh.sh" "$DOTFILES_DIR" "$DRY_RUN"

if [[ "$ONLY" == all ]]; then
  "$DOTFILES_DIR/scripts/tools.sh" "$DRY_RUN"
  "$DOTFILES_DIR/scripts/git.sh" "$DOTFILES_DIR" "$DRY_RUN"
  "$DOTFILES_DIR/scripts/macos.sh" "$DRY_RUN"
fi

log "Installation complete"
