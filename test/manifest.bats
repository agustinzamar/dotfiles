#!/usr/bin/env bats
# Contract tests for install/manifest.sh — the single Bash manifest parser
# that emits the versioned context JSON consumed by the installer TUI.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=../install/manifest.sh
  . "$DOTFILES_DIR/install/manifest.sh"
}

# ---------------------------------------------------------------------------
# json_escape
# ---------------------------------------------------------------------------

@test "json_escape passes plain strings through" {
  run json_escape 'visual-studio-code'
  [ "$status" -eq 0 ]
  [ "$output" == 'visual-studio-code' ]
}

@test "json_escape escapes double quotes and backslashes" {
  run json_escape 'say "hi"\now'
  [ "$status" -eq 0 ]
  [ "$output" == 'say \"hi\"\\now' ]
}

@test "json_escape escapes tabs and newlines" {
  run json_escape "$(printf 'a\tb\nc')"
  [ "$status" -eq 0 ]
  [ "$output" == 'a\tb\nc' ]
}

@test "json_escape keeps Application Support spaces intact" {
  run json_escape '/Users/x/Library/Application Support/Code/User/settings.json'
  [ "$status" -eq 0 ]
  [ "$output" == '/Users/x/Library/Application Support/Code/User/settings.json' ]
}

# ---------------------------------------------------------------------------
# install_context_json — golden shape over fixtures
# ---------------------------------------------------------------------------

# Fixture topic files: one brew, one cask, one tap, one comment-only file.
fixture_topics() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/core" <<'EOF'
# --- Core ---
brew "fzf"
cask "ghostty"
brew "we"ird\name"
tap "timescam/tap"
EOF
  cat >"$dir/desktop" <<'EOF'
cask "google-chrome"
EOF
  cat >"$dir/code" <<'EOF'
vscode-extension-one
EOF
}

# Fixture link maps with the same shape as install/links.sh: multi-target
# names, an optional group, and targets that need escaping.
fixture_all_links() {
  cat <<-EOF
		ghostty|config/ghostty/config|$HOME/.config/ghostty/config||terminal
		ghostty|config/ghostty/config|$HOME/Library/Application "Sup"port\ghostty.conf||terminal
		vscode|config/vscode/settings.json|$HOME/Library/Application Support/Code/User/settings.json||vscode|code
		hunk|config/hunk/config.toml|$HOME/.config/hunk/config.toml||git|hunk
		opencode|config/opencode/opencode.jsonc|$HOME/.config/opencode/opencode.jsonc||ai
	EOF
}

fixture_optional_links() {
  cat <<-EOF
		agents|ai/AGENTS.md|$HOME/.claude/CLAUDE.md|||ai
		agents|ai/AGENTS.md|$HOME/.config/opencode/AGENTS.md|||ai
	EOF
}

golden_json() {
  cat <<EOF
{
  "version": 1,
  "locked": ["base", "shell"],
  "packages": [
    { "id": "fzf", "topic": "core", "kind": "brew", "area": "shell", "locked": true, "default": false },
    { "id": "ghostty", "topic": "core", "kind": "cask", "area": "terminal", "locked": false, "default": true },
    { "id": "we\"ird\\name", "topic": "core", "kind": "brew", "area": "terminal", "locked": false, "default": false },
    { "id": "timescam/tap", "topic": "core", "kind": "tap", "area": "shell", "locked": false, "default": false },
    { "id": "google-chrome", "topic": "desktop", "kind": "cask", "area": "desktop", "locked": false, "default": false },
    { "id": "code", "topic": "code", "kind": "topic", "area": "vscode", "locked": false, "default": false },
    { "id": "duti-defaults", "topic": "duti", "kind": "topic", "area": "terminal", "locked": false, "default": false }
  ],
  "links": [
    { "name": "ghostty", "optional": false, "component": "terminal", "requirement": "",
      "rows": [
        { "source": "config/ghostty/config", "target": "$HOME/.config/ghostty/config", "mode": "" },
        { "source": "config/ghostty/config", "target": "$HOME/Library/Application \"Sup\"port\\ghostty.conf", "mode": "" }
      ] },
    { "name": "vscode", "optional": false, "component": "vscode", "requirement": "code",
      "rows": [
        { "source": "config/vscode/settings.json", "target": "$HOME/Library/Application Support/Code/User/settings.json", "mode": "" }
      ] },
    { "name": "hunk", "optional": false, "component": "git", "requirement": "hunk",
      "rows": [
        { "source": "config/hunk/config.toml", "target": "$HOME/.config/hunk/config.toml", "mode": "" }
      ] },
    { "name": "opencode", "optional": false, "component": "ai", "requirement": "",
      "rows": [
        { "source": "config/opencode/opencode.jsonc", "target": "$HOME/.config/opencode/opencode.jsonc", "mode": "" }
      ] },
    { "name": "agents", "optional": true, "component": "ai", "requirement": "",
      "rows": [
        { "source": "ai/AGENTS.md", "target": "$HOME/.claude/CLAUDE.md", "mode": "" },
        { "source": "ai/AGENTS.md", "target": "$HOME/.config/opencode/AGENTS.md", "mode": "" }
      ] }
  ]
}
EOF
}

