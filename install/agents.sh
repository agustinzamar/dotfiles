#!/usr/bin/env bash
# dot agents sync: merge the tracked Claude Code settings fragment into the live
# ~/.claude/settings.json.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 1
REPO_ROOT=$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd -P) || exit 1
CLAUDE_SETTINGS_SOURCE="${CLAUDE_SETTINGS_SOURCE:-$REPO_ROOT/config/claude/settings.json}"

# Merge the tracked Claude settings fragment into the live settings.json.
# Claude Code and other tools (plugins, gentle-ai hooks) write that file, so it
# is never symlinked: only the keys in the fragment are owned by dot, and every
# other key is preserved. Invalid live JSON is left untouched and reported.
merge_claude_settings() {
  local target="$HOME/.claude/settings.json" temporary

  if "${DRY_RUN:-false}"; then
    echo "would merge: $target"
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "skipping $target: jq is not installed" >&2
    return 0
  fi

  mkdir -p "$(dirname "$target")" || return 1
  [[ -f "$target" ]] || printf '{}\n' >"$target"

  temporary=$(mktemp "${target}.tmp.XXXXXX") || return 1
  if ! jq -s '.[0] * .[1]' "$target" "$CLAUDE_SETTINGS_SOURCE" >"$temporary" 2>/dev/null; then
    echo "ERROR: could not merge $target (invalid JSON?); left unchanged" >&2
    rm -f "$temporary"
    return 1
  fi

  if cmp -s "$temporary" "$target"; then
    rm -f "$temporary"
  else
    mv "$temporary" "$target"
  fi
}

# When run directly (not sourced), merge the settings.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  merge_claude_settings
fi
