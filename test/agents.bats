#!/usr/bin/env bats

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  export REPO_ROOT
  TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gentle-ai-agents.XXXXXX")
  export HOME="$TEST_ROOT/home"
  mkdir -p "$HOME"
  NATIVE="$TEST_ROOT/native-gentle-ai"
  NATIVE_LOG="$TEST_ROOT/native.log"
  NATIVE_PATH_LOG="$TEST_ROOT/native-path.log"
  export GENTLE_AI_NATIVE_BIN="$NATIVE"
  export PATH="$REPO_ROOT/bin:$PATH"
  cat >"$NATIVE" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NATIVE_LOG"
printf '%s\n' "$PATH" >>"$NATIVE_PATH_LOG"
exit "${NATIVE_STATUS:-0}"
EOF
  chmod +x "$NATIVE"
  export NATIVE_LOG NATIVE_PATH_LOG
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

# Put the fake native in a directory of its own — never the wrapper dir — so PATH
# lookup finds a real candidate. NATIVE_BIN_DIR names that directory.
seed_native_on_path() {
  NATIVE_BIN_DIR="$TEST_ROOT/native-bin"
  mkdir -p "$NATIVE_BIN_DIR"
  cp "$NATIVE" "$NATIVE_BIN_DIR/gentle-ai"
  chmod +x "$NATIVE_BIN_DIR/gentle-ai"
  unset GENTLE_AI_NATIVE_BIN
}

@test "sync refreshes all targets from the repository source and preserves managed blocks" {
  seed_targets

  run gentle-ai sync

  [ "$status" -eq 0 ]
  for target in \
    "$HOME/.agents/AGENTS.md" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.claude/CLAUDE.md"; do
    # Source dot sections are present in each target.
    grep -F 'git-commits-and-pull-requests' "$target"
    grep -F 'subagent-model-selection' "$target"
    grep -F 'communication-style' "$target"
    # Non-dot content (gentle-ai blocks, arbitrary text) is preserved.
    grep -F 'managed Gentle AI instructions' "$target"
    grep -F 'stale personal rules' "$target"
  done
}

@test "sync creates missing targets from the repository source" {
  run gentle-ai sync

  [ "$status" -eq 0 ]
  for target in \
    "$HOME/.agents/AGENTS.md" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.claude/CLAUDE.md"; do
    # Target should contain source dot sections.
    grep -F 'git-commits-and-pull-requests' "$target"
    grep -F 'subagent-model-selection' "$target"
    grep -F 'communication-style' "$target"
  done
}

@test "non-sync invocations delegate unchanged to the native binary" {
  run gentle-ai status --verbose

  [ "$status" -eq 0 ]
  [ "$(cat "$NATIVE_LOG")" = 'status --verbose' ]
  [ ! -e "$HOME/.agents/AGENTS.md" ]
}

@test "PATH lookup skips the repository wrapper" {
  seed_native_on_path
  export PATH="$REPO_ROOT/bin:$NATIVE_BIN_DIR:/opt/homebrew/bin:/usr/bin:/bin"

  run gentle-ai status

  [ "$status" -eq 0 ]
  [ "$(cat "$NATIVE_LOG")" = 'status' ]
}

@test "delegated invocation puts the native directory first on the child PATH" {
  seed_native_on_path
  # The wrapper dir comes first and the native dir does not, so without the fix
  # the child inherits a PATH that resolves `gentle-ai` back to the wrapper.
  export PATH="$REPO_ROOT/bin:/usr/bin:$NATIVE_BIN_DIR:/opt/homebrew/bin:/bin"

  run gentle-ai status

  [ "$status" -eq 0 ]
  child_path=$(cat "$NATIVE_PATH_LOG")
  # Compare by identity: mktemp paths differ from their physical form on macOS.
  [ "${child_path%%:*}" -ef "$NATIVE_BIN_DIR" ]
}

