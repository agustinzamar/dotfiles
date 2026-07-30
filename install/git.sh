#!/usr/bin/env bash
# Git config. Sourced directly by bin/dot.

# Identity keys (name, email, signing) are never overridden if already set.
# set_git_config skips them automatically — no need for manual guards.

_identity_keys="^user\.(name|email|signingkey)$|^commit\.gpgsign$|^gpg\."

set_git_config() {
  local key=$1 value=$2
  if [[ "$key" =~ $_identity_keys ]] && git config --global --get "$key" &>/dev/null; then
    return 0
  fi
  if [[ "$(git config --global "$key" 2>/dev/null)" == "$value" ]]; then
    return 0
  fi
  run git config --global --replace-all "$key" "$value" 2>/dev/null ||
    run git config --global "$key" "$value"
}

install_git() {
  log "Setting git config"

  local cfg="$DOTFILES_DIR/config/git/config"
  if [[ -f "$cfg" ]]; then
    local key val
    while IFS='=' read -r key val; do
      [[ -n "$key" ]] || continue
      set_git_config "$key" "$val"
    done < <(git config --file "$cfg" --list 2>/dev/null || true)
  fi

  # Credential helper path depends on brew prefix, can't be hardcoded
  local gh_helper
  gh_helper="!$(brew --prefix 2>/dev/null)/bin/gh auth git-credential"
  set_git_config credential.https://github.com.helper "$gh_helper"
  set_git_config credential.https://gist.github.com.helper "$gh_helper"
}
