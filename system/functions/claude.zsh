# The GitHub MCP server reads GITHUB_PERSONAL_ACCESS_TOKEN. Give it the token
# for this one process instead of exporting it: an exported secret is inherited
# by every command the shell ever runs, and reading it here means only a real
# `claude` launch pays the keychain call.
#
# `command claude` skips this function, so the wrapper cannot recurse.
claude() {
  if command -v gh >/dev/null 2>&1; then
    GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token 2>/dev/null)" command claude "$@"
  else
    command claude "$@"
  fi
}
