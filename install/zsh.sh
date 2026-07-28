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

migrate_zsh_custom() {
  local old_custom="${HOME}/.dotfiles-custom/shell"
  local new_custom="${HOME}/.dotfiles-home/custom"

  if [[ ! -d "$old_custom" ]]; then
    echo "Nothing to migrate — $old_custom does not exist."
    return 0
  fi

  if "$DRY_RUN"; then
    echo "+ migrate $old_custom/.{exports,aliases,functions,zshrc} → $new_custom/"
    return 0
  fi

  mkdir -p "$new_custom"
  local f base dot_name count=0
  for f in "$old_custom"/.{exports,aliases,functions,zshrc}; do
    [[ -f "$f" ]] || continue
    base=${f##*/}
    dot_name=${base#.}
    if [[ $dot_name == "exports" ]]; then
      run mv "$f" "$new_custom/.exports"
      echo "  moved $f → $new_custom/.exports"
    else
      run mv "$f" "$new_custom/${dot_name}.zsh"
      echo "  moved $f → $new_custom/${dot_name}.zsh"
    fi
    ((count++))
  done

  if ((count > 0)); then
    rmdir "$old_custom" 2>/dev/null || true
    echo "  done — migrated $count file(s)"
  else
    echo "Nothing to migrate — no dotfiles found in $old_custom"
  fi
}