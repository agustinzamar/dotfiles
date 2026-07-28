#!/usr/bin/env bash
# Zinit plugin manager. Sourced by bin/dot.

install_zsh() {
  local zinit_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

  if [[ -d "$zinit_dir" ]]; then
    :
  elif "$DRY_RUN"; then
    echo '+ install zinit'
  else
    mkdir -p "$(dirname "$zinit_dir")"
    run git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$zinit_dir"
  fi
}