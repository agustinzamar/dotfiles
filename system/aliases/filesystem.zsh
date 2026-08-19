alias cd='z'
alias cat='bat --paging=never'
alias ls='eza -la --icons --group-directories-first'
alias ll='eza -la --icons --git'
alias tree='eza --tree --icons'

# zmv: batch rename/copy/link without the shell expanding glob patterns
alias zmv='noglob zmv'
alias zcp='noglob zmv -C'
alias zln='noglob zmv -L'

