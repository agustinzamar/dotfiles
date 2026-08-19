#!/usr/bin/env bash
# Bootstrap a fresh machine in one line:
#
#   curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash
#
# Clones this repo to ~/dotfiles and runs the installer. config/zsh/.zshrc puts
# the CLI on PATH from $DOTFILES_DIR.

set -Eeuo pipefail

REPO_URL="https://github.com/agustinzamar/dotfiles"
TARGET="${DOTFILES_DIR:-$HOME/dotfiles}"

is_executable() { type "$1" >/dev/null 2>&1; }

if [[ -d "$TARGET/.git" ]]; then
  echo "==> $TARGET already exists, pulling"
  git -C "$TARGET" pull --ff-only
elif is_executable git; then
  echo "==> Cloning into $TARGET"
  git clone "$REPO_URL" "$TARGET"
else
  # git arrives with the Xcode command line tools, which `dot install` triggers
  # anyway. The tarball path covers the window before they are there.
  echo "==> No git yet, fetching a tarball into $TARGET"
  mkdir -p "$TARGET"
  if is_executable curl; then
    curl -fsSL "$REPO_URL/tarball/main" | tar -xz --strip-components=1 -C "$TARGET"
  elif is_executable wget; then
    wget -qO- "$REPO_URL/tarball/main" | tar -xz --strip-components=1 -C "$TARGET"
  else
    echo "No git, curl or wget available. Aborting." >&2
    exit 1
  fi
fi

exec "$TARGET/bin/dot" install "$@"