@test "install_context_json emits golden JSON v1 over fixtures" {
  local tmp ctx
  tmp="$(mktemp -d)"
  fixture_topics "$tmp/topics"
  ctx="$tmp/context.json"
  MANIFEST_TOPIC_DIR="$tmp/topics" install_context_json "$ctx"
  [ -s "$ctx" ]
  run bash -c 'diff <(jq -S "$1") <(jq -S "$2")' _ "$ctx" <(golden_json)
  [ "$status" -eq 0 ]
  rm -rf "$tmp"
}

@test "install_context_json fails loudly when the topics dir is unreadable" {
  local ctx
  ctx="$(mktemp)"
  MANIFEST_TOPIC_DIR="$DOTFILES_DIR/install/topics-does-not-exist" run install_context_json "$ctx"
  [ "$status" -ne 0 ]
  [[ -n "$output" ]]
  rm -f "$ctx"
}

# ---------------------------------------------------------------------------
# Real-tree invariants (against the actual topics + links.sh)
# ---------------------------------------------------------------------------

@test "real tree: locked members and former-baseline defaults carry the right flags" {
  local ctx json
  ctx="$(mktemp)"
  install_context_json "$ctx"
  json="$(cat "$ctx")"
  for id in fzf git gh tmux; do
    [ "$(jq -r --arg id "$id" '[.packages[] | select(.id == $id)][0].locked' <<<"$json")" == "true" ]
  done
  for id in lazygit hunk yazi neovim ghostty; do
    [ "$(jq -r --arg id "$id" '[.packages[] | select(.id == $id)][0].default' <<<"$json")" == "true" ]
    [ "$(jq -r --arg id "$id" '[.packages[] | select(.id == $id)][0].locked' <<<"$json")" == "false" ]
  done
  [ "$(jq -r '[.packages[] | select(.id == "t3-code")][0].default' <<<"$json")" == "false" ]
  rm -f "$ctx"
}

@test "real tree: special topics become exactly one delegating row each" {
  local ctx json
  ctx="$(mktemp)"
  install_context_json "$ctx"
  json="$(cat "$ctx")"
  [ "$(jq '[.packages[] | select(.kind == "topic")] | length' <<<"$json")" -eq 2 ]
  [ "$(jq -r '[.packages[] | select(.id == "code")][0].topic' <<<"$json")" == "code" ]
  [ "$(jq -r '[.packages[] | select(.id == "duti-defaults")][0].topic' <<<"$json")" == "duti" ]
  rm -f "$ctx"
}

@test "real tree: multi-target link names collapse into one entry" {
  local ctx json
  ctx="$(mktemp)"
  install_context_json "$ctx"
  json="$(cat "$ctx")"
  [ "$(jq '[.links[] | select(.name == "ghostty")][0].rows | length' <<<"$json")" -eq 2 ]
  [ "$(jq '[.links[] | select(.name == "yazi")][0].rows | length' <<<"$json")" -eq 3 ]
  [ "$(jq '[.links[] | select(.name == "agents")][0].optional' <<<"$json")" == "true" ]
  rm -f "$ctx"
}

# ---------------------------------------------------------------------------
# Drift guard
# ---------------------------------------------------------------------------

@test "drift guard: every links.sh component/requirement token resolves to a populated area" {
  local token area count
  local tokens
  tokens="$({
    all_links
    optional_links
  } | awk -F'|' '($5 != "" || $6 != "") { if ($5 != "") print $5; if ($6 != "") print $6 }' | sort -u)"
  [ -n "$tokens" ]
  local ctx
  ctx="$(mktemp)"
  install_context_json "$ctx"
  while IFS= read -r token; do
    run area_for_package "$token"
    [ "$status" -eq 0 ] || { echo "token '$token' has no area mapping" >&2; fail "area_for_package $token"; }
    area="$output"
    count="$(jq --arg area "$area" '[.packages[] | select(.area == $area)] | length' "$ctx")"
    [ "$count" -ge 1 ] || { echo "token '$token' → area '$area' has no package rows" >&2; fail "orphan token $token"; }
  done <<<"$tokens"
  rm -f "$ctx"
}
