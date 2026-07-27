alias opencodeconfig="code ~/.config/opencode/opencode.json"

opencode() {
  export GITHUB_PAT="${GITHUB_PAT:-$(security find-generic-password -a "$USER" -s "opencode-github-pat" -w 2>/dev/null)}"
  command opencode "$@"
}
