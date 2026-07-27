#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR=${1:?missing dotfiles directory}
ONLY=${2:-all}
DRY_RUN=${3:-false}
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%dT%H%M%S)"

run() {
  if "$DRY_RUN"; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

link_file() {
  local source="$DOTFILES_DIR/$1" target=$2 current
  [[ -e "$source" || -L "$source" ]] || { echo "missing source: $source" >&2; return 1; }
  mkdir -p "$(dirname "$target")"
  current=$(readlink "$target" 2>/dev/null || true)
  [[ "$current" == "$source" ]] && return 0
  if [[ -e "$target" || -L "$target" ]]; then
    run mkdir -p "$BACKUP_DIR"
    run mv "$target" "$BACKUP_DIR/$(basename "$target")"
  fi
  run ln -s "$source" "$target"
}

link_shell() {
  link_file config/zsh/.zshrc "$HOME/.zshrc"
  link_file config/p10k/.p10k.zsh "$HOME/.p10k.zsh"
  link_file home/.exports "$HOME/.dotfiles-home/.exports"
  for file in home/aliases/*.zsh home/functions/*.zsh; do
    link_file "$file" "$HOME/.dotfiles-home/${file#home/}"
  done
}

link_all() {
  link_shell
  link_file config/ghostty/config "$HOME/.config/ghostty/config"
  link_file config/tmux/tmux.conf "$HOME/.config/tmux/tmux.conf"
  link_file config/yazi/yazi.toml "$HOME/.config/yazi/yazi.toml"
  link_file config/yazi/keymap.toml "$HOME/.config/yazi/keymap.toml"
  link_file config/yazi/theme.toml "$HOME/.config/yazi/theme.toml"
  link_file config/ghostty/config "$HOME/Library/Application Support/Muxy/ghostty.conf"
  link_file config/npm/.npmrc "$HOME/.npmrc"
  link_file home/functions/mysql.zsh "$HOME/.dotfiles-home/functions/mysql.zsh"
  link_file home/aliases/composer.zsh "$HOME/.dotfiles-home/aliases/composer.zsh"
  link_file home/functions/docker.zsh "$HOME/.dotfiles-home/functions/docker.zsh"
  link_file config/herd/herd.json "$HOME/Library/Application Support/Herd/config/herd.json"
  link_file home/aliases/laravel.zsh "$HOME/.dotfiles-home/aliases/laravel.zsh"
  link_file home/functions/laravel.zsh "$HOME/.dotfiles-home/functions/laravel.zsh"
  link_file config/vscode/settings.json "$HOME/Library/Application Support/Code/User/settings.json"
  link_file config/vscode/keybindings.json "$HOME/Library/Application Support/Code/User/keybindings.json"
  link_file config/claude/settings.json "$HOME/.claude/settings.json"
  link_file config/opencode/skills "$HOME/.claude/skills"
  link_file config/opencode/agents "$HOME/.claude/agents"
  link_file config/opencode/AGENTS.md "$HOME/.config/opencode/AGENTS.md"
  link_file config/opencode/plugins "$HOME/.config/opencode/plugins"
  link_file config/opencode/skills "$HOME/.config/opencode/skills"
  link_file config/opencode/themes "$HOME/.config/opencode/themes"
  link_file config/opencode/agents "$HOME/.config/opencode/agents"
  link_file config/opencode/commands "$HOME/.config/opencode/commands"
  link_file config/hunk/config.toml "$HOME/.config/hunk/config.toml"
  link_file config/mackup/dotfiles-custom.cfg "$HOME/.mackup/dotfiles-custom.cfg"
}

case "$ONLY" in
  all) link_all ;;
  shell) link_shell ;;
  *) echo "unsupported --only value: $ONLY" >&2; exit 2 ;;
esac
