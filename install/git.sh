#!/usr/bin/env bash
# Git config. Sourced by bin/dot via install/tools.sh (or standalone).

# Only set non-identity settings — name/email/gpg stay local per machine.
# If you want to pin them in the repo, set them in config/git/config and
# add yourself to the symlink list in install/links.sh.

set_git_config() {
  local key=$1 value=$2
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