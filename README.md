# Dotfiles

macOS dotfiles installed with Bash and Homebrew Bundle, driven by a single
`dot` command.

## Install

On a fresh machine, one line — clones to `~/.dotfiles` and installs:

```bash
curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash
```

It falls back to a tarball when git is not there yet, which is the case before
the Xcode command line tools are installed. Or clone it yourself:

```bash
git clone git@github.com:agustinzamar/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
bin/dot install
```

Clone to `~/.dotfiles`, or symlink it there: `system/.exports` puts
`~/.dotfiles/bin` on your `PATH`, so that is the path `dot` is found under once
the shell configs are linked and the shell has been restarted.

## Topics

Packages are grouped into topics under `install/topics/`. Each file is a
Brewfile and each is also a command:

```bash
dot media      # ffmpeg, imagemagick, vlc
dot laravel    # herd, dbngin
```

`dot brew` installs everything in `install/topics/`. Files in
`install/topics/optional/` are skipped, so a machine opts into them by name —
that is where `laravel` lives. Promoting or demoting a topic is a `git mv`.

Adding a topic means adding one file: it shows up in `dot help` and becomes a
command with no code change.

## Usage

`dot <command>`. Run `dot help` for the full list.

| Command | What it does |
| --- | --- |
| `install` | Everything below, in order (`macos` covers `dock`) |
| `brew` | Install Homebrew and every topic |
| `link` | Symlink every config into place |
| `link-shell` | Symlink the shell configs only |
| `unlink` | Remove symlinks that point into this repo |
| `zsh` | Install Oh My Zsh, its theme and plugins |
| `tools` | Install what Homebrew Bundle does not cover |
| `code` | Install the VS Code extensions in `install/Codefile` |
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

`make` targets (`install`, `link`, `unlink`, `update`, `doctor`, `backup`,
`test`, `check`, `lint`) are thin aliases for the same commands.

## Layout

- `bin/dot` — the CLI; one `sub_<command>` function per command, plus
  whatever `install/topics/` holds
- `install/common.sh` — `run`, `log`, `link_file`; the only copies
- `install/topics/` — one Brewfile per package group; each is also a command.
  `optional/` holds the ones `dot brew` skips
- `install/` — the other package lists (`Codefile`, `duti`) plus
  the per-topic install steps
- `config/` — application configuration
- `system/` — shell aliases, functions, exports, `env/`, `completions/`, `macos/`
- `remote-install.sh` — one-line bootstrap for a fresh machine
- `test/` — Bats tests

The package lists are plain data: one entry per line, `#` comments ignored.
Adding a package is a one-line diff.

`install/*.sh` and `system/macos/*.sh` are sourced by `bin/dot`, not executed
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

No secret is written to disk. `config/opencode/opencode.json` passes
`{env:GITHUB_PAT}` to the shadcn MCP server, which OpenCode expands from the
environment at runtime — export it from wherever you keep it. Unset, the server
runs without a GitHub token.

`~/.dotfiles-custom/shell/` is sourced if present, for anything that should not
be committed.