@test "sync also puts the native directory first on the child PATH" {
  seed_native_on_path
  export PATH="$REPO_ROOT/bin:/usr/bin:$NATIVE_BIN_DIR:/opt/homebrew/bin:/bin"

  run gentle-ai sync

  [ "$status" -eq 0 ]
  child_path=$(cat "$NATIVE_PATH_LOG")
  [ "${child_path%%:*}" -ef "$NATIVE_BIN_DIR" ]
}

@test "a wrapper copy on PATH is skipped instead of bouncing between copies" {
  seed_native_on_path
  # A second checkout of this repo puts another copy of the wrapper on PATH, and
  # that copy is the entry point here. Without the guard the two wrappers exec
  # each other forever, so a watchdog bounds the wait: this must fail, not hang.
  mkdir -p "$TEST_ROOT/other-clone/bin"
  cp "$REPO_ROOT/bin/gentle-ai" "$TEST_ROOT/other-clone/bin/gentle-ai"
  chmod +x "$TEST_ROOT/other-clone/bin/gentle-ai"
  export PATH="$TEST_ROOT/other-clone/bin:$REPO_ROOT/bin:$NATIVE_BIN_DIR:/usr/bin:/bin"

  gentle-ai status &
  target=$!
  (sleep 5 && kill -9 "$target" 2>/dev/null) &
  watchdog=$!
  wait "$target"
  status=$?
  kill "$watchdog" 2>/dev/null

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

# ---------------------------------------------------------------------------
# Section-merge core tests (Work Unit 2)
# ---------------------------------------------------------------------------

# Helper: create a source AGENTS.md with named dot sections.
_create_source() {
  local dir="$1"
  mkdir -p "$dir/ai"
  cat >"$dir/ai/AGENTS.md" <<'SOURCE'
<!-- dot:section alpha -->

## Alpha Section

Alpha content here.

<!-- /dot:section -->

<!-- dot:section beta -->

## Beta Section

Beta content here.

<!-- /dot:section -->
SOURCE
}

@test "merge replaces an existing dot section by name" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
<!-- dot:section alpha -->

## Alpha Section

Old alpha content that should be replaced.

<!-- /dot:section -->

Some local text.
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$REPO_ROOT" "$home"

  [ "$status" -eq 0 ]
  grep -q 'Alpha content here' "$home/.agents/AGENTS.md"
  grep -q 'Old alpha content' "$home/.agents/AGENTS.md" && return 1
  grep -q 'Some local text' "$home/.agents/AGENTS.md"
}

@test "merge appends a missing dot section" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
<!-- dot:section alpha -->

## Alpha Section

Alpha content here.

<!-- /dot:section -->
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"

  [ "$status" -eq 0 ]
  grep -q 'Alpha content here' "$home/.agents/AGENTS.md"
  grep -q 'Beta content here' "$home/.agents/AGENTS.md"
}

@test "merge preserves non-dot content (gentle-ai blocks, arbitrary text)" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
My personal instructions.

<!-- gentle-ai:managed -->
Managed content here.
<!-- /gentle-ai:managed -->

<!-- dot:section alpha -->

## Alpha Section

Alpha content here.

<!-- /dot:section -->

More personal text with `code` and $VARIABLE.
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"

  [ "$status" -eq 0 ]
  grep -q 'My personal instructions' "$home/.agents/AGENTS.md"
  grep -q 'Managed content here' "$home/.agents/AGENTS.md"
  grep -q 'More personal text' "$home/.agents/AGENTS.md"
  grep -q 'Alpha content here' "$home/.agents/AGENTS.md"
  grep -q 'Beta content here' "$home/.agents/AGENTS.md"
}

@test "merge preserves target-only dot sections" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
<!-- dot:section gamma -->

## Gamma Section

Gamma is local-only, not in source.

<!-- /dot:section -->

<!-- dot:section alpha -->

## Alpha Section

