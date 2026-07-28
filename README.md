# Dotfiles

macOS dotfiles installed with Bash and Homebrew Bundle, driven by a single
`dot` command.

## Install

```bash
git clone git@github.com:agustinzamar/dotfiles.git ~/Documents/repos/dotfiles
cd ~/Documents/repos/dotfiles
bin/dot install
```

On a personal machine, follow up with the personal-only packages:

```bash
bin/dot brew-personal
```

`system/.exports` puts `~/.dotfiles/bin` on your `PATH`, so `dot` works from
anywhere once the shell configs are linked and the shell has been restarted.

## Usage

`dot <command>`. Run `dot help` for the full list.

| Command | What it does |
| --- | --- |
| `install` | Everything below, in order |
| `brew` | Install Homebrew, the formulae and the casks |
| `brew-personal` | Install the personal-only package set |
| `link` | Symlink every config into place |
| `link-shell` | Symlink the shell configs only |
| `unlink` | Remove symlinks that point into this repo |
| `zsh` | Install Oh My Zsh, its theme and plugins |
| `tools` | Install what Homebrew Bundle does not cover |
| `npm` | Install the global packages in `install/npmfile` |
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

`make` targets (`install`, `link`, `update`, `doctor`, `backup`, `test`,
`check`, `lint`) are thin aliases for the same commands.

## Layout

- `bin/dot` — the CLI; one `sub_<command>` function per command
- `install/common.sh` — `run`, `log`, `link_file`; the only copies
- `install/` — package lists (`Brewfile`, `Caskfile`, `Codefile`, `npmfile`,
  `duti`) plus the per-topic install steps
- `config/` — application configuration
- `system/` — shell aliases, functions, exports, and `macos/`
- `test/` — Bats tests

The package lists are plain data: one entry per line, `#` comments ignored.
Adding a package is a one-line diff.

`install/*.sh` and `system/macos/*.sh` are sourced by `bin/dot`, not executed
directly. They read `DOTFILES_DIR` and `DRY_RUN` from the environment.

Adding a command means adding one `sub_*` function and one line in `sub_help`;
the test suite checks the two stay in sync.

## Notes

The installer is idempotent. A file it replaces is moved to
`~/.dotfiles-backup/<timestamp>/`, keeping its path below `$HOME` so that
same-named files do not collide.

Private values live in `~/.dotfiles-custom/vars.json` with mode `0600`.
Generated Git and OpenCode configs stay ignored by Git.
