#!/usr/bin/env bats
# Contract tests for install/manifest.sh — the single Bash manifest parser
# that emits the versioned context JSON consumed by the installer TUI.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # Deterministic 'brew list': an empty stub by default so installed pre-check
  # flags are independent of this machine; tests swap MANIFEST_BREW for richer
  # fakes. One printf line (no heredoc) keeps bats' preprocessor happy.
  BREW_STUB="$BATS_TEST_TMPDIR/brew-stub"
  printf '#!/bin/sh\nif [ "$1" = \"list\" ]; then exit 0; fi\nexit 0\n' >"$BREW_STUB"
  chmod +x "$BREW_STUB"
  export MANIFEST_BREW="$BREW_STUB"
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
brew "anomalyco/tap/opencode"
tap "timescam/tap"
EOF
  cat >"$dir/desktop" <<'EOF'
cask "google-chrome"
cask "discord"
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
    { "id": "fzf", "label": "fzf", "topic": "core", "category": "core", "kind": "brew", "area": "shell", "locked": true, "default": false, "installed": true },
    { "id": "ghostty", "label": "ghostty", "topic": "core", "category": "core", "kind": "cask", "area": "terminal", "locked": false, "default": true, "installed": false },
    { "id": "we\"ird\\name", "label": "we\"ird\\name", "topic": "core", "category": "core", "kind": "brew", "area": "terminal", "locked": false, "default": false, "installed": false },
    { "id": "anomalyco/tap/opencode", "label": "opencode", "topic": "core", "category": "ai", "kind": "brew", "area": "ai", "locked": false, "default": false, "installed": false },
    { "id": "timescam/tap", "label": "timescam/tap", "topic": "core", "category": "core", "kind": "tap", "area": "shell", "locked": false, "default": false, "installed": false },
    { "id": "google-chrome", "label": "google-chrome", "topic": "desktop", "category": "Browsers", "kind": "cask", "area": "desktop", "locked": false, "default": false, "installed": false },
    { "id": "discord", "label": "discord", "topic": "desktop", "category": "Communication", "kind": "cask", "area": "desktop", "locked": false, "default": false, "installed": false },
    { "id": "code", "label": "code", "topic": "code", "category": "code", "kind": "topic", "area": "vscode", "locked": false, "default": false, "installed": false },
    { "id": "duti-defaults", "label": "duti-defaults", "topic": "duti", "category": "duti", "kind": "topic", "area": "terminal", "locked": false, "default": false, "installed": false }
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
  for id in fzf git gh; do
    [ "$(jq -r --arg id "$id" '[.packages[] | select(.id == $id)][0].locked' <<<"$json")" == "true" ]
  done
  # tmux is a real preference (some people don't want a multiplexer forced on)
  # -- pre-checked like the other former-baseline tools, but toggleable.
  for id in lazygit hunk yazi neovim ghostty tmux; do
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
  # code + duti-defaults (topic rows) + the new System adoptees dock/macos.
  [ "$(jq '[.packages[] | select(.kind == "topic")] | length' <<<"$json")" -eq 4 ]
  [ "$(jq -r '[.packages[] | select(.id == "code")][0].topic' <<<"$json")" == "code" ]
  [ "$(jq -r '[.packages[] | select(.id == "duti-defaults")][0].topic' <<<"$json")" == "duti" ]
  [ "$(jq -r '[.packages[] | select(.id == "dock")][0].topic' <<<"$json")" == "system" ]
  [ "$(jq -r '[.packages[] | select(.id == "macos")][0].topic' <<<"$json")" == "system" ]
  # Human labels for the delegating rows (they now render in the main list).
  [ "$(jq -r '[.packages[] | select(.id == "code")][0].label' <<<"$json")" == "VS Code extensions" ]
  [ "$(jq -r '[.packages[] | select(.id == "dock")][0].label' <<<"$json")" == "Dock defaults" ]
  [ "$(jq -r '[.packages[] | select(.id == "macos")][0].label' <<<"$json")" == "macOS defaults" ]
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

