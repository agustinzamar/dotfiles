#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gentle-ai-agents.XXXXXX")
  export HOME="$TEST_ROOT/home"
  mkdir -p "$HOME"
  NATIVE="$TEST_ROOT/native-gentle-ai"
  NATIVE_LOG="$TEST_ROOT/native.log"
  export GENTLE_AI_NATIVE_BIN="$NATIVE"
  export PATH="$REPO_ROOT/bin:$PATH"
  cat >"$NATIVE" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NATIVE_LOG"
exit "${NATIVE_STATUS:-0}"
EOF
  chmod +x "$NATIVE"
  export NATIVE_LOG
}

teardown() {
  rm -rf "$TEST_ROOT"
}

seed_targets() {
  local target
  for target in \
    "$HOME/.agents/AGENTS.md" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.claude/CLAUDE.md"; do
    mkdir -p "$(dirname "$target")"
    cat >"$target" <<'EOF'
stale personal rules that must be removed
<!-- gentle-ai: managed -->
managed Gentle AI instructions
<!-- /gentle-ai: managed -->
EOF
  done
}

@test "sync refreshes all targets from the repository source and preserves managed blocks" {
  seed_targets

  run gentle-ai sync

  [ "$status" -eq 0 ]
  for target in \
    "$HOME/.agents/AGENTS.md" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.claude/CLAUDE.md"; do
    grep -F 'Use Context7 MCP' "$target"
    grep -F '<!-- gentle-ai: managed -->' "$target"
    grep -F 'managed Gentle AI instructions' "$target"
    ! grep -F 'stale personal rules' "$target"
  done
}

@test "sync creates missing targets with the exact repository source" {
  run gentle-ai sync

  [ "$status" -eq 0 ]
  for target in \
    "$HOME/.agents/AGENTS.md" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.claude/CLAUDE.md"; do
    cmp -s "$REPO_ROOT/ai/AGENTS.md" "$target"
  done
}

@test "non-sync invocations delegate unchanged to the native binary" {
  run gentle-ai status --verbose

  [ "$status" -eq 0 ]
  [ "$(cat "$NATIVE_LOG")" = 'status --verbose' ]
  [ ! -e "$HOME/.agents/AGENTS.md" ]
}

@test "PATH lookup skips the repository wrapper" {
  mkdir -p "$TEST_ROOT/native-bin"
  cp "$NATIVE" "$TEST_ROOT/native-bin/gentle-ai"
  chmod +x "$TEST_ROOT/native-bin/gentle-ai"
  unset GENTLE_AI_NATIVE_BIN
  export PATH="$REPO_ROOT/bin:$TEST_ROOT/native-bin:/opt/homebrew/bin:/usr/bin:/bin"

  run gentle-ai status

  [ "$status" -eq 0 ]
  [ "$(cat "$NATIVE_LOG")" = 'status' ]
}

@test "sync preserves native failure and does not merge" {
  seed_targets
  before=$(cat "$HOME/.agents/AGENTS.md")
  export NATIVE_STATUS=23

  run gentle-ai sync

  [ "$status" -eq 23 ]
  [ "$(cat "$HOME/.agents/AGENTS.md")" = "$before" ]
}

@test "sync dry-run delegates but does not merge" {
  seed_targets
  before=$(cat "$HOME/.agents/AGENTS.md")

  run gentle-ai sync --dry-run

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.agents/AGENTS.md")" = "$before" ]
  [ "$(cat "$NATIVE_LOG")" = 'sync --dry-run' ]
}
