# The GitHub MCP server (Claude Code plugin) authenticates with this variable.
# Read it from the gh CLI keychain so the token is never stored on disk.
if command -v gh &>/dev/null; then
  export GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null)"
fi
