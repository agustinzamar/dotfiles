#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  export REPO_ROOT
  TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gentle-ai-agents.XXXXXX")
  export HOME="$TEST_ROOT/home"
  mkdir -p "$HOME"
  export PATH="$REPO_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

# ---------------------------------------------------------------------------
# Claude settings fragment merge tests
# ---------------------------------------------------------------------------

@test "dot agents sync merges the tracked statusLine into Claude settings" {
  mkdir -p "$HOME/.claude"
  cat >"$HOME/.claude/settings.json" <<'JSON'
{
  "model": "opus",
  "hooks": { "Stop": [] },
  "statusLine": { "type": "command", "command": "bash /Users/someone/.claude/statusline-command.sh" }
}
JSON

  run dot agents sync

  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" = 'bash ~/.claude/statusline-command.sh' ]
  [ "$(jq -r '.statusLine.type' "$HOME/.claude/settings.json")" = 'command' ]
  [ "$(jq -r '.model' "$HOME/.claude/settings.json")" = 'opus' ]
  [ "$(jq -c '.hooks' "$HOME/.claude/settings.json")" = '{"Stop":[]}' ]
}

@test "dot agents sync creates Claude settings with the statusLine when missing" {
  run dot agents sync

  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")" = 'bash ~/.claude/statusline-command.sh' ]
}

@test "Claude settings merge is idempotent" {
  run dot agents sync
  first=$(cat "$HOME/.claude/settings.json")

  run dot agents sync

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = "$first" ]
}

@test "Claude settings merge leaves invalid JSON untouched and fails" {
  mkdir -p "$HOME/.claude"
  printf '{ not json' >"$HOME/.claude/settings.json"

  run dot agents sync

  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = '{ not json' ]
}

@test "dot agents sync --dry-run does not modify Claude settings" {
  mkdir -p "$HOME/.claude"
  printf '{"model":"opus"}\n' >"$HOME/.claude/settings.json"

  run dot agents sync --dry-run

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/settings.json")" = '{"model":"opus"}' ]
}
