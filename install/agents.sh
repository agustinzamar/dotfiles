#!/usr/bin/env bash
# Refresh agent instruction files while preserving non-dot-owned content.
#
# merge_target() replaces <!-- dot:section name --> blocks by name,
# preserves all non-dot bytes (gentle-ai blocks, arbitrary user text),
# appends missing source sections, and fails on malformed input.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 1
REPO_ROOT=$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd -P) || exit 1
SOURCE="${SOURCE:-$REPO_ROOT/config/ai/AGENTS.md}"

[ -f "$SOURCE" ] || {
  echo "gentle-ai: missing source: $SOURCE" >&2
  exit 1
}

# Parse source <!-- dot:section name --> blocks into temp files.
# Each section becomes <dir>/<name>. Creates <dir> and a names list file.
# Fails on malformed or duplicate sections.
_parse_source_sections() {
  local file="$1" dir="$2" names_file="$3"
  local name="" content="" in_section=false

  # shellcheck disable=SC2188
  : >"$names_file"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\<!--\ dot:section\ ([^[:space:]]+)\ --\>$ ]]; then
      if $in_section; then
        echo "ERROR: nested or unclosed dot section: $name" >&2
        return 1
      fi
      name="${BASH_REMATCH[1]}"
      in_section=true
      content="$line"$'\n'
      continue
    fi

    if $in_section; then
      content+="$line"$'\n'
      if [[ "$line" =~ ^\<!--\ /dot:section\ --\>$ ]]; then
        in_section=false
        # Check for duplicate
        if grep -qFx "$name" "$names_file" 2>/dev/null; then
          echo "ERROR: duplicate dot section name: $name" >&2
          return 1
        fi
        echo "$name" >>"$names_file"
        printf '%s' "$content" >"$dir/$name"
        name="" content=""
      fi
    fi
  done <"$file"

  if $in_section; then
    echo "ERROR: unclosed dot section: $name" >&2
    return 1
  fi
}

# Merge source dot sections into a target file.
# - Replaces matching target sections by name (in place)
# - Preserves target-only sections
# - Preserves all non-dot content
# - Appends missing source sections at the end
# - Writes to a temp file, only moves if content changed
merge_target() {
  local target="$1"
  local temporary

  # Dry-run: report what would be done, change nothing.
  if "${DRY_RUN:-false}"; then
    echo "would merge: $target"
    return 0
  fi

  mkdir -p "$(dirname "$target")" || return 1
  temporary=$(mktemp "${target}.tmp.XXXXXX") || return 1

  # Parse source sections into temp files
  local sections_dir names_file
  sections_dir=$(mktemp -d) || return 1
  names_file=$(mktemp) || {
    rm -rf "$sections_dir" "$temporary"
    return 1
  }

  if ! _parse_source_sections "$SOURCE" "$sections_dir" "$names_file"; then
    rm -rf "$sections_dir" "$names_file" "$temporary"
    return 1
  fi

  # If target doesn't exist, just copy source
  if [[ ! -f "$target" ]]; then
    cp "$SOURCE" "$temporary"
    mv "$temporary" "$target"
    rm -rf "$sections_dir" "$names_file"
    return 0
  fi

  # Track which source sections have been placed
  local placed_file output_file
  placed_file=$(mktemp)
  output_file=$(mktemp)

  # Process target: replace matching sections, preserve others.
  # Malformed sections (unclosed) are preserved as-is with a warning.
  local in_section=false section_name="" section_content=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\<!--\ dot:section\ ([^[:space:]]+)\ --\>$ ]]; then
      in_section=true
      section_name="${BASH_REMATCH[1]}"
      section_content="$line"$'\n'
      continue
    fi

    if $in_section; then
      section_content+="$line"$'\n'
      if [[ "$line" =~ ^\<!--\ /dot:section\ --\>$ ]]; then
        in_section=false
        # Check if this section name exists in source
        if [[ -f "$sections_dir/$section_name" ]]; then
          # Replace with source content
          cat "$sections_dir/$section_name" >>"$output_file"
          echo "$section_name" >>"$placed_file"
        else
          # Target-only section: preserve it
          printf '%s' "$section_content" >>"$output_file"
        fi
        section_name="" section_content=""
      fi
      continue
    fi

    # Non-section line: preserve as-is
    printf '%s\n' "$line" >>"$output_file"
  done <"$target"

  # If we ended inside a section, the target has a malformed (unclosed) block.
  # Preserve it as-is rather than silently rewriting — the design promises to
  # preserve every byte outside dot-owned sections we fully understand.
  if $in_section; then
    echo "WARNING: malformed (unclosed) dot section '$section_name' in $target — preserving as-is" >&2
    printf '%s' "$section_content" >>"$output_file"
  fi

  # Append any source sections not yet placed (in source order)
  local sname
  while IFS= read -r sname; do
    [[ -n "$sname" ]] || continue
    if ! grep -qFx "$sname" "$placed_file" 2>/dev/null; then
      cat "$sections_dir/$sname" >>"$output_file"
    fi
  done <"$names_file"

  # Only move if content changed
  if ! cmp -s "$output_file" "$target" 2>/dev/null; then
    mv "$output_file" "$target"
  else
    rm -f "$output_file"
  fi
  rm -f "$temporary"
  rm -rf "$sections_dir" "$names_file" "$placed_file"
  return 0
}

