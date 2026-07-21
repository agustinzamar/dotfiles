alias cd='z'
alias cat='bat --paging=never'
catcopy() {
  bat -p --paging=never "$1" | pbcopy
}
alias ls='eza -la --icons --group-directories-first'
alias ll='eza -la --icons --git'
alias lt='eza --tree --icons'
