# pay-respects: Rust rewrite of thefuck. Corrects the previous command.
if command -v pay-respects &>/dev/null; then
  eval "$(pay-respects zsh --alias fk)"
fi