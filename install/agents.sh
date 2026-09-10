#!/usr/bin/env bash
# Refresh agent instruction files while preserving Gentle AI managed blocks.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 1
REPO_ROOT=$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd -P) || exit 1
SOURCE="$REPO_ROOT/ai/AGENTS.md"

[ -f "$SOURCE" ] || {
  echo "gentle-ai: missing source: $SOURCE" >&2
  exit 1
}

merge_target() {
  local target="$1"
  local temporary

  mkdir -p "$(dirname "$target")" || return 1
  temporary=$(mktemp "${target}.tmp.XXXXXX") || return 1

  if [ -f "$target" ] && grep -F -q '<!-- gentle-ai:' "$target"; then
    awk '
      FNR == NR { print; next }
      index($0, "<!-- gentle-ai:") { found = 1 }
      found { print }
    ' "$SOURCE" "$target" >"$temporary" || return 1
  else
    cp "$SOURCE" "$temporary" || return 1
  fi

  mv "$temporary" "$target"
}

merge_target "$HOME/.agents/AGENTS.md" || exit 1
merge_target "$HOME/.config/opencode/AGENTS.md" || exit 1
merge_target "$HOME/.claude/CLAUDE.md" || exit 1
