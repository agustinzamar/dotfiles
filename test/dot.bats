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

@test "every command in help is dispatchable" {
  local command name
  while read -r command; do
    name="sub_${command//-/_}"
    grep -q "^$name()" "$DOT" ||
      [ -f "$DOTFILES_DIR/install/topics/$command" ] ||
      [ -f "$DOTFILES_DIR/install/topics/optional/$command" ] || {
        echo "'$command' has neither $name() nor a topic file"
        return 1
      }
  done < <("$DOT" help | sed -n 's/^   \([a-z-]*\) .*/\1/p' | grep -v '^help$')
}

@test "every topic is listed in help and runs as a command" {
  local topic
  for topic in "$DOTFILES_DIR"/install/topics/* "$DOTFILES_DIR"/install/topics/optional/*; do
    [ -f "$topic" ] || continue
    topic=$(basename "$topic")
    "$DOT" help | grep -q "^   $topic " || {
      echo "topic '$topic' missing from help"
      return 1
    }
    run "$DOT" "$topic" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"/topics/"*"/$topic"* || "$output" == *"/topics/$topic"* ]]
  done
}

# The whole point of optional/: a machine opts in by name, `brew` never does.
@test "brew installs every default topic and no optional one" {
  local topic
  run "$DOT" brew --dry-run
  [ "$status" -eq 0 ]
  for topic in "$DOTFILES_DIR"/install/topics/*; do
    [ -f "$topic" ] || continue
    [[ "$output" == *"topics/$(basename "$topic")"* ]]
  done
  for topic in "$DOTFILES_DIR"/install/topics/optional/*; do
    [ -f "$topic" ] || continue
    [[ "$output" != *"optional/$(basename "$topic")"* ]]
  done
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

# Renaming a shell file leaves the old symlink dangling; zsh matches it and
# fails to source it on every prompt.
@test "link prunes shell symlinks whose source is gone" {
  home="$(mktemp -d)"
  mkdir -p "$home/.dotfiles-home/aliases"
  ln -s "$DOTFILES_DIR/system/aliases/gone.zsh" "$home/.dotfiles-home/aliases/gone.zsh"
  HOME="$home" run "$DOT" link-shell
  [ "$status" -eq 0 ]
  [ ! -L "$home/.dotfiles-home/aliases/gone.zsh" ]
}

# Stale links point through ~/.dotfiles or at an old clone, not at
# $DOTFILES_DIR, so the sweep must not match on the target path.
@test "link prunes a stale symlink pointing at another clone" {
  home="$(mktemp -d)"
  mkdir -p "$home/.dotfiles-home/functions"
  ln -s /somewhere/else/dotfiles/system/functions/old.zsh \
    "$home/.dotfiles-home/functions/old.zsh"
  HOME="$home" run "$DOT" link-shell
  [ "$status" -eq 0 ]
  [ ! -L "$home/.dotfiles-home/functions/old.zsh" ]
}

# A link that still resolves is left alone, stale-looking target or not.
@test "link leaves resolving symlinks alone" {
  home="$(mktemp -d)"
  mkdir -p "$home/.dotfiles-home/aliases"
  echo "alias x=y" > "$home/real.zsh"
  ln -s "$home/real.zsh" "$home/.dotfiles-home/aliases/keep.zsh"
  HOME="$home" run "$DOT" link-shell
  [ "$status" -eq 0 ]
  [ -L "$home/.dotfiles-home/aliases/keep.zsh" ]
}