# Run merge on all managed targets.
sync_all_targets() {
  local targets=(
    "$HOME/.agents/AGENTS.md"
    "$HOME/.config/opencode/AGENTS.md"
    "$HOME/.claude/CLAUDE.md"
    "$HOME/.codex/AGENTS.md"
  )
  local failures=0
  for target in "${targets[@]}"; do
    merge_target "$target" || failures=$((failures + 1))
  done
  _pi_normalize_markers || failures=$((failures + 1))
  return "$failures"
}

# Normalize PI agent close-marker mismatches.
# Open markers use pi-codegraph-tool or pi-codegraph-guidance, but close
# markers should be just pi-codegraph. If a close says -tool or -guidance,
# rewrite it to the generic pi-codegraph form for consistency.
# Scope: only the 23 files listed in the design spec, all under
# $HOME/.pi/agent/agents/. Idempotent — already-correct files are unchanged.
_pi_normalize_markers() {
  local pi_dir="$HOME/.pi/agent/agents"
  [[ -d "$pi_dir" ]] || return 0

  local files=(
    gentle-ai-explore gentle-ai-verify gentle-ai-worker
    jd-fix-agent jd-judge-a jd-judge-b
    review-readability review-reliability review-resilience review-risk
    sdd-apply sdd-archive sdd-design sdd-explore sdd-init sdd-onboard
    sdd-proposal sdd-research sdd-spec sdd-status sdd-sync sdd-tasks
    sdd-verify
  )

  local f name changed=0
  for name in "${files[@]}"; do
    f="$pi_dir/$name.md"
    [[ -f "$f" ]] || continue

    local file_changed=false

    # Close markers that include -tool or -guidance are mismatched: normalize
    # them to the generic pi-codegraph form.
    if grep -qF '<!-- /gentle-ai:pi-codegraph-tool -->' "$f"; then
      sed -i '' 's|<!-- /gentle-ai:pi-codegraph-tool -->|<!-- /gentle-ai:pi-codegraph -->|g' "$f"
      file_changed=true
    fi
    if grep -qF '<!-- /gentle-ai:pi-codegraph-guidance -->' "$f"; then
      sed -i '' 's|<!-- /gentle-ai:pi-codegraph-guidance -->|<!-- /gentle-ai:pi-codegraph -->|g' "$f"
      file_changed=true
    fi

    $file_changed && changed=$((changed + 1))
  done

  if ((changed > 0)); then
    echo "PI markers normalized in $changed file(s)"
  fi
  return 0
}

# When run directly (not sourced), sync all targets.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  sync_all_targets
fi
