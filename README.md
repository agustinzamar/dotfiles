# Dotfiles

macOS and Ubuntu dotfiles installed with Bash, driven by a single `dot`
command. macOS installs through Homebrew Bundle; Ubuntu installs through apt
plus official upstream installers (see `install/debian.sh`).

## Install

On a fresh machine, one line — clones to `~/dotfiles` and installs:

```bash
curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash -s -- --all
```

The trailing `--all` runs the headless full install (no interaction). It falls
back to a tarball when git is not there yet — before the Xcode command line
tools on macOS, or before `sudo apt-get install -y git curl` on Ubuntu
(which the bootstrap tries first when sudo is available).

That line runs whatever `main` serves at that moment. Open
[`remote-install.sh`](remote-install.sh) before you pipe it — or skip the pipe
entirely and clone, which does the same work:

```bash
git clone git@github.com:agustinzamar/dotfiles.git ~/dotfiles
cd ~/dotfiles
bin/dot install --all     # headless; bare `bin/dot install` needs a TTY
```

`config/zsh/.zshrc` puts `~/dotfiles/bin` on your `PATH`, so `dot` is available
once the shell configs are linked and the shell has been restarted. A bare
`make` shows available targets; `make install` runs the full interactive
installer.

Bare `dot install` (and bare `make install`) opens the **interactive
installer** and needs a TTY. Scripted or CI installs, or piping the one-liner
without flags, should use the headless path instead — bare `dot install` under
non-TTY stdin fails fast and says so:

```bash
dot install --all          # headless: every standard phase (AI stays opt-in)
```

On a truly fresh machine the installer bootstraps what it needs (Xcode CLT +
Homebrew on macOS; apt essentials + zsh on Ubuntu) before opening.

### Ubuntu

`dot install --all` on Debian/Ubuntu installs the basics headlessly:

- shell: `zsh` (set as default via `chsh`), `zinit`, `fzf`, `zoxide`, `eza`,
  `oh-my-posh` prompt with the tracked theme
- git stack: `git`, `gh`, `lazygit`, tracked git config + credential helper
- terminal tools: `ripgrep`, `bat` (`batcat` shim), `fd` (`fdfind` shim),
  `jq`, `yq`, `btop`, `yazi`, `superfile` (`spf`), `neovim`, `ghostty`,
  `topgrade`, `pay-respects`, `jless`, `dust`
- dev: `go`, `mise`, `python3`, `pipx`, `rust`, `php` + `composer`,
  `shellcheck`, `shfmt`, `opencode` (official installer)
- configs linked: `.zshrc`, `oh-my-posh`, `ghostty`, `yazi`, `git`, `mise`,
  plus `vscode` at `~/.config/Code/User/` and `superfile` at
  `~/.config/superfile/` (XDG homes, not `~/Library`)

macOS-only pieces are skipped with a note (`sketchybar`, `linearmouse`,
`rectangle`, `duti`, `dockutil`, `orbstack`, macOS casks). VS Code extensions
install with `dot install code` once `code` exists (snap or the Microsoft
`.deb`). `dot doctor` stays green without Homebrew.

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
| `link` | Repair links for the baseline components (base/shell/git/terminal) |
| `link --all` | Force-link every valid config explicitly |
| `link <name>` | Force-link one config (`ghostty`, `paneru`, `yazi`, …) |
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
```

### The installer (two steps)

The installer has two steps. **Step 1** lists every package as its own row,
grouped visually by topic: a locked essentials block is pinned at the top
(shell + git setup, `fzf`/`git`/`gh`) and is always installed; the rest
are individually toggleable, with the former baseline tools
(`lazygit`, `hunk`, `yazi`, `neovim`, Ghostty) pre-checked. **Step 2** offers
exactly the config links that belong to the tools you selected, all unchecked,
plus a final opt-in `agents` group. Press Enter to install the selected tools,
link the checked configs, and finish. Press `q` anywhere before confirming to
abort — nothing is installed and nothing is linked.

`dot link` / `dot update` gate on the static baseline (base/shell/git/terminal
on, everything else opt-in); link choices are applied once and are
not persisted. Successful work is not repeated during the same session, and
deselecting an installed app never uninstalls it or removes its config link.

A bare `make` shows available targets (`help` is the default). `make install`
runs the first-init entry point (`dot install`). The Makefile also carries
`make test`, `make check` and `make lint`, which CI runs.

## The installer binary

The interactive installer runs a compiled binary, `bin/dot-tui`. The prebuilt binary is used if present; otherwise `bin/dot`
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

Shell configuration is loaded directly from `~/dotfiles/system/`. Tool-gated
snippets live in `config/zsh/exports/` and reach the shell only once `dot link`
symlinks them into `~/.config/zsh/exports/` — the requirement column in
`install/links.sh` decides whether the tool is installed. `~/.dotfiles-custom/`
is sourced if present, for anything that should not be committed.
