# Dotfiles

macOS dotfiles installed with Bash and Homebrew Bundle.

## Install

```bash
git clone git@github.com:agustinzamar/dotfiles.git ~/Documents/repos/dotfiles
cd ~/Documents/repos/dotfiles
./install.sh
```

Options:

```bash
./install.sh --profile personal
./install.sh --profile work
./install.sh --only shell
./install.sh --dry-run
```

`Brewfile` contains shared packages. `Brewfile.personal` contains the
personal-only packages. The installer is idempotent and backs up replaced
files under `~/.dotfiles-backup/<timestamp>`.

## Maintenance

```bash
scripts/update.sh "$PWD"
scripts/doctor.sh "$PWD"
scripts/backup.sh "$PWD"
```

`backup.sh` runs Mackup, commits repository changes, and pushes them.

## Layout

- `config/` — application configuration
- `home/` — shell aliases, functions, and exports
- `Brewfile*` — Homebrew packages and VS Code extensions
- `install.sh` — installation coordinator
- `scripts/` — focused installation and maintenance actions

Private values are stored in `~/.dotfiles-custom/vars.json` with mode `0600`.
Generated Git and OpenCode configs stay ignored by Git.
