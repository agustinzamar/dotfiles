alias zshconfig="code ~/.zshrc"
alias ohmyzsh="code ~/.oh-my-zsh"
alias opencodeconfig="code ~/.config/opencode/opencode.json"
alias claudeconfig="code ~/.claude/settings.json"

# Keep the PAT in the keychain rather than rendered into opencode.json on disk.
opencode() {
  export GITHUB_PAT="${GITHUB_PAT:-$(security find-generic-password -a "$USER" -s "opencode-github-pat" -w 2>/dev/null)}"
  command opencode "$@"
}