@test "real tree: tap labels collapse, categories group, installed detection works" {
  local ctx json
  ctx="$(mktemp)"
  # Real brew list: the installed-pre-check assertion must see actual state
  # (the setup stub reports nothing installed by design for the other tests).
  MANIFEST_BREW=/opt/homebrew/bin/brew install_context_json "$ctx"
  json="$(cat "$ctx")"
  [ "$(jq -r '[.packages[] | select(.id == "anomalyco/tap/opencode")][0].label' <<<"$json")" == "opencode" ]
  [ "$(jq -r '[.packages[] | select(.id == "stupside/tap/castor")][0].label' <<<"$json")" == "castor" ]
  [ "$(jq -r '[.packages[] | select(.id == "claude-code@latest")][0].category' <<<"$json")" == "AI" ]
  [ "$(jq -r '[.packages[] | select(.id == "codex")][0].category' <<<"$json")" == "AI" ]
  [ "$(jq -r '[.packages[] | select(.id == "discord")][0].category' <<<"$json")" == "Communication" ]
  [ "$(jq -r '[.packages[] | select(.id == "google-chrome")][0].category' <<<"$json")" == "Browsers" ]
  [ "$(jq -r '[.packages[] | select(.id == "yabai")][0].category' <<<"$json")" == "Desktop" ]
  [ "$(jq -r '[.packages[] | select(.id == "linearmouse")][0].category' <<<"$json")" == "Tweakers" ]
  [ "$(jq -r '[.packages[] | select(.id == "raycast")][0].category' <<<"$json")" == "Utilities" ]
  [ "$(jq -r '[.packages[] | select(.id == "7zip")][0].category' <<<"$json")" == "Archives" ]
  [ "$(jq -r '[.packages[] | select(.id == "btop")][0].category' <<<"$json")" == "Monitoring" ]
  [ "$(jq -r '[.packages[] | select(.id == "eza")][0].category' <<<"$json")" == "Filesystem" ]
  [ "$(jq -r '[.packages[] | select(.id == "ffmpeg")][0].category' <<<"$json")" == "Media tools" ]
  [ "$(jq -r '[.packages[] | select(.id == "spotify")][0].category' <<<"$json")" == "Entertainment" ]
  [ "$(jq -r '[.packages[] | select(.id == "mysql")][0].category' <<<"$json")" == "Databases" ]
  # Taps keep their full name as the label.
  [ "$(jq -r '[.packages[] | select(.id == "timescam/tap")][0].label' <<<"$json")" == "timescam/tap" ]
  # Installed detection via brew list: t3-code is present on this machine.
  [ "$(jq -r '[.packages[] | select(.id == "t3-code")][0].installed' <<<"$json")" == "true" ]
  rm -f "$ctx"
}

@test "real tree: git/services/linters/prompt categories exist; no package falls back to a raw lowercase topic name" {
  local ctx json
  ctx="$(mktemp)"
  MANIFEST_BREW=/opt/homebrew/bin/brew install_context_json "$ctx"
  json="$(cat "$ctx")"
  [ "$(jq -r '[.packages[] | select(.id == "lazygit")][0].category' <<<"$json")" == "Git" ]
  [ "$(jq -r '[.packages[] | select(.id == "hunk")][0].category' <<<"$json")" == "Git" ]
  [ "$(jq -r '[.packages[] | select(.id == "herd")][0].category' <<<"$json")" == "Services" ]
  [ "$(jq -r '[.packages[] | select(.id == "orbstack")][0].category' <<<"$json")" == "Services" ]
  # System adoptees + code land in the main selector now.
  [ "$(jq -r '[.packages[] | select(.id == "duti-defaults")][0].category' <<<"$json")" == "System" ]
  [ "$(jq -r '[.packages[] | select(.id == "dock")][0].category' <<<"$json")" == "System" ]
  [ "$(jq -r '[.packages[] | select(.id == "macos")][0].category' <<<"$json")" == "System" ]
  [ "$(jq -r '[.packages[] | select(.id == "code")][0].category' <<<"$json")" == "Editors" ]
  [ "$(jq -r '[.packages[] | select(.id == "shellcheck")][0].category' <<<"$json")" == "Linters" ]
  [ "$(jq -r '[.packages[] | select(.id == "shfmt")][0].category' <<<"$json")" == "Linters" ]
  [ "$(jq -r '[.packages[] | select(.id == "actionlint")][0].category' <<<"$json")" == "Linters" ]
  [ "$(jq -r '[.packages[] | select(.id == "swiftformat")][0].category' <<<"$json")" == "Linters" ]
  [ "$(jq -r '[.packages[] | select(.id == "oh-my-posh")][0].category' <<<"$json")" == "Prompt" ]
  [ "$(jq -r '[.packages[] | select(.id == "poppler")][0].category' <<<"$json")" == "Filesystem" ]
  [ "$(jq -r '[.packages[] | select(.id == "dockutil")][0].category' <<<"$json")" == "Utilities" ]
  # No toggleable package (kind brew/cask/tap) may ever fall back to a raw
  # lowercase topic name (core/desktop/dev/media) — every real package gets
  # an explicit category, so the selector never mixes cased headers with
  # raw fallback ones.
      local orphans
      orphans="$(jq -r '[.packages[] | select(.kind != "topic") | select(.category == .topic and (.category | test("^[a-z]+$")))] | map(.id) | join(",")' <<<"$json")"
      if [ -n "$orphans" ]; then
        echo "uncategorized packages fell back to a raw topic name: $orphans" >&2
      fi
      [ -z "$orphans" ]
      rm -f "$ctx"
}

@test "real tree: unar is declared once, not duplicated across topics" {
  local ctx json
  ctx="$(mktemp)"
  MANIFEST_BREW=/opt/homebrew/bin/brew install_context_json "$ctx"
  json="$(cat "$ctx")"
  [ "$(jq -r '[.packages[] | select(.id == "unar")] | length' <<<"$json")" == "1" ]
  rm -f "$ctx"
}