Alpha content here.

<!-- /dot:section -->
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"

  [ "$status" -eq 0 ]
  grep -q 'Gamma is local-only' "$home/.agents/AGENTS.md"
  grep -q 'Alpha content here' "$home/.agents/AGENTS.md"
  grep -q 'Beta content here' "$home/.agents/AGENTS.md"
}

@test "merge handles a target with no dot markers (Codex-like)" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.codex"
  cat >"$home/.codex/AGENTS.md" <<'TARGET'
# Codex Instructions

These are local Codex instructions with no dot markers.

Some more content.
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.codex/AGENTS.md"' \
    _ "$repo" "$home"

  [ "$status" -eq 0 ]
  grep -q 'Codex Instructions' "$home/.codex/AGENTS.md"
  grep -q 'local Codex instructions' "$home/.codex/AGENTS.md"
  grep -q 'Alpha content here' "$home/.codex/AGENTS.md"
  grep -q 'Beta content here' "$home/.codex/AGENTS.md"
}

@test "merge creates missing target from source" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"

  [ "$status" -eq 0 ]
  [ -f "$home/.agents/AGENTS.md" ]
  grep -q 'Alpha content here' "$home/.agents/AGENTS.md"
  grep -q 'Beta content here' "$home/.agents/AGENTS.md"
}

@test "merge is idempotent (second run produces identical bytes)" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
<!-- dot:section alpha -->

## Alpha Section

Alpha content here.

<!-- /dot:section -->

Local text.
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    bash -c 'SOURCE="$SOURCE" . "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"
  first_status=$?
  [ "$first_status" -eq 0 ]
  first_run=$(cat "$home/.agents/AGENTS.md")

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    bash -c 'SOURCE="$SOURCE" . "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"
  second_status=$?
  [ "$second_status" -eq 0 ]
  second_run=$(cat "$home/.agents/AGENTS.md")

  [ "$first_run" = "$second_run" ]
}

@test "idempotence verified by cmp (no byte difference on second run)" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
<!-- dot:section alpha -->

## Alpha Section

Alpha content here.

<!-- /dot:section -->

Local text.
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    bash -c 'SOURCE="$SOURCE" . "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"
  first_status=$?
  [ "$first_status" -eq 0 ]
  cp "$home/.agents/AGENTS.md" "$home/.agents/AGENTS.md.first"

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    bash -c 'SOURCE="$SOURCE" . "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"
  second_status=$?
  [ "$second_status" -eq 0 ]

  cmp -s "$home/.agents/AGENTS.md.first" "$home/.agents/AGENTS.md"
}

@test "merge preserves shell-like and documentation text in non-dot content" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
```bash
echo "hello world"
if [[ -f "$HOME/.zshrc" ]]; then source "$HOME/.zshrc"; fi
```

<!-- gentle-ai:context7 -->
Context7 block.
<!-- /gentle-ai:context7 -->

| Column A | Column B |
|----------|----------|
| `code`   | $VAR     |

<!-- dot:section alpha -->

## Alpha Section

Alpha content here.

<!-- /dot:section -->
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"

  [ "$status" -eq 0 ]
  grep -q 'echo "hello world"' "$home/.agents/AGENTS.md"
  grep -q 'Context7 block' "$home/.agents/AGENTS.md"
  grep -q 'Column A' "$home/.agents/AGENTS.md"
  grep -q 'Alpha content here' "$home/.agents/AGENTS.md"
  grep -q 'Beta content here' "$home/.agents/AGENTS.md"
}

@test "merge rejects duplicate source section names" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  mkdir -p "$repo/ai"
  cat >"$repo/ai/AGENTS.md" <<'SOURCE'
<!-- dot:section alpha -->

## Alpha First

<!-- /dot:section -->

<!-- dot:section alpha -->

## Alpha Second

<!-- /dot:section -->
SOURCE

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
Existing content.
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"

  [ "$status" -ne 0 ]
}

@test "merge preserves malformed (unclosed) target sections with a warning" {
  local home repo
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  _create_source "$repo"

  mkdir -p "$home/.agents"
  cat >"$home/.agents/AGENTS.md" <<'TARGET'
Before text.

<!-- dot:section orphan -->

## Orphan Section

This section has no closing marker.

Some trailing text after the unclosed block.
TARGET

  SOURCE="$repo/ai/AGENTS.md" HOME="$home" DRY_RUN=false \
    run bash -c '. "$REPO_ROOT/install/agents.sh"; merge_target "$HOME/.agents/AGENTS.md"' \
    _ "$repo" "$home"

  [ "$status" -eq 0 ]
  # A warning about the malformed section is emitted.
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"orphan"* ]]
  [[ "$output" == *"malformed"* ]]
  # The malformed block is preserved byte-for-byte (not silently rewritten).
  grep -q '<!-- dot:section orphan -->' "$home/.agents/AGENTS.md"
  grep -q 'This section has no closing marker' "$home/.agents/AGENTS.md"
  grep -q 'Some trailing text after the unclosed block' "$home/.agents/AGENTS.md"
  # Source sections are still appended.
  grep -q 'Alpha content here' "$home/.agents/AGENTS.md"
  grep -q 'Beta content here' "$home/.agents/AGENTS.md"
  # Non-dot content before the malformed block is preserved.
  grep -q 'Before text' "$home/.agents/AGENTS.md"
}

# ---------------------------------------------------------------------------
# dot agents sync tests (Work Unit 3)
# ---------------------------------------------------------------------------

@test "dot agents sync refreshes all managed targets" {
  seed_targets

  run dot agents sync

  [ "$status" -eq 0 ]
  for target in \
    "$HOME/.agents/AGENTS.md" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.claude/CLAUDE.md"; do
    grep -F 'git-commits-and-pull-requests' "$target"
    grep -F 'subagent-model-selection' "$target"
    grep -F 'communication-style' "$target"
    grep -F 'managed Gentle AI instructions' "$target"
  done
}

@test "dot agents sync creates missing targets" {
  run dot agents sync

  [ "$status" -eq 0 ]
  for target in \
    "$HOME/.agents/AGENTS.md" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.claude/CLAUDE.md"; do
    grep -F 'git-commits-and-pull-requests' "$target"
    grep -F 'subagent-model-selection' "$target"
  done
}

@test "dot agents sync includes .codex/AGENTS.md" {
  run dot agents sync

  [ "$status" -eq 0 ]
  [ -f "$HOME/.codex/AGENTS.md" ]
  grep -F 'git-commits-and-pull-requests' "$HOME/.codex/AGENTS.md"
}

@test "dot agents sync preserves target-only content (Codex preservation)" {
  mkdir -p "$HOME/.codex"
  cat >"$HOME/.codex/AGENTS.md" <<'TARGET'
# Codex Instructions

Custom local rules.

<!-- dot:section gamma -->

## Gamma Section

Gamma is local-only.

<!-- /dot:section -->
TARGET

  run dot agents sync

  [ "$status" -eq 0 ]
  grep -F 'Codex Instructions' "$HOME/.codex/AGENTS.md"
  grep -F 'Custom local rules' "$HOME/.codex/AGENTS.md"
  grep -F 'Gamma is local-only' "$HOME/.codex/AGENTS.md"
  grep -F 'git-commits-and-pull-requests' "$HOME/.codex/AGENTS.md"
}

@test "dot agents sync --dry-run does not modify targets" {
  seed_targets
  before=$(cat "$HOME/.agents/AGENTS.md")

  run dot agents sync --dry-run

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.agents/AGENTS.md")" = "$before" ]
}

# ---------------------------------------------------------------------------
# PI close-marker normalization tests
# ---------------------------------------------------------------------------

