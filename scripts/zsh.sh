#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR=${1:?missing dotfiles directory}
DRY_RUN=${2:-false}

run() {
  if "$DRY_RUN"; then
    printf '+ '; printf '%q ' "$@"; printf '\n'
  else
    "$@"
  fi
}

if [[ -d "$HOME/.oh-my-zsh" ]]; then
  :
elif "$DRY_RUN"; then
  echo '+ install Oh My Zsh'
else
  env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

for spec in \
  "romkatv/powerlevel10k|$HOME/.oh-my-zsh/custom/themes/powerlevel10k" \
  "zsh-users/zsh-autosuggestions|$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
  "Aloxaf/fzf-tab|$HOME/.oh-my-zsh/custom/plugins/fzf-tab" \
  "zdharma-continuum/fast-syntax-highlighting|$HOME/.oh-my-zsh/custom/plugins/fast-syntax-highlighting"; do
  repo=${spec%%|*}; dest=${spec#*|}
  [[ -d "$dest" ]] || run git clone --depth=1 "https://github.com/$repo.git" "$dest"
done
