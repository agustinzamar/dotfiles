# Tool-specific PATH entries. `typeset -U path` in .zshrc keeps these unique.
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"

# Ghostty CLI (use `ghostty +list-fonts`, `+show-config`, etc.)
export PATH="/Applications/Ghostty.app/Contents/MacOS:$PATH"

# pnpm global bin
export PNPM_HOME="$HOME/Library/pnpm"
export PATH="$PNPM_HOME/bin:$PNPM_HOME:$PATH"
