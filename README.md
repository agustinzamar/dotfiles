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
[`remote-install.sh`](remote-install.sh) before you pipe it — it is 67 lines —
or skip the pipe entirely and clone, which does the same work:

```bash
git clone git@github.com:agustinzamar/dotfiles.git ~/dotfiles
cd ~/dotfiles
bin/dot install
```

`system/.exports` puts `~/dotfiles/bin` on your `PATH`, so `dot` is available
once the shell configs are linked and the shell has been restarted. A bare
`make` runs the full install.

## Server (Linux/VPS)

A separate one-liner installs only a lean zsh setup on a remote box — zsh,
Oh My Posh (using the same `theme.omp.json` as the desktop config), and native
completions. No Homebrew, TUI, zinit, or macOS aliases are touched:

```bash
curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install-server.sh | bash
```

It detects `apt`, `dnf`, `yum`, `pacman`, or `apk` to install `zsh`, and uses
the official script to install Oh My Posh into `~/.local/bin`. Existing
`~/.zshrc` and theme are backed up to `~/.dotfiles-backup/<timestamp>/` first.
Re-running is safe. The script asks before changing your default shell, and
never does so non-interactively. Pin a branch with `DOTFILES_REF`.

Bare `dot install` (and bare `make`) opens the **interactive installer** and
needs a TTY. Scripted or CI installs, or piping the one-liner without flags,
should use the headless paths instead — bare `dot install` under non-TTY stdin
fails fast and says so:

```bash
dot install --all          # headless: every standard phase (AI stays opt-in)
dot install --profile dev  # headless: apply a saved profile
```

On a truly fresh machine the installer bootstraps what it needs (Xcode CLT,
Homebrew, then Bun if the prebuilt binary is missing) before opening.

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
| `install` | Opens the interactive installer (tools, then config links) — requires a TTY |
| `install --all` | Install every standard phase headlessly (AI stays opt-in) |
| `install --profile PATH` | Apply a saved component profile without the TUI |
| `link` | Repair links selected in `~/.config/dot/profile.json` |
| `link --all` | Force-link every valid config explicitly |
| `link <name>` | Force-link one config (`ghostty`, `tmux`, `yazi`, …) |
| `ai [agent]` | Install AI skills and plugins (opt-in, never part of `install`) |
| `unlink` | Remove symlinks that point into this repo |
| `doctor` | Check required tools and symlinks |
| `update` | Pull this repo, re-link configs, then upgrade packages (`topgrade`, else `brew`) |
| `test` | Run the Bats suite |

Every command accepts `--dry-run`, which prints what would run and touches
nothing:

```bash
dot install --dry-run
dot link --dry-run
dot install --dry-run --profile ~/.config/dot/profile.json
```

### The installer (two steps)

The installer has two steps. **Step 1** lists every package as its own row,
grouped visually by topic: a locked essentials block is pinned at the top
(shell + git setup, `fzf`/`git`/`gh`/`tmux`) and is always installed; the rest
are individually toggleable, with the former baseline tools
(`lazygit`, `hunk`, `yazi`, `neovim`, Ghostty) pre-checked. **Step 2** offers
exactly the config links that belong to the tools you selected, all unchecked,
plus a final opt-in `agents` group. Press Enter to install the selected tools,
link the checked configs, and finish. Press `q` anywhere before confirming to
abort — nothing is installed and nothing is linked.

The profile at `~/.config/dot/profile.json` stores the selected *areas*
(what `dot link` / `dot update` gate on); link choices are applied once and are
not persisted. Successful work is not repeated during the same session, and
deselecting an installed app never uninstalls it or removes its config link.

A bare `make` is the one-shot first init (`dot install`). The Makefile also
carries `make test`, `make check` and `make lint`, which CI runs.

## The installer binary

The interactive installer and `dot install --profile` run a compiled binary,
`bin/dot-tui`. The prebuilt binary is used if present; otherwise `bin/dot`
builds it from source with Bun at least at the version pinned in
[`.bun-version`](.bun-version), or prints guidance pointing back to the
bootstrap one-liner above. Neither path requires a language toolchain at
runtime. The TUI reads its package list from `install/manifest.sh`'s emitted
context JSON — the same files the headless topics install and `dot link` use,
so interactive and scripted installs cannot diverge.

Contributors who want to build or test the installer locally can install Bun
with `brew install bun` and run `make build-tui` / `make bun-test`.

## Layout

- `bin/dot` — the CLI; one `sub_<command>` function per command, plus
  whatever `install/topics/` holds
- `install/common.sh` — `run`, `log`, `link_file`; the only copies
- `install/topics/` — one Brewfile per package group; each is also a command.
- `install/*.sh` — the per-topic install steps
- `config/` — application configuration
- `system/` — shell aliases and functions, exports, `env/`, `completions/`, `defaults/`
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
