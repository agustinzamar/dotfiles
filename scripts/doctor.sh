#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR=${1:?missing dotfiles directory}
failed=0
check() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; failed=1; }; }
check_link() { [[ -L "$2" && "$(readlink "$2")" == "$DOTFILES_DIR/$1" ]] || { echo "broken: $2"; failed=1; }; }

for command in brew git zsh jq; do check "$command"; done
check_link config/zsh/.zshrc "$HOME/.zshrc"
check_link config/p10k/.p10k.zsh "$HOME/.p10k.zsh"
check_link config/ghostty/config "$HOME/.config/ghostty/config"
check_link config/tmux/tmux.conf "$HOME/.config/tmux/tmux.conf"
((failed == 0)) && echo "dotfiles: healthy"
exit "$failed"
