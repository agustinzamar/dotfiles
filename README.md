# Dotfiles

macOS dotfiles installed with Bash and Homebrew Bundle, driven by a single
`dot` command.

## Install

On a fresh machine, one line — clones to `~/dotfiles` and installs:

```bash
curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash
```

It falls back to a tarball when git is not there yet, which is the case before
the Xcode command line tools are installed. Or clone it yourself:

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

Homebrew installs the agent CLIs (`install/topics/ai`). Everything they load on
top lives in `ai/` and is opt-in: no install phase writes an agent's config,
adds a plugin, or links the instructions file.

| Path | What it holds |
| --- | --- |
| `ai/AGENTS.md` | One instructions file for every agent |
| `ai/skills.json` | Skill packages, by default installed with the skills CLI |
| `ai/plugins.json` | Plugins, one command per agent |
| `ai/skills/` | Skills written here rather than pulled from a package |

An entry can install differently per agent, because the same upstream ships as
a skill package for one CLI and as a plugin for another:

```json
{ "source": "mattpocock/skills",
  "install": { "claude-code": "claude plugin install mattpocock-skills" } }
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

## Usage

`dot <command>`. Run `dot help` for the full list.

| Command | What it does |
| --- | --- |
| `install` | Everything below, in order (`macos` covers `dock`) |
| `brew` | Install Homebrew and every topic |
| `link` | Symlink every config into place |
| `link <name>` | Symlink one config (`ghostty`, `tmux`, `yazi`, …) |
| `ai [agent]` | Install AI skills and plugins (opt-in, never part of `install`) |
| `unlink` | Remove symlinks that point into this repo |
| `zsh` | Install Oh My Zsh, its theme and plugins |
| `code` | Install the VS Code extensions in `install/topics/code` |
| `duti` | Set default apps for file types |
| `macos` | Apply macOS system defaults |
| `dock` | Apply Dock settings |
| `doctor` | Check required tools and symlinks |
| `update` | Pull, upgrade packages, re-run the install |
| `backup` | Commit and push this repo |
| `clean` | Clean up caches |
| `edit` | Open this repo in `$VISUAL` |
| `test` | Run the Bats suite |

Every command accepts `--dry-run`, which prints what would run and touches
nothing:

```bash
dot install --dry-run
dot link --dry-run
```

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
