#!/usr/bin/env bash
# Shared helpers for bin/dot. Sourced, never executed.
# Expects DOTFILES_DIR and DRY_RUN to be exported by bin/dot.

: "${DOTFILES_DIR:?install/common.sh requires DOTFILES_DIR}"
: "${DRY_RUN:=false}"

BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%dT%H%M%S)"

# Apply a list of shell files. Each file is sourced in order,
# so later files can override earlier ones.
apply_defaults() {
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    log "Applying ${file#"$DOTFILES_DIR"/}"
    if "$DRY_RUN"; then
      echo "+ source ${file#"$DOTFILES_DIR"/}"
    else
      # shellcheck source=/dev/null
      . "$file"
    fi
  done
}

# The package files are plain lists: one name per line, `#` comments and blank
# lines ignored. Keeping them as data means adding a package is a one-line diff.
read_package_file() {
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

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

# Path a replaced target is moved to. The target's location under $HOME is
# preserved so that same-named files (several apps ship a plain `config`) do
# not overwrite each other inside a single backup directory.
backup_path() {
  local rel=${1#"$HOME"/}
  printf '%s/%s' "$BACKUP_DIR" "${rel#/}"
}

# link_file <repo-relative-source> <absolute-target> [mode]
link_file() {
  local source="$DOTFILES_DIR/$1" target=$2 mode=${3:-} current backup
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

  if [[ "$mode" == app-writable && -f "$target" && ! -L "$target" ]]; then
    # The app maintains this file itself, so never overwrite or replace it
    # with a symlink: a future app write would just orphan the symlink. Back up
    # the live copy and leave it in place — the user can adopt the repo version
    # by hand (delete the live file, then re-run). A backup is only needed when
    # the live and tracked copies differ.
    if ! cmp -s "$source" "$target"; then
      backup=$(backup_path "$target")
      run mkdir -p "$(dirname "$backup")"
      run cp "$target" "$backup"
      printf '\nConfig conflict:\n  live: %s\n  repo: %s\n' "$target" "$source" >&2
      [[ "$DRY_RUN" == false ]] &&
        printf '  kept the live file; a copy was saved to %s\n' "$backup" >&2
      printf '  re-run after editing %s to match, or remove it to adopt the repo version.\n' "$target" >&2
    fi
    return 0
  elif [[ -e "$target" || -L "$target" ]]; then
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

# Every file under install/topics/ is a Brewfile and a command: `dot media`
# installs install/topics/media. Adding a topic is adding one file.
TOPIC_DIR="$DOTFILES_DIR/install/topics"

# `return 0` because a glob that ends on a non-file would otherwise leave the
# function's status non-zero, which `set -e` treats as a failure.
_topic_names() {
  local file
  for file in "$1"/*; do
    [[ -f "$file" ]] && basename "$file"
  done
  return 0
}

topics() { _topic_names "$TOPIC_DIR"; }

# Every topic name a user can install by name, comma-joined.
topic_names() {
  topics | paste -sd, - | sed 's/,/, /g'
  return 0
}

topic_path() {
  local dir="$TOPIC_DIR/$1"
  [[ -f "$dir" ]] && {
    printf '%s' "$dir"
    return 0
  }
  return 1
}

# Run a single Brewfile by absolute path, logging under the given label.
run_topic_file() {
  log "Installing $1"
  run brew bundle --file="$2"
}