@test "PI fixture sync normalizes mismatched close markers" {
  # Create a PI file with mismatched close markers (close says -tool/-guidance
  # but should be generic pi-codegraph).
  mkdir -p "$HOME/.pi/agent/agents"
  cat >"$HOME/.pi/agent/agents/sdd-apply.md" <<'EOF'
# SDD Apply

Before content.

<!-- gentle-ai:pi-codegraph-tool -->
Tool block content.
<!-- /gentle-ai:pi-codegraph-tool -->

Middle content.

<!-- gentle-ai:pi-codegraph-guidance -->
Guidance block content.
<!-- /gentle-ai:pi-codegraph-guidance -->

After content.
EOF

  run dot agents sync

  [ "$status" -eq 0 ]
  # Close markers should be normalized to generic pi-codegraph.
  grep -q '<!-- /gentle-ai:pi-codegraph -->' "$HOME/.pi/agent/agents/sdd-apply.md"
  ! grep -q '<!-- /gentle-ai:pi-codegraph-tool -->' "$HOME/.pi/agent/agents/sdd-apply.md"
  ! grep -q '<!-- /gentle-ai:pi-codegraph-guidance -->' "$HOME/.pi/agent/agents/sdd-apply.md"
  # Content between markers is preserved.
  grep -q 'Tool block content' "$HOME/.pi/agent/agents/sdd-apply.md"
  grep -q 'Guidance block content' "$HOME/.pi/agent/agents/sdd-apply.md"
  grep -q 'Before content' "$HOME/.pi/agent/agents/sdd-apply.md"
  grep -q 'After content' "$HOME/.pi/agent/agents/sdd-apply.md"
}

@test "PI normalization is idempotent (second run is a no-op)" {
  mkdir -p "$HOME/.pi/agent/agents"
  cat >"$HOME/.pi/agent/agents/sdd-apply.md" <<'EOF'
# SDD Apply

<!-- gentle-ai:pi-codegraph-tool -->
Tool content.
<!-- /gentle-ai:pi-codegraph-tool -->

<!-- gentle-ai:pi-codegraph-guidance -->
Guidance content.
<!-- /gentle-ai:pi-codegraph-guidance -->
EOF

  run dot agents sync
  [ "$status" -eq 0 ]
  cp "$HOME/.pi/agent/agents/sdd-apply.md" "$HOME/.pi/agent/agents/sdd-apply.md.first"

  run dot agents sync
  [ "$status" -eq 0 ]

  cmp -s "$HOME/.pi/agent/agents/sdd-apply.md.first" "$HOME/.pi/agent/agents/sdd-apply.md"
}

@test "PI normalization skips files outside the 23-file list" {
  mkdir -p "$HOME/.pi/agent/agents"
  cat >"$HOME/.pi/agent/agents/unknown-agent.md" <<'EOF'
<!-- gentle-ai:pi-codegraph-tool -->
Content.
<!-- /gentle-ai:pi-codegraph-tool -->
EOF

  run dot agents sync
  [ "$status" -eq 0 ]
  # Unlisted file should be unchanged.
  grep -q '<!-- /gentle-ai:pi-codegraph-tool -->' "$HOME/.pi/agent/agents/unknown-agent.md"
}

@test "PI normalization does not touch APPEND_SYSTEM.md" {
  mkdir -p "$HOME/.pi/agent/agents"
  cat >"$HOME/.pi/agent/agents/APPEND_SYSTEM.md" <<'EOF'
<!-- gentle-ai:pi-codegraph-tool -->
Content.
<!-- /gentle-ai:pi-codegraph-tool -->
EOF

  run dot agents sync
  [ "$status" -eq 0 ]
  # APPEND_SYSTEM.md should be untouched (not in the 23-file list).
  grep -q '<!-- /gentle-ai:pi-codegraph-tool -->' "$HOME/.pi/agent/agents/APPEND_SYSTEM.md"
}
