#!/usr/bin/env bash
# Shared helpers for bin/dot. Sourced, never executed.
# Expects DOTFILES_DIR and DRY_RUN to be exported by bin/dot.

: "${DOTFILES_DIR:?install/common.sh requires DOTFILES_DIR}"
: "${DRY_RUN:=false}"

BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%dT%H%M%S)"

# Run a command, or print it when --dry-run is in effect.
run() {
  if "$DRY_RUN"; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

log() { printf '\n==> %s\n' "$*"; }

is_executable() { type "$1" >/dev/null 2>&1; }

defaults_write() { run defaults write "$1" "$2" "-$3" "$4"; }

# Path a replaced target is moved to. The target's location under $HOME is
# preserved so that same-named files (several apps ship a plain `config`) do
# not overwrite each other inside a single backup directory.
backup_path() {
  local rel=${1#"$HOME"/}
  printf '%s/%s' "$BACKUP_DIR" "${rel#/}"
}

# link_file <repo-relative-source> <absolute-target>
link_file() {
  local source="$DOTFILES_DIR/$1" target=$2 current backup
  if [[ ! -e "$source" && ! -L "$source" ]]; then
    # Generated configs (see install/git.sh) do not exist during a dry run,
    # so only treat a missing source as fatal when actually installing.
    if "$DRY_RUN"; then
      echo "note: source not present yet: $source" >&2
    else
      echo "missing source: $source" >&2
      return 1
    fi
  fi

  current=$(readlink "$target" 2>/dev/null || true)
  [[ "$current" == "$source" ]] && return 0

  if [[ -e "$target" || -L "$target" ]]; then
    backup=$(backup_path "$target")
    run mkdir -p "$(dirname "$backup")"
    run mv "$target" "$backup"
  fi
  run mkdir -p "$(dirname "$target")"
  run ln -s "$source" "$target"
}

# unlink_file <repo-relative-source> <absolute-target>
# Only removes a symlink that actually points into this repo.
unlink_file() {
  local source="$DOTFILES_DIR/$1" target=$2
  [[ "$(readlink "$target" 2>/dev/null || true)" == "$source" ]] || return 0
  run rm "$target"
}
