#!/usr/bin/env bash
# Shared sandbox for the bats suites that run bin/dot end to end.
#
# SAFETY. `dot link`, `dot unlink` and `dot install` write into $HOME and into
# the global git config. On a developer machine ~/.zshrc and ~/.gitconfig are
# symlinks into this repo, so a leaked run would replace tracked source.
# box_setup() builds a scratch HOME plus a curated PATH and records both the
# real global git config and what the real $HOME holds at every target the link
# map can reach; box_teardown() fails loudly if any of it moved.
#
# The OS family is a PATH stub (`uname`, plus `apt-get` for the debian case),
# never the host's own uname, so every assertion is a property of a declared
# fixture rather than of the machine running the suite.

# Every target the link map can reach, resolved against the REAL home.
real_home_targets() {
  "$BASH" -c '
    . "$1/install/links.sh"
    if declare -F all_links_raw >/dev/null 2>&1; then all_links_raw; else all_links; fi
    optional_links' _ "$DOTFILES_DIR" | cut -d'|' -f3
}

real_home_snapshot() {
  local target file
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    if [[ -L "$target" ]]; then
      printf 'link %s -> %s\n' "$target" "$(readlink "$target")"
    elif [[ -e "$target" ]]; then
      printf 'file %s\n' "$target"
    else
      printf 'absent %s\n' "$target"
    fi
  done < <(real_home_targets)
  for file in "${GIT_CONFIG_GLOBAL:-}" "$HOME/.gitconfig" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/git/config"; do
    [[ -n "$file" ]] || continue
    if [[ -e "$file" ]]; then sha256sum "$file"; else echo "absent $file"; fi
  done
}

box_setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOT="$DOTFILES_DIR/bin/dot"
  REAL_HOME_BEFORE=$(real_home_snapshot)

  SCRATCH="$BATS_TEST_TMPDIR/box"
  SCRATCH_HOME="$SCRATCH/home"
  STUB_BIN="$SCRATCH/stub"
  REAL_BIN="$SCRATCH/real"
  mkdir -p "$SCRATCH_HOME" "$STUB_BIN" "$REAL_BIN"

  # A curated PATH built from symlinks: a binary is visible to the CLI only
  # when a test asks for it, so `brew`/`bat`/`batcat` presence is a declared
  # fixture and not whatever this machine happens to have installed.
  local tool path
  for tool in bash sh env git jq date sed grep awk basename dirname paste cat \
    ls mkdir rm mv cp ln readlink cmp sort uniq head tail tr cut wc find stat \
    chmod mktemp xargs id tput; do
    if path=$(command -v "$tool" 2>/dev/null); then
      ln -sf "$path" "$REAL_BIN/$tool"
    fi
  done
  ln -sf "$DOT" "$REAL_BIN/dot"
}

box_teardown() {
  local after
  after=$(real_home_snapshot)
  if [[ "$REAL_HOME_BEFORE" != "$after" ]]; then
    echo "FATAL: this test escaped the box and changed the real \$HOME"
    diff <(printf '%s\n' "$REAL_HOME_BEFORE") <(printf '%s\n' "$after") || true
    return 1
  fi
}

stub() {
  printf '#!/bin/sh\n%s\n' "$2" >"$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

# Declare the OS family this box detects.
box_family() {
  case "$1" in
    macos) stub uname 'echo Darwin' ;;
    debian)
      stub uname 'echo Linux'
      stub apt-get 'exit 0'
      ;;
    unknown) stub uname 'echo Redox' ;;
    *) return 1 ;;
  esac
}

# The only sanctioned way to run the CLI inside the box.
dot_cli() {
  env -i \
    HOME="$SCRATCH_HOME" \
    GIT_CONFIG_GLOBAL="$SCRATCH_HOME/.gitconfig" \
    GIT_CONFIG_NOSYSTEM=1 \
    PATH="$STUB_BIN:$REAL_BIN" \
    TERM=dumb \
    ${LINK_VERBOSE:+LINK_VERBOSE="$LINK_VERBOSE"} \
    "$DOT" "$@"
}
