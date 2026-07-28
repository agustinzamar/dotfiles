# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Source exports early so zinit plugins find brewed binaries
source "${HOME}/.dotfiles-home/.exports"

# === Zinit (plugin manager) — auto-installs if missing ===
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME/.git" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Completions path
fpath=("${HOME}/.dotfiles-home/completions" $fpath)

# === Plugins ===

# Powerlevel10k (not turbo — needed for prompt)
zinit ice depth=1
zinit light romkatv/powerlevel10k

# Oh My Zsh plugins (turbo)
zinit wait lucid for \
  OMZP::git \
  OMZP::gh \
  OMZP::docker \
  OMZP::docker-compose \
  OMZP::composer \
  OMZP::laravel \
  OMZP::nvm \
  OMZP::npm \
  OMZP::extract \
  OMZP::zoxide \
  OMZP::fzf \
  OMZP::command-not-found

# Custom plugins (turbo, light mode)
zinit wait lucid light-mode for \
  atinit"zicompinit; zinit cdreplay -q" \
    zdharma-continuum/fast-syntax-highlighting \
  atload"_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions \
  Aloxaf/fzf-tab

bindkey -e
bindkey '^P' history-search-backward
bindkey '^N' history-search-forward

HISTFILE="${HOME}/.zsh_history"
HISTSIZE=5000
SAVEHIST=$HISTSIZE
setopt hist_ignore_dups
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt hist_save_no_dups
setopt hist_find_no_dups
setopt appendhistory
setopt sharehistory

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no

# fzf-tab: preview directories with eza
zstyle ':fzf-tab:complete:*:*' fzf-preview 'eza -la --icons --group-directories-first --color --no-permissions --no-filesize --no-user $realpath'

typeset -U path PATH

# === Added by dotfiles ===
for f in "${HOME}"/.dotfiles-home/aliases/*.zsh(N); do source "$f"; done
for f in "${HOME}"/.dotfiles-home/functions/*.zsh(N); do source "$f"; done

# Load private custom overrides (not committed)
[[ -f "${HOME}/.dotfiles-home/custom/.exports" ]] && source "${HOME}/.dotfiles-home/custom/.exports"
for f in "${HOME}"/.dotfiles-home/custom/*.zsh(N); do source "$f"; done

# Per-tool environment, one file each, sourced in filename order. See
# system/env/ in the dotfiles repo.
for f in "${HOME}"/.dotfiles-home/env/*.zsh(N); do source "$f"; done

# Last, so the prompt config wins over anything a tool init changed.
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh