#!/usr/bin/env bats

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOT="$DOTFILES_DIR/bin/dot"
}

@test "dot with no arguments prints usage" {
  run "$DOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: dot <command>"* ]]
}

@test "dot help lists commands" {
  run "$DOT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"link-shell"* ]]
  [[ "$output" == *"doctor"* ]]
}

@test "every command in help has a matching sub_ function" {
  local command name
  while read -r command; do
    name="sub_${command//-/_}"
    grep -q "^$name()" "$DOT" || {
      echo "no $name() for '$command'"
      return 1
    }
  done < <("$DOT" help | sed -n 's/^   \([a-z-]*\) .*/\1/p' | grep -v '^help$')
}

# Deleting a config without removing its line from the map leaves the target a
# dangling symlink after `dot link`. That is how ~/.claude/skills broke.
@test "every source in the link map exists" {
  local source target missing=0
  while IFS='|' read -r source target; do
    [ -n "$source" ] || continue
    [ -e "$DOTFILES_DIR/$source" ] || {
      echo "missing source: $source"
      missing=1
    }
  done < <(DOTFILES_DIR="$DOTFILES_DIR" bash -c '. "$0/install/links.sh"; all_links' "$DOTFILES_DIR")
  [ "$missing" -eq 0 ]
}

@test "an unknown command exits 1" {
  run "$DOT" definitely-not-a-command
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a known command"* ]]
}

@test "dry-run link prints symlink commands" {
  HOME="$(mktemp -d)" run "$DOT" link --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s"* ]]
}

@test "dry-run link does not touch the filesystem" {
  local home
  home="$(mktemp -d)"
  HOME="$home" run "$DOT" link --dry-run
  [ "$status" -eq 0 ]
  # Regression test: link_file used to mkdir -p outside of run().
  [ -z "$(find "$home" -mindepth 1)" ]
}

@test "link and unlink round-trip" {
  local home
  home="$(mktemp -d)"
  HOME="$home" "$DOT" link
  [ "$(readlink "$home/.zshrc")" = "$DOTFILES_DIR/config/zsh/.zshrc" ]
  HOME="$home" "$DOT" unlink
  [ ! -e "$home/.zshrc" ]
}

@test "link is idempotent" {
  local home
  home="$(mktemp -d)"
  HOME="$home" "$DOT" link
  HOME="$home" "$DOT" link
  # A second run finds every link already correct, so it makes no backup.
  [ ! -d "$home/.dotfiles-backup" ]
}

@test "a replaced file is backed up under its own path" {
  local home
  home="$(mktemp -d)"
  mkdir -p "$home/.config/ghostty"
  echo original > "$home/.config/ghostty/config"
  HOME="$home" "$DOT" link
  # Regression test: backups used to flatten to the basename, so several
  # files named `config` clobbered each other.
  [ "$(cat "$home"/.dotfiles-backup/*/.config/ghostty/config)" = "original" ]
}

@test "is-executable detects present and absent commands" {
  run "$DOTFILES_DIR/bin/is-executable" bash
  [ "$status" -eq 0 ]
  run "$DOTFILES_DIR/bin/is-executable" definitely-not-installed-xyz
  [ "$status" -eq 1 ]
}

@test "is-supported echoes the matching branch" {
  run "$DOTFILES_DIR/bin/is-supported" true yes no
  [ "$output" = "yes" ]
  run "$DOTFILES_DIR/bin/is-supported" false yes no
  [ "$output" = "no" ]
}
