#!/usr/bin/env bash
# Tools that Homebrew Bundle does not cover. Sourced by bin/dot.

install_tools() {
  xcode-select -p >/dev/null 2>&1 || run xcode-select --install

  local brew_prefix
  brew_prefix=$(brew --prefix 2>/dev/null || true)
  if [[ -n "$brew_prefix" && -x "$brew_prefix/opt/fzf/install" ]]; then
    run "$brew_prefix/opt/fzf/install" --all --no-bash --no-fish
  fi

  local package key
  for package in rendercv ytsage; do
    pipx list 2>/dev/null | grep -q "package $package" || run pipx install "$package"
  done

  # `|| continue` rather than `&&`: as a function body under `set -e`, a final
  # falsy test would abort the whole install run.
  for key in "$HOME"/.ssh/id_*; do
    case "$key" in *.pub | *.revoked) continue ;; esac
    [[ -f "$key" ]] || continue
    run ssh-add --apple-use-keychain "$key"
  done
}
