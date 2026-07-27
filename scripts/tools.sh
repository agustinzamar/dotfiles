#!/usr/bin/env bash
set -Eeuo pipefail

DRY_RUN=${1:-false}
run() {
  if "$DRY_RUN"; then
    printf '+ '; printf '%q ' "$@"; printf '\n'
  else
    "$@"
  fi
}

if ! xcode-select -p >/dev/null 2>&1; then run xcode-select --install; fi
if [[ -x "$(brew --prefix 2>/dev/null)/opt/fzf/install" ]]; then
  run "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish
fi
if ! npm list -g --depth=0 opentmux >/dev/null 2>&1; then run npm install -g opentmux; fi
for package in rendercv ytsage; do
  pipx list 2>/dev/null | grep -q "package $package" || run pipx install "$package"
done
for key in "$HOME"/.ssh/id_*; do
  case "$key" in *.pub|*.revoked) continue ;; esac
  [[ -f "$key" ]] && run ssh-add --apple-use-keychain "$key"
done
