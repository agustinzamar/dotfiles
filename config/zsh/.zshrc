# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Source exports early so zinit plugins find brewed binaries
source "${HOME}/dotfiles/system/.exports"

# Set nvim as default editor for opencode and other tools
export EDITOR="nvim"
export VISUAL="nvim"

export LS_COLORS="di=38;5;67:ow=48;5;60:ex=38;5;132:ln=38;5;144:*.tar=38;5;180:*.zip=38;5;180:*.jpg=38;5;175:*.png=38;5;175:*.mp3=38;5;175:*.wav=38;5;175:*.txt=38;5;223:*.sh=38;5;132"

# === Zinit (plugin manager) — auto-installs if missing ===
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME/.git" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Completions path
fpath=("${HOME}/dotfiles/system/completions" $fpath)

# Powerlevel10k (not turbo — needed for prompt)
zinit ice depth=1
zinit light romkatv/powerlevel10k

# Oh My Zsh plugins (turbo, light mode)
zinit wait lucid light-mode for \
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
  OMZP::command-not-found \
  OMZP::per-directory-history/per-directory-history.zsh \
  OMZP::history \
  OMZP::sudo

# Custom plugins (turbo, light mode)
# fzf-tab must load after compinit but BEFORE widget-wrapping plugins
# (fast-syntax-highlighting, zsh-autosuggestions), otherwise autosuggestions
# wraps fzf-tab's widget and Tab both accepts the suggestion AND completes.
zinit wait lucid light-mode for \
  atinit"zicompinit; zinit cdreplay -q" \
    Aloxaf/fzf-tab \
  zdharma-continuum/fast-syntax-highlighting \
  atload"_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions \
  atload"bindkey '\e[A' history-substring-search-up; bindkey '\e[B' history-substring-search-down" \
    OMZP::history-substring-search/history-substring-search.zsh \
  jirutka/zsh-shift-select

# Emacs mode
bindkey -e

# History search with up/down arrows based on current input.
# Fallback only: history-substring-search rebinds these in its atload above.
bindkey '\e[A' history-search-backward
bindkey '\e[B' history-search-forward

# Bind magic space to expand aliases and history words
bindkey ' ' magic-space

# Open buffer line in editor (vim, nvim, or code) with Ctrl-X Ctrl-E
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^x^e' edit-command-line

# Copy the current command line to the clipboard with Ctrl-X Ctrl-C
copy-command-line() {
  print -n -- "$BUFFER" | pbcopy
}
zle -N copy-command-line
bindkey '^x^c' copy-command-line

# Enable zmv for batch renaming (used with noglob aliases in aliases/filesystem.zsh)
autoload -U zmv

# History settings
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

# Completion settings
# Case/hyphen-insensitive, then substring anywhere ("back" -> "auditboard-backend")
zstyle ':completion:*' matcher-list 'm:{a-zA-Z-_}={A-Za-z_-}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no

# fzf-tab: preview directories with eza
zstyle ':fzf-tab:complete:*:*' fzf-preview 'eza -la --icons --group-directories-first --color --no-permissions --no-filesize --no-user $realpath'

# fzf default opts: smart-case matching (case-insensitive unless the query
# contains uppercase), consistent across Ctrl-T / Ctrl-R / **<TAB> / fzf-tab.
export FZF_DEFAULT_OPTS='--ansi --layout=reverse --info=inline --smart-case'
export FZF_CTRL_R_OPTS='--sort'
export FZF_CTRL_T_OPTS='--preview "bat --color=always --line-range=:100 {} 2>/dev/null || eza -la --icons {}"'
export FZF_ALT_C_OPTS='--preview "eza -la --icons --color=always --group-directories-first {}"'

typeset -U path PATH

# Load aliases and functions, in filename order. See system/aliases/ and system/functions/ in the dotfiles repo.
for f in "${HOME}"/dotfiles/system/aliases/*.zsh(N); do source "$f"; done
for f in "${HOME}"/dotfiles/system/functions/*.zsh(N); do source "$f"; done

# Load private custom overrides (not committed, machine-specific)
for f in "${HOME}"/.dotfiles-custom/exports/*.zsh(N); do source "$f"; done
for f in "${HOME}"/.dotfiles-custom/aliases/*.zsh(N); do source "$f"; done
for f in "${HOME}"/.dotfiles-custom/functions/*.zsh(N); do source "$f"; done

# Per-tool environment, one file each, sourced in filename order. See
# system/env/ in the dotfiles repo.
for f in "${HOME}"/dotfiles/system/env/*.zsh(N); do source "$f"; done

# Last, so the prompt config wins over anything a tool init changed.
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Yazi: force Kitty Graphics Protocol for image previews in Ghostty
export YAZI_IMAGE_PROTOCOL=kitty
