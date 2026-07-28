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
  [[ "$output" == *"links"* ]]
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

@test "every topic is listed in help and installable" {
  local topic
  for topic in "$DOTFILES_DIR"/install/topics/*; do
    [ -f "$topic" ] || continue
    topic=$(basename "$topic")
    [[ "$topic" == "apps" || "$topic" == "ai" ]] && continue  # install subcommands, not brew topics
    "$DOT" help | grep -q "^   $topic " || {
      echo "topic '$topic' missing from help"
      return 1
    }
    run "$DOT" install "$topic" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"/topics/"*"/$topic"* || "$output" == *"/topics/$topic"* ]]
  done
}

# The completion parses `dot help`, so a change to the help format silently
# leaves it offering nothing.
@test "the zsh completion parses every command out of help" {
  local from_help from_completion
  from_help=$("$DOT" help | sed -n 's/^   \([a-z][a-z0-9-]*\)  *.*/\1/p' | sort)
  # The same expression the completion function uses.
  from_completion=$("$DOT" help |
    sed -n 's/^   \([a-z][a-z0-9-]*\)  *\(.*\)$/\1:\2/p' | cut -d: -f1 | sort)
  [ -n "$from_completion" ]
  [ "$from_help" = "$from_completion" ]
}

@test "the completion is a zsh compdef for dot" {
  local file="$DOTFILES_DIR/system/completions/_dot"
  [ -f "$file" ]
  head -1 "$file" | grep -q '^#compdef dot$'
  zsh -n "$file"
}

# The macos scripts call `defaults write` directly instead of going through
# `run`, so a dry run must stop short of sourcing them.
@test "macos dry-run reports without sourcing" {
  run "$DOT" install macos --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ source system/macos/_defaults.sh"* ]]
  [[ "$output" != *"sudo"* ]]
}

# `_defaults.sh` must sort before the per-app files; that is what the leading
# underscore is for.
@test "macos applies the shared defaults first" {
  run "$DOT" install macos --dry-run
  [ "$status" -eq 0 ]
  [[ "$(grep -c 'source system/macos/' <<<"$output")" -ge 2 ]]
  [[ "$(grep -m1 'source system/macos/' <<<"$output")" == *"_defaults.sh"* ]]
}

# duti reads a file with no final newline as an unterminated extra line and
# fails with "line too long". .editorconfig asks for one; nothing enforced it.
@test "every package file ends with a newline" {
  local file bad=0
  for file in "$DOTFILES_DIR"/install/duti \
    "$DOTFILES_DIR"/install/Codefile \
    "$DOTFILES_DIR"/install/topics/* \
    "$DOTFILES_DIR"/install/topics/optional/*; do
    [ -f "$file" ] || continue
    [ -z "$(tail -c 1 "$file")" ] || {
      echo "no final newline: ${file#"$DOTFILES_DIR"/}"
      bad=1
    }
  done
  [ "$bad" -eq 0 ]
}

# `brew "chatgpt"` on a cask fails only once a real install reaches it, which
# is how three casks sat in the AI topic declared as formulae.
@test "every package is declared with the right type" {
  command -v brew >/dev/null || skip "brew not installed"

  # Two `brew` calls rather than one per package: `brew info` costs a second
  # each, these are instant and give the complete name lists.
  local formulae casks
  formulae=$(brew formulae 2>/dev/null)
  casks=$(brew casks 2>/dev/null)
  [ -n "$formulae" ] && [ -n "$casks" ] || skip "brew name lists unavailable"

  local file line name wrong=0
  for file in "$DOTFILES_DIR"/install/topics/* "$DOTFILES_DIR"/install/topics/optional/*; do
    [ -f "$file" ] || continue
    while IFS= read -r line; do
      case "$line" in
        'brew "'* | 'cask "'*) ;;
        *) continue ;;
      esac
      name=${line#* \"}
      name=${name%\"}

      # A tap-qualified name (owner/tap/pkg) only resolves once that tap is
      # added, which CI does not do. Nothing to check against.
      case "$name" in */*) continue ;; esac

      case "$line" in
        'brew "'*)
          grep -qxF "$name" <<<"$formulae" || {
            echo "$(basename "$file"): brew \"$name\" is not a formula"
            wrong=1
          }
          ;;
        'cask "'*)
          grep -qxF "$name" <<<"$casks" || {
            echo "$(basename "$file"): cask \"$name\" is not a cask"
            wrong=1
          }
          ;;
      esac
    done < "$file"
  done
  [ "$wrong" -eq 0 ]
}

# A broken package used to abort the run, so `link` never ran and the shell
# kept sourcing symlinks that no longer resolved.
#
# Scoped to `brew`, deliberately. Testing this through `dot install` means
# really running sub_macos, which sources system/macos/_defaults.sh and writes
# a few hundred settings to the preferences of whoever runs the suite.
@test "a failing topic does not stop the other topics" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 1\n' > "$stub/brew"
  chmod +x "$stub/brew"

  PATH="$stub:$PATH" run "$DOT" install brew
  [ "$status" -eq 1 ]
  [[ "$output" == *"topics that failed:"* ]]
  # Every topic was attempted rather than the run stopping at the first.
  [[ "$output" == *"ai"* && "$output" == *"system"* ]]
}

# The phase list drives the loop that collects failures; if a phase is dropped
# from it, install silently stops doing that work.
@test "install runs every phase through the failure-collecting loop" {
  local phase
  for phase in brew link zsh tools code macos duti git; do
    grep -q "for phase in .*\b$phase\b" "$DOT" || {
      echo "phase '$phase' missing from the full-install loop"
      return 1
    }
  done
}

# dock-defaults.sh is in the macos glob, so installing it again as its own
# phase kills the Dock twice and the second killall exits 1.
@test "install does not run dock as a separate phase" {
  grep -q "for phase in .*\bdock\b" "$DOT" && {
    echo "dock is back in the install loop; macos already sources it"
    return 1
  }
  # Still reachable on its own.
  run "$DOT" install dock --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dock-defaults.sh"* ]]
}

# The whole point of optional/: a machine opts in by name, `brew` never does.
@test "brew installs every default topic and no optional one" {
  local topic
  run "$DOT" install brew --dry-run
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

# ~/.dotfiles is a symlink to the repo, so invoking dot through it used to give
# a DOTFILES_DIR that did not match the paths `link` wrote into the symlinks:
# doctor called every link broken and unlink declined to remove them.
@test "DOTFILES_DIR is the same however dot is invoked" {
  local link direct via_symlink
  link="$(mktemp -d)/dotfiles-link"
  ln -s "$DOTFILES_DIR" "$link"

  # A temporary HOME for both: with the real one, link_file finds the links
  # already correct and prints nothing.
  direct=$(HOME="$(mktemp -d)" "$DOT" install link --dry-run 2>&1 |
    grep -m1 -o '/[^ ]*/config/zsh/.zshrc')
  via_symlink=$(HOME="$(mktemp -d)" "$link/bin/dot" install link --dry-run 2>&1 |
    grep -m1 -o '/[^ ]*/config/zsh/.zshrc')
  [ -n "$direct" ]
  [ "$direct" = "$via_symlink" ]
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
  HOME="$(mktemp -d)" run "$DOT" install link --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s"* ]]
}

@test "dry-run link does not touch the filesystem" {
  local home
  home="$(mktemp -d)"
  HOME="$home" run "$DOT" install link --dry-run
  [ "$status" -eq 0 ]
  # Regression test: link_file used to mkdir -p outside of run().
  [ -z "$(find "$home" -mindepth 1)" ]
}

@test "link and unlink round-trip" {
  local home
  home="$(mktemp -d)"
  HOME="$home" "$DOT" install link
  [ "$(readlink "$home/.zshrc")" = "$DOTFILES_DIR/config/zsh/.zshrc" ]
  HOME="$home" "$DOT" unlink
  [ ! -e "$home/.zshrc" ]
}

@test "link is idempotent" {
  local home
  home="$(mktemp -d)"
  HOME="$home" "$DOT" install link
  HOME="$home" "$DOT" install link
  # A second run finds every link already correct, so it makes no backup.
  [ ! -d "$home/.dotfiles-backup" ]
}

@test "a replaced file is backed up under its own path" {
  local home
  home="$(mktemp -d)"
  mkdir -p "$home/.config/ghostty"
  echo original > "$home/.config/ghostty/config"
  HOME="$home" "$DOT" install link
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
  HOME="$home" run "$DOT" install links
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
  HOME="$home" run "$DOT" install links
  [ "$status" -eq 0 ]
  [ ! -L "$home/.dotfiles-home/functions/old.zsh" ]
}

# A link that still resolves is left alone, stale-looking target or not.
@test "link leaves resolving symlinks alone" {
  home="$(mktemp -d)"
  mkdir -p "$home/.dotfiles-home/aliases"
  echo "alias x=y" > "$home/real.zsh"
  ln -s "$home/real.zsh" "$home/.dotfiles-home/aliases/keep.zsh"
  HOME="$home" run "$DOT" install links
  [ "$status" -eq 0 ]
  [ -L "$home/.dotfiles-home/aliases/keep.zsh" ]
}
