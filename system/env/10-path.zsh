# Tool-specific PATH entries. `typeset -U path` in .zshrc keeps these unique.
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"

# pnpm global bin
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH"
