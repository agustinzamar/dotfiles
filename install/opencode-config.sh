#!/usr/bin/env bash
# Merge config/opencode/opencode.json (defaults) into ~/.config/opencode/opencode.json
# (app-managed).  Deep-merges top-level keys: for each key in defaults, if
# missing from the live file or a nested object, individual sub-keys are added
# without overwriting existing values.
#
# Sourced by bin/dot -- expects $DOTFILES_DIR and $DRY_RUN.

install_opencode_config() {

  if ! command -v opencode >/dev/null 2>&1; then
    echo "opencode not installed, skipping config merge" >&2
    return 0
  fi

  local defaults="$DOTFILES_DIR/config/opencode/opencode.json"
  local target="$HOME/.config/opencode/opencode.json"

  [[ -f "$defaults" ]] || {
    log "No opencode config defaults at $defaults; skipping"
    return 0
  }

  # Remove the old symlink if it still points into this repo.
  if [[ -L "$target" ]]; then
    local link_target
    link_target=$(readlink "$target")
    if [[ "$link_target" == "$DOTFILES_DIR"* ]]; then
      run rm "$target"
    fi
  fi

  # Ensure target dir exists.
  run mkdir -p "$(dirname "$target")"

  # If the live file doesn't exist yet, just write defaults.
  if [[ ! -f "$target" ]]; then
    log "Opencode: writing default config from opencode.json"
    run cp "$defaults" "$target"
    return 0
  fi

  # Deep merge: for each key in defaults, add to target if missing.
  # Nested objects are merged recursively (existing sub-keys preserved).
  local tmpfile
  tmpfile=$(mktemp)

  # jq filter: deepMerge(a; b) takes two values and returns b with any keys
  # from a that don't exist in b (recursing into objects).
  if ! jq -n \
    --slurpfile defaults "$defaults" \
    --slurpfile current "$target" '
      def deepMerge(a; b):
        if (a | type) == "object" and (b | type) == "object" then
          reduce (a | keys[]) as $k (b; .[$k] = deepMerge(a[$k]; b[$k]))
        elif b != null then b
        else a
        end;
      deepMerge($defaults[0]; $current[0])
    ' >"$tmpfile" 2>/dev/null; then
    log "Opencode: jq merge failed; keeping live file unchanged"
    rm -f "$tmpfile"
    return 1
  fi

  # Only write if the merged result actually differs.
  if cmp -s "$target" "$tmpfile"; then
    rm -f "$tmpfile"
    return 0
  fi

  log "Opencode: merging default keys from opencode.json into settings.json"
  run mv "$tmpfile" "$target"
}
