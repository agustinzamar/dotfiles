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
  [[ "$output" == *"link <name>"* ]]
  [[ "$output" == *"doctor"* ]]
}

# Uses the same expression as the completion function (system/completions/_dot)
# so help continuation lines, which indent without a command name, are skipped.
@test "every command in help is dispatchable" {
  local command name
  while read -r command; do
    name="sub_${command//-/_}"
    grep -q "^$name()" "$DOT" ||
      [ -f "$DOTFILES_DIR/install/topics/$command" ] || {
        echo "'$command' has neither $name() nor a topic file"
        return 1
      }
  done < <("$DOT" help | sed -n 's/^   \([a-z][a-z0-9-]*\)   *.*$/\1/p' | grep -v '^help$')
}

# Topics are no longer listed as standalone commands in help: a single
# `install <topic>` line names them all. That line must name every topic,
# and each of them must still install.
@test "install <topic> help line mentions every topic and each topic installs" {
  local topics help_line topic
  topics=$(DOTFILES_DIR="$DOTFILES_DIR" bash -c '. "$0/install/common.sh"; topics' "$DOTFILES_DIR")
  help_line=$("$DOT" help | grep '^   install <topic>')
  [[ -n "$help_line" ]]
  echo "$topics" | while read -r topic; do
    grep -qF "$topic" <<<"$help_line" || {
      echo "topic '$topic' missing from the install <topic> help line"
      exit 1
    }
    run "$DOT" install "$topic" --dry-run
    { [ "$status" -eq 0 ] && { grep -q "^sub_${topic}()" "$DOT" || [[ "$output" == *"--file=$DOTFILES_DIR/install/topics/$topic "* ]]; }; } || {
      echo "install $topic failed: status=$status output=$output"
      exit 1
    }
  done
}

@test "help no longer advertises install ai" {
  run "$DOT" help
  [ "$status" -eq 0 ]
  [[ "$output" != *"install ai"* ]]
}

# The completion parses `dot help`, so a change to the help format silently
# leaves it offering nothing. The 3-space minimum in the sed regex skips
# sub-arg lines (`link <name>`, `install <topic>`, `install --all`) which have
# only one space between the command word and its argument; without it the
# completion menu would show `link` and `install` three times each.
@test "the zsh completion parses every command out of help" {
  local from_help from_completion
  from_help=$("$DOT" help | sed -n 's/^   \([a-z][a-z0-9-]*\)   *.*/\1/p' | sort -u)
  # The same expression the completion function uses.
  from_completion=$("$DOT" help |
    sed -n 's/^   \([a-z][a-z0-9-]*\)   *\(.*\)$/\1:\2/p' | cut -d: -f1 | sort -u)
  [ -n "$from_completion" ]
  [ "$from_help" = "$from_completion" ]
  # No command should appear more than once; that has happened when the
  # regex picked up sub-arg lines (`link <name>`, `install <topic>`).
  local counts duplicate
  counts=$("$DOT" help |
    sed -n 's/^   \([a-z][a-z0-9-]*\)   *\(.*\)$/\1/p' | sort | uniq -d)
  duplicate=$counts
  [ -z "$duplicate" ]
}

@test "the completion is a zsh compdef for dot" {
  local file="$DOTFILES_DIR/system/completions/_dot"
  [ -f "$file" ]
  head -1 "$file" | grep -q '^#compdef dot$'
  zsh -n "$file"
}

# The macos script calls `defaults write` and `sudo` directly instead of going
# through `run`, so a dry run must stop short of sourcing it.
@test "macos dry-run reports without sourcing" {
  run "$DOT" install macos --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ source system/defaults/macos.sh"* ]]
  [[ "$output" != *"sudo"* ]]
}

@test "macos sources the defaults file" {
  run "$DOT" install macos --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ source system/defaults/macos.sh"* ]]
}

# duti reads a file with no final newline as an unterminated extra line and
# fails with "line too long". .editorconfig asks for one; nothing enforced it.
@test "every package file ends with a newline" {
  local file bad=0
  for file in "$DOTFILES_DIR"/install/topics/duti \
    "$DOTFILES_DIR"/install/topics/code \
    "$DOTFILES_DIR"/install/topics/*; do
    [ -f "$file" ] || continue
    [ -z "$(tail -c 1 "$file")" ] || {
      echo "no final newline: ${file#"$DOTFILES_DIR"/}"
      bad=1
    }
  done
  [ "$bad" -eq 0 ]
}

# install/topics/duti has gone missing before (moved by accident) while the
# code that reads it stayed silent about it, so `dot install duti` just
# errored on a real machine that had duti installed.
@test "duti package list exists" {
  [ -f "$DOTFILES_DIR/install/topics/duti" ]
}

# `cask repobar` and `brew install foo/tap/bar` are both syntactically valid
# Ruby, so `bash -n`/`ruby -c` pass and only `brew bundle` itself catches them
# — which needs network/homebrew and CI never ran it against these files.
# A structural line-shape check catches the same class of typo for free.
@test "every topic file line is a properly quoted brew or cask entry" {
  local file line bad=0
  for file in "$DOTFILES_DIR"/install/topics/*; do
    [ -f "$file" ] || continue
    # code and duti are plain lists consumed by sub_code/sub_duti, not Brewfiles.
    grep -q "^sub_$(basename "$file")()" "$DOT" && continue
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      [[ "$line" =~ ^(brew|cask)\ \"[^\"]+\"$ ]] || {
        echo "${file#"$DOTFILES_DIR"/}: malformed line: $line"
        bad=1
      }
    done < "$file"
  done
  [ "$bad" -eq 0 ]
}

# `brew "chatgpt"` on a cask fails only once a real install reaches it, which
# is how three casks sat in the AI topic declared as formulae.
@test "every package is declared with the right type" {
  command -v brew >/dev/null || skip "brew not installed"

  # Prefer the API name caches. `brew search --cask ''` exits 1 as soon as one
  # third-party tap is untrusted, which turned this test into a permanent skip
  # on a real machine — and that is how `brew "ghostty"` (a cask) survived.
  local formulae casks api="${HOMEBREW_CACHE:-$HOME/Library/Caches/Homebrew}/api"
  if [ -r "$api/formula_names.txt" ] && [ -r "$api/cask_names.txt" ]; then
    formulae=$(<"$api/formula_names.txt")
    casks=$(<"$api/cask_names.txt")
  else
    formulae=$(brew search --formula '' 2>/dev/null) || skip "brew formulae unavailable"
    casks=$(brew search --cask '' 2>/dev/null) || skip "brew casks unavailable"
  fi

  local file line name wrong=0
  for file in "$DOTFILES_DIR"/install/topics/*; do
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

      # Only a definite mismatch fails: the name is declared one way and exists
      # the other way. A name in neither list is an alias (`7zip` ->
      # `sevenzip`, `postgresql` -> `postgresql@18`) or lives in a tap, and
      # both of those install fine.
      case "$line" in
        'brew "'*)
          if ! grep -qxF "$name" <<<"$formulae" && grep -qxF "$name" <<<"$casks"; then
            echo "$(basename "$file"): brew \"$name\" is a cask"
            wrong=1
          fi
          ;;
        'cask "'*)
          if ! grep -qxF "$name" <<<"$casks" && grep -qxF "$name" <<<"$formulae"; then
            echo "$(basename "$file"): cask \"$name\" is a formula"
            wrong=1
          fi
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
  # Every topic was attempted rather than the run stopping at the first. Name
  # two real topics: a substring that also occurs in "failed" would pass here
  # even when only one topic ran.
  [[ "$output" == *"dev"* && "$output" == *"media"* ]]
}

# .zshrc runs before there is a prompt, so it must not clone anything, and it
# must find the repo from its own path rather than assuming ~/dotfiles.
@test "zshrc installs nothing and hardcodes no repo path" {
  local zshrc="$DOTFILES_DIR/config/zsh/.zshrc"
  ! grep -qE 'git clone' "$zshrc"
  ! grep -qE '\$\{?HOME\}?/dotfiles' "$zshrc"
  grep -q 'DOTFILES_DIR=' "$zshrc"

  # zsh resolves it through the symlink that `dot link zsh` puts at ~/.zshrc.
  run zsh -c "source '$zshrc' >/dev/null 2>&1; print -- \$DOTFILES_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "$DOTFILES_DIR" ]
}

# An exported secret is inherited by every command the shell runs.
@test "no shell file exports a secret" {
  local hits
  hits=$(grep -rlE '^ *export [A-Z_]*(TOKEN|SECRET|PASSWORD|API_KEY)' \
    "$DOTFILES_DIR"/system "$DOTFILES_DIR"/config 2>/dev/null || true)
  [ -z "$hits" ] || {
    echo "exports a secret into every child process: $hits"
    return 1
  }
}

# The phase list drives the loop that collects failures; if a phase is dropped
# from it, install silently stops doing that work.
# topics/code and topics/duti are a VS Code extension list and a duti mapping
# table. `brew bundle` reads a Brewfile as Ruby and dies on both, so `dot brew`
# reported two failed topics on every machine.
@test "brew skips the topics that have their own installer" {
  local stub log
  stub="$(mktemp -d)"
  log="$stub/log"
  cat >"$stub/brew" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$BREW_LOG"
exit 0
EOF
  chmod +x "$stub/brew"

  BREW_LOG="$log" PATH="$stub:$PATH" run "$DOT" install brew
  [ "$status" -eq 0 ]
  grep -q 'topics/core' "$log"
  ! grep -q 'topics/duti' "$log"
  ! grep -q 'topics/code' "$log"
}

@test "install runs every phase through the failure-collecting loop" {
  local phase
  for phase in brew link zsh code macos duti git; do
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
  [[ "$output" == *"dock.sh"* ]]
}

# bin/dot brew/link/etc used to only dispatch through `dot install <name>`;
# the README documents them as top-level commands in their own right.
@test "install subcommands and topics work as bare top-level commands" {
  run "$DOT" brew --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"install/topics/core"* ]]

  run "$DOT" core --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"install/topics/core"* ]]

  HOME="$(mktemp -d)" run "$DOT" link p10k --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Linking p10k"* ]]
}

@test "an unknown install target exits 1" {
  run "$DOT" install definitely-not-a-topic
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not an install command or topic"* ]]
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
  direct=$(HOME="$(mktemp -d)" "$DOT" link --dry-run 2>&1 |
    grep -m1 -o '/[^ ]*/config/zsh/.zshrc')
  via_symlink=$(HOME="$(mktemp -d)" "$link/bin/dot" link --dry-run 2>&1 |
    grep -m1 -o '/[^ ]*/config/zsh/.zshrc')
  [ -n "$direct" ]
  [ "$direct" = "$via_symlink" ]
}

# Deleting a config without removing its line from the map leaves the target a
# dangling symlink after `dot link`. That is how ~/.claude/skills broke.
@test "every source in the link map exists" {
  local source target missing=0
  while IFS='|' read -r name source target mode; do
    [ -n "$source" ] || continue
    [ -e "$DOTFILES_DIR/$source" ] || {
      echo "missing source: $source"
      missing=1
    }
  done < <(DOTFILES_DIR="$DOTFILES_DIR" bash -c '. "$0/install/links.sh"; all_links' "$DOTFILES_DIR")
  [ "$missing" -eq 0 ]
}

# config/kimi-code/tui.toml and (for a while) config/muxy/settings.json sat
# in the repo with no install path at all: not in links.sh, not merged by a
# config/*.sh script. Nothing installed them on a fresh machine and nothing
# said so. This walks every tracked config file and requires it be reachable
# some way, so a newly-added orphan fails loudly instead of sitting silent.
@test "every tracked config file is wired into an install path" {
  # Consumed directly by their own install/*.sh, not through links.sh.
  local handled="config/git/config"
  local known_gaps=""

  local sources
  sources=$(DOTFILES_DIR="$DOTFILES_DIR" bash -c '. "$0/install/links.sh"; all_links' "$DOTFILES_DIR" |
    cut -d'|' -f2)

  local file rel check covered missing=0
  while IFS= read -r file; do
    rel=${file#"$DOTFILES_DIR"/}
    [[ " $handled " == *" $rel "* ]] && continue
    [[ " $known_gaps " == *" $rel "* ]] && continue

    covered=1
    check="$rel"
    while :; do
      grep -qxF "$check" <<<"$sources" && {
        covered=0
        break
      }
      [[ "$check" == */* ]] || break
      check=${check%/*}
    done
    ((covered)) && {
      echo "orphaned config, wired into no install path: $rel"
      missing=1
    }
  done < <(git -C "$DOTFILES_DIR" ls-files 'config/*')
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

@test "profile-aware link selects individual components" {
  local home profile
  home="$(mktemp -d)"
  profile="$home/profile.json"
  printf '{"components":{"desktop-aerospace":true}}\n' >"$profile"
  HOME="$home" DOT_PROFILE="$profile" run "$DOT" link --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"config/aerospace/aerospace.toml"* ]]
  [[ "$output" != *"config/linearmouse/linearmouse.json"* ]]
}

# A name can cover several targets (ghostty -> ghostty + Muxy), and must not
# pull in unrelated configs.
@test "link <name> links only that config" {
  local home
  home="$(mktemp -d)"
  HOME="$home" run "$DOT" link ghostty --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"/config/ghostty/config"* ]]
  [[ "$output" != *"config/zsh/.zshrc"* ]]
}

@test "an unknown link target exits 1" {
  run "$DOT" link definitely-not-a-config
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such link"* ]]
}

# link is a standalone command now, so install must not swallow it silently.
@test "install link points at the standalone command" {
  run "$DOT" install link --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"dot link"* ]]
}

# A machine gets the agent CLIs from Homebrew and nothing else until asked, so
# no install phase may reach the ai/ manifests or an agent's own config.
@test "AI work never runs as part of an install phase" {
  local phase
  for phase in ai; do
    grep -q "for phase in .*\b$phase\b" "$DOT" && {
      echo "'$phase' is back in an install loop; ai/ must stay opt-in"
      return 1
    }
  done
  # Same rule for the instructions file: only `dot link agents` places it.
  run "$DOT" --dry-run link
  [ "$status" -eq 0 ]
  [[ "$output" != *"AGENTS.md"* ]]
}

# Skills default to the skills CLI, installed globally and unattended.
@test "AI skills install through the skills CLI" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' >"$stub/claude"
  chmod +x "$stub/claude"

  PATH="$stub:$PATH" run "$DOT" ai claude-code --skills --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--agent claude-code --global --yes"* ]]
  [[ "$output" != *"plugins for"* ]]
}

# Agents sharing the default skills CLI command collapse into one call per
# entry, with one --agent flag per agent.
@test "AI groups agents into one skills CLI call per entry" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' >"$stub/claude"
  printf '#!/bin/sh\nexit 0\n' >"$stub/codex"
  printf '#!/bin/sh\nexit 0\n' >"$stub/opencode"
  chmod +x "$stub/claude" "$stub/codex" "$stub/opencode"

  PATH="$stub:$PATH" run "$DOT" ai --skills --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"add mattpocock/skills --agent claude-code --agent codex --agent opencode --global --yes"* ]]
  [[ "$output" != *"mattpocock-skills"* ]]
}

# A vendor with several picked skills becomes one call with repeated --skill
# flags, and a single-skill vendor folds into the aggregator that hosts it.
@test "AI emits one skills CLI call per vendor with repeated --skill flags" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' >"$stub/claude"
  printf '#!/bin/sh\nexit 0\n' >"$stub/codex"
  printf '#!/bin/sh\nexit 0\n' >"$stub/opencode"
  chmod +x "$stub/claude" "$stub/codex" "$stub/opencode"

  PATH="$stub:$PATH" run "$DOT" ai --skills --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"add vercel-labs/agent-skills --skill vercel-composition-patterns --skill vercel-react-view-transitions --skill web-design-guidelines --agent claude-code --agent codex --agent opencode --global --yes"* ]]
  [[ "$output" == *"add vercel-labs/open-agents --skill agent-browser --skill vercel-react-best-practices --agent claude-code --agent codex --agent opencode --global --yes"* ]]
  [[ "$output" != *"add vercel-labs/agent-browser"* ]]
}

@test "AI skills remove a stale skills directory symlink" {
  local home stub
  home="$(mktemp -d)"
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' >"$stub/claude"
  chmod +x "$stub/claude"
  mkdir -p "$home/.claude"
  ln -s "$home/missing-skills" "$home/.claude/skills"

  HOME="$home" PATH="$stub:$PATH" run "$DOT" ai claude-code --skills --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"rm $home/.claude/skills"* ]]
}

@test "AI plugins install through the agent CLI" {
  local stub log
  stub="$(mktemp -d)"
  log="$stub/log"
  cat >"$stub/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$PLUGIN_LOG"
exit 0
EOF
  chmod +x "$stub/claude"

  PLUGIN_LOG="$log" PATH="$stub:$PATH" run "$DOT" ai claude-code --plugins
  [ "$status" -eq 0 ]
  grep -q '^plugin marketplace add DietrichGebert/ponytail$' "$log"
  grep -q '^plugin install ponytail@ponytail --scope user$' "$log"
  grep -q '^plugin install superpowers@claude-plugins-official --scope user$' "$log"
}

# Only the named agent's commands run, so an opencode-only plugin never reaches
# Claude Code and vice versa.
@test "AI installs only for the agent asked for" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' >"$stub/opencode"
  chmod +x "$stub/opencode"

  PATH="$stub:$PATH" run "$DOT" ai opencode --plugins --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"opencode plugin @tarquinen/opencode-dcp@latest --global"* ]]
  [[ "$output" != *"claude plugin"* ]]
}

# The default skill command runs through pnpm. Without this the run fails once
# per entry instead of saying what is wrong.
@test "AI stops when pnpm cannot be installed" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' >"$stub/claude"
  chmod +x "$stub/claude"
  ln -s "$(command -v jq)" "$stub/jq"

  PATH="$stub:/usr/bin:/bin" run /bin/bash "$DOT" ai claude-code --skills --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"pnpm is missing"* ]]
}

@test "AI installs pnpm through Homebrew when it is absent" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' >"$stub/claude"
  printf '#!/bin/sh\nexit 0\n' >"$stub/brew"
  chmod +x "$stub/claude" "$stub/brew"
  ln -s "$(command -v jq)" "$stub/jq"

  PATH="$stub:/usr/bin:/bin" run /bin/bash "$DOT" ai claude-code --skills --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew install pnpm"* ]]
}

@test "AI skips an agent whose CLI is missing" {
  local stub
  stub="$(mktemp -d)"
  ln -s "$(command -v jq)" "$stub/jq"
  PATH="$stub:/usr/bin:/bin" run /bin/bash "$DOT" ai claude-code --plugins
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-code: claude is not installed"* ]]
}

@test "AI rejects an unknown flag and an unknown agent" {
  run "$DOT" ai --nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: dot ai"* ]]

  run "$DOT" ai gemini
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown agent: gemini"* ]]
}

@test "AI install supports macOS system bash" {
  local stub
  stub="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' >"$stub/claude"
  chmod +x "$stub/claude"

  PATH="$stub:$PATH" run /bin/bash "$DOT" ai claude-code --skills --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--agent claude-code"* ]]
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

@test "app-writable config preserves a differing live file and warns" {
  local home repo source target common
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  source="$repo/config/claude/settings.json"
  target="$home/.claude/settings.json"
  common="$DOTFILES_DIR/install/common.sh"
  mkdir -p "$(dirname "$source")" "$(dirname "$target")"
  printf '%s\n' '{"tracked":true}' >"$source"
  printf '%s\n' '{"live":true}' >"$target"

  DOTFILES_DIR="$repo" HOME="$home" DRY_RUN=false \
    run bash -c '. "$1"; link_file config/claude/settings.json "$HOME/.claude/settings.json" app-writable' \
    _ "$common"

  # The live file is left in place, unchanged, and no symlink is created.
  [ "$status" -eq 0 ]
  [ ! -L "$target" ]
  [ "$(cat "$target")" = '{"live":true}' ]
  # The repo source is untouched — the app's copy wins, the backup is the
  # escape hatch.
  [ "$(cat "$source")" = '{"tracked":true}' ]
  # A backup of the live file exists under its home-relative path.
  [ "$(cat "$home"/.dotfiles-backup/*/.claude/settings.json)" = '{"live":true}' ]
}

@test "app-writable config silently leaves a matching live file alone" {
  local home repo source target common
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  source="$repo/config/claude/settings.json"
  target="$home/.claude/settings.json"
  common="$DOTFILES_DIR/install/common.sh"
  mkdir -p "$(dirname "$source")" "$(dirname "$target")"
  printf '%s\n' '{"tracked":true}' >"$source"
  printf '%s\n' '{"tracked":true}' >"$target"

  DOTFILES_DIR="$repo" HOME="$home" DRY_RUN=false \
    run bash -c '. "$1"; link_file config/claude/settings.json "$HOME/.claude/settings.json" app-writable' \
    _ "$common"

  [ "$status" -eq 0 ]
  [ ! -L "$target" ]
  [ "$(cat "$target")" = '{"tracked":true}' ]
  [ ! -d "$home/.dotfiles-backup" ]
}

@test "app-writable config links once the live file is gone" {
  local home repo source target common
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  source="$repo/config/claude/settings.json"
  target="$home/.claude/settings.json"
  common="$DOTFILES_DIR/install/common.sh"
  mkdir -p "$(dirname "$source")" "$(dirname "$target")"
  printf '%s\n' '{"tracked":true}' >"$source"

  DOTFILES_DIR="$repo" HOME="$home" DRY_RUN=false \
    run bash -c '. "$1"; link_file config/claude/settings.json "$HOME/.claude/settings.json" app-writable' \
    _ "$common"

  [ "$status" -eq 0 ]
  [ "$(readlink "$target")" = "$source" ]
  [ "$(cat "$target")" = '{"tracked":true}' ]
}

# check_link previously had no coverage at all: a stale or foreign symlink
# would never fail a test even though sub_doctor's whole job is to catch it.
# doctor used to check a hand-written subset of the link map, so drift in the
# rest went unseen.
@test "doctor checks every link in the map" {
  local home
  home="$(mktemp -d)"

  HOME="$home" run "$DOT" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"$home/.config/yazi/yazi.toml"* ]]
  [[ "$output" == *"$home/.config/lazygit/config.yml"* ]]
  # An app-writable target is a live file by design, never a symlink.
  [[ "$output" != *"herdr/config.toml"* ]]
}

@test "doctor reports a symlink that doesn't point into the repo" {
  local home
  home="$(mktemp -d)"
  ln -s /somewhere/else "$home/.zshrc"
  HOME="$home" run "$DOT" doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken: $home/.zshrc"* ]]
}

# The Makefile's SCRIPTS glob referenced system/macos/*.sh, a directory that
# never existed (the real one is system/defaults/); `make lint`/`make check`
# silently checked nothing under it and no test noticed.
@test "every Makefile SCRIPTS glob pattern matches a real file" {
  local scripts_line pattern
  scripts_line=$(grep '^SCRIPTS :=' "$DOTFILES_DIR/Makefile")
  scripts_line=${scripts_line#SCRIPTS := }
  for pattern in $scripts_line; do
    # shellcheck disable=SC2086
    compgen -G "$DOTFILES_DIR/$pattern" >/dev/null || {
      echo "SCRIPTS pattern matches nothing: $pattern"
      return 1
    }
  done
}
