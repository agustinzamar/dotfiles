#!/usr/bin/env bash
# Git config. Sourced directly by bin/dot.

# Identity keys (name, email, signing) are never overridden if already set.
# set_git_config skips them automatically — no need for manual guards.

_identity_keys="^user\.(name|email|signingkey)$|^commit\.gpgsign$|^gpg\."

# Owned by the resolution below, never replayed from the tracked config file:
# that file can only ever hardcode one machine's absolute gh path, which is how
# `!/opt/homebrew/bin/gh` ended up in the global config of hosts without brew.
_gh_helper_keys="^credential\.https://(gist\.)?github\.com\.helper$"

_gh_credential_keys=(
  "credential.https://github.com.helper"
  "credential.https://gist.github.com.helper"
)

# The helper value git should exec, or nothing when none is usable. git runs the
# value as a shell word, so a relative path (resolved against git's cwd, not
# ours) or one containing whitespace would break at fetch time — better to write
# nothing than something that cannot run.
_gh_credential_helper() {
  local gh
  gh=$(command -v gh 2>/dev/null) || return 0
  [[ "$gh" == /* && "$gh" != *[[:space:]]* ]] || return 0
  printf '!%s auth git-credential' "$gh"
}

# True for a helper of ours whose command no longer exists. Overwriting is not
# enough: when nothing resolves there is no replacement to write, so the dead
# value would survive and git would keep exec'ing it on every fetch.
_gh_helper_is_stale() {
  local value=$1 path
  [[ "$value" == '!'*' auth git-credential' ]] || return 1
  path=${value#'!'}
  path=${path%' auth git-credential'}
  [[ -n "$path" && ! -x "$path" ]]
}

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
  local cfg="$DOTFILES_DIR/config/git/config"
  if [[ -f "$cfg" ]]; then
    local key val
    while IFS='=' read -r key val; do
      [[ -n "$key" ]] || continue
      if [[ "$key" =~ $_gh_helper_keys ]]; then continue; fi
      set_git_config "$key" "$val"
    done < <(git config --file "$cfg" --list 2>/dev/null || true)
  fi

  # Derived from the real binary. `brew --prefix` used to stand in for it, which
  # on a host without Homebrew expands to nothing and wrote `!/bin/gh ...` — and
  # aborted the whole phase under `set -e` when brew was not installed at all.
  local helper key
  helper=$(_gh_credential_helper)
  for key in "${_gh_credential_keys[@]}"; do
    if [[ -n "$helper" ]]; then
      set_git_config "$key" "$helper"
    elif _gh_helper_is_stale "$(git config --global "$key" 2>/dev/null || true)"; then
      run git config --global --unset-all "$key"
    fi
  done
}
