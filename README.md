# Dotfiles

macOS dotfiles installed with Bash and Homebrew Bundle, driven by a single
`dot` command.

## Install

On a fresh machine, one line — clones to `~/dotfiles` and installs:

```bash
curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash
```

It falls back to a tarball when git is not there yet, which is the case before
the Xcode command line tools are installed.

That line runs whatever `main` serves at that moment. Open
[`remote-install.sh`](remote-install.sh) before you pipe it — it is 37 lines —
or skip the pipe entirely and clone, which does the same work:

```bash
git clone git@github.com:agustinzamar/dotfiles.git ~/dotfiles
cd ~/dotfiles
bin/dot install
```

`system/.exports` puts `~/dotfiles/bin` on your `PATH`, so `dot` is available
once the shell configs are linked and the shell has been restarted. A bare
`make` runs the full install.

## Topics

Packages are grouped into topics under `install/topics/`. Each file is a
Brewfile and each is also a command:

```bash
dot dev                            # installs install/topics/dev
```

`dot brew` installs every topic in `install/topics/`. Each topic is also a
command with no additional code. Promoting or demoting a topic is a `git mv`.

Adding a topic means adding one file: it becomes a command with no code
change, and `dot help` names it on the `install <topic>` line.

## AI agents

Homebrew installs the agent CLIs (`install/topics/dev`). Everything they load on
top lives in `ai/` and is opt-in: no install phase writes an agent's config,
adds a plugin, or links the instructions file.

| Path | What it holds |
| --- | --- |
| `ai/AGENTS.md` | One instructions file for every agent |
| `ai/skills.json` | Skill packages, by default installed with the skills CLI |
| `ai/plugins.json` | Plugins, one command per agent |
| `ai/skills/` | Single-file skills tracked here, linked into Claude Code |

Every skill entry installs once for every agent that wants it. Entries that
share a source and the default command collapse into one skills CLI call with
repeated `--skill` and `--agent` flags. An entry can instead name a per-agent
command, because the same upstream sometimes ships as a skill package for one
CLI and as a plugin for another:

```json
{ "source": "shadcn/ui",
  "skill": "shadcn",
  "install": { "claude-code": "claude plugin install superpowers" } }
```

`install.<agent>` overrides the default command; `agents` narrows which agents
want the entry at all. Every command installs globally and unattended, and each
CLI is idempotent, so these are safe to re-run:

```bash
dot ai                             # every agent CLI found on this machine
dot ai opencode --plugins          # one agent, plugins only
dot link agents                    # point the agents at ai/AGENTS.md
dot claude_config                  # merge Claude Code defaults
```

An `install` value is a shell command, run as you, with network access. That
makes these two files the trust boundary of this repo — more than the install
one-liner, which only fetches code you can read here. Read every command you
paste in, from a README or anywhere else, and treat a change to them like a
change to a script, not like a change to a config value.

## Usage

`dot <command>`. Run `dot help` for the full list.

| Command | What it does |
| --- | --- |
| `install` | Everything below, in order (`macos` covers `dock`) |
| `tui` | Select baseline and optional components in the Bubble Tea installer |
| `install --profile PATH` | Apply a saved component profile without the TUI |
| `brew` | Install Homebrew and every topic |
| `link` | Link selected components from `~/.config/dot/profile.json` |
| `link --all` | Link every valid config explicitly |
| `link <name>` | Symlink one config (`ghostty`, `tmux`, `yazi`, …) |
| `ai [agent]` | Install AI skills and plugins (opt-in, never part of `install`) |
| `unlink` | Remove symlinks that point into this repo |
| `zsh` | Run the fzf key-binding installer (zinit loads the plugins from `.zshrc`) |
| `code` | Install the VS Code extensions in `install/topics/code` |
| `duti` | Set default apps for file types |
| `macos` | Apply macOS system defaults |
| `dock` | Apply Dock settings |
| `doctor` | Check required tools and symlinks |
| `update` | Pull this repo, re-link configs, then upgrade packages (`topgrade`, else `brew`) |
| `backup` | Commit and push this repo |
| `clean` | Clean up caches |
| `edit` | Open this repo in `$VISUAL` |
| `test` | Run the Bats suite |

Every command accepts `--dry-run`, which prints what would run and touches
nothing:

```bash
dot install --dry-run
dot link --dry-run
dot install --dry-run --profile ~/.config/dot/profile.json
```

The TUI selects Base, Shell, Git, and Terminal by default. Go is required and
cannot be disabled. Optional PHP, Laravel, AI, desktop, communication, media,
editor, and service components start unselected. Selections persist in the
machine-local profile at `~/.config/dot/profile.json`.

A bare `make` is the one-shot first init (`dot install`). The Makefile also
carries `make test`, `make check` and `make lint`, which CI runs.

## Layout

- `bin/dot` — the CLI; one `sub_<command>` function per command, plus
  whatever `install/topics/` holds
- `install/common.sh` — `run`, `log`, `link_file`; the only copies
- `install/topics/` — one Brewfile per package group; each is also a command.
- `install/*.sh` — the per-topic install steps
- `config/` — application configuration
- `system/` — shell aliases, functions, exports, `env/`, `completions/`, `defaults/`
- `remote-install.sh` — one-line bootstrap for a fresh machine
- `test/` — Bats tests

The package lists are plain data: one entry per line, `#` comments ignored.
Adding a package is a one-line diff.

`install/*.sh` and `system/defaults/*.sh` are sourced by `bin/dot`, not executed
directly. They read `DOTFILES_DIR` and `DRY_RUN` from the environment.

Adding a command means adding one `sub_*` function and one line in `sub_help`;
the test suite checks the two stay in sync. A topic needs neither — the
dispatcher falls through to `install/topics/<name>`.

## Notes

The installer is idempotent. A file it replaces is moved to
`~/.dotfiles-backup/<timestamp>/`, keeping its path below `$HOME` so that
same-named files do not collide.

Git identity is committed in `config/git/config`; nothing is generated or
prompted for.

Shell configuration is loaded directly from `~/dotfiles/system/`.
`~/.dotfiles-custom/` is sourced if present, for anything that should not be
committed.
