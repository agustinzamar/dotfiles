#!/usr/bin/env bash
# Git config. Sourced by bin/dot via install/tools.sh (or standalone).

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

  set_git_config credential.https://github.com.helper ""
  set_git_config credential.https://github.com.helper "!$(brew --prefix 2>/dev/null)/bin/gh auth git-credential"
  set_git_config credential.https://gist.github.com.helper ""
  set_git_config credential.https://gist.github.com.helper "!$(brew --prefix 2>/dev/null)/bin/gh auth git-credential"
  set_git_config core.autocrlf input
  set_git_config push.autoSetupRemote true
  set_git_config rebase.autoStash true
  set_git_config fetch.prune true
  set_git_config help.autocorrect immediate
  set_git_config color.ui auto
}