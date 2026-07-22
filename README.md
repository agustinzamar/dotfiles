# Dotfiles

Personal dotfiles managed by a Go CLI. Interactive TUI installer with checkboxes — pick which tools to install. Adding a new tool is a few lines of YAML. Fully idempotent.

## Key Features

- **Interactive TUI** — Bubble Tea checklist, check/uncheck tools before install
- **Data-driven** — All tools declared in `config/tools.yaml`, no per-tool Go code
- **Generic Step Engine** — 9 step types (brew, cask, symlink, template, git-clone, vscode, omz-plugin, tap, run)
- **Template Rendering** — Go templates for sensitive configs (git, opencode), rendered outputs gitignored
- **Private Configs** — `~/.dotfiles-custom/shell/` loaded by `.zshrc`, never committed
- **Symlink Engine** — Idempotent, backs up existing files before overwriting
- **Single Binary** — `go build` produces one static arm64 binary

## Quick Start

```bash
# Clone
git clone git@github.com:agustinzamar/dotfiles.git ~/Documents/repos/dotfiles
cd ~/Documents/repos/dotfiles

# Build and install to PATH
make install

# Interactive install
dotfiles install

# Or non-interactive: install everything
dotfiles install --all

# Update everything later
dotfiles update
```

`dotfiles` runs from anywhere — no need to be inside the repo.

## Commands

| Command | Description |
|---------|-------------|
| `dotfiles install` | Launch interactive TUI with category checklist |
| `dotfiles install --all` | Non-interactive batch install of all tools |
| `dotfiles install --all --dry-run` | Preview what would be installed |
| `dotfiles update` | `git pull` + `brew update && brew upgrade` + re-sync symlinks |
| `dotfiles list` | List all available tools in the manifest |
| `dotfiles doctor` | Check health of installed tools and symlinks |
| `dotfiles cleanup` | Remove `.backup` files from symlink operations |
| `dotfiles backup` | Mackup sync + commit & push dotfiles changes |

## What's Included

### Core
- **Xcode CLT** — Command Line Tools (git, compilers, etc.)
- **Homebrew** — Package manager
- **SSH Keychain** — Auto-loads SSH keys into Apple Keychain so you never type your passphrase

### Shell
- **Oh My Zsh** — Zsh framework with custom `.zshrc`
- **Powerlevel10k** — Prompt theme (robbyrussell style)
- **zsh-autosuggestions** — Fish-like autosuggestions
- **fzf-tab** — Fuzzy tab completion
- **fast-syntax-highlighting** — Syntax highlighting in shell
- **bash** — Modern Bourne-Again Shell
- **Shell Aliases & Functions** — Custom aliases and shell functions

### Terminal
- **Ghostty** — Terminal emulator with Catppuccin theme
- **Muxy** — Terminal multiplexer
- **tmux** — Terminal multiplexer

### CLI Tools
- **bat** — Cat with syntax highlighting
- **eza** — Modern ls with icons
- **fzf** — Fuzzy finder
- **zoxide** — Smart directory jumping
- **ripgrep** — Fast grep
- **fd** — Fast find
- **hunk** — Review-first terminal diff viewer
- **jq** — JSON processor
- **yq** — YAML processor
- **bottom** — System monitor
- **direnv** — Per-directory env vars
- **unar** — Multi-format unarchiver
- **yazi** — Terminal file manager
- **sshpass** — Non-interactive SSH auth
- **MySQL Client** — MySQL database CLI
- **mole** — SSH tunneling CLI tool
- **opentmux** — tmux session manager wrapper
- **rendercv** — LaTeX-based CV/resume renderer

### Development
- **Herd** — Laravel dev environment
- **DBngin** — Database manager
- **OrbStack** — Docker & Linux VMs
- **Composer** — PHP package manager
- **mysql-to-sqlite3** — MySQL to SQLite converter
- **sqlite3** — SQLite CLI
- **pipx** — Python package runner
- **Go** — Go programming language
- **.npmrc** — npm configuration

### Git & GitHub
- **gh** — GitHub CLI
- **Git Config** — `.gitconfig` with hunk pager + gh auth (Go template)

### Editors
- **VS Code** — Settings + keybindings + extensions
- **PhpStorm** — JetBrains PHP IDE

### AI Tools
- **Claude Code** — Claude AI coding agent (config + skills + agents synced)
- **Opencode** — OpenCode AI coding agent (config + plugins/skills/themes/agents/commands synced)
- **Google Antigravity** — Agent orchestration platform
- **Grok Build CLI** — Grok coding agent CLI

### macOS Defaults
- **Finder** — Show all extensions, pathbar, full path in title
- **Dock** — Autohide, no recents, left position
- **Screenshots** — PNG format, save to Desktop
- **Text & Input** — Fast key repeat, always show scrollbars
- **Misc** — No .DS_Store on network stores, disable Handoff

### Utilities
- **mackup** — Backup sensitive configs (SSH, shell aliases) to cloud storage
- **Finetune** — Per-app volume mixer
- **Boring Notch** — Notch customization utility
- **Raycast** — App launcher and productivity tool
- **TypeWhisper** — Speech-to-text transcription tool
- **AltTab** — Window switcher with previews
- **Spotify** — Music streaming player

### Backup & Sync
- **mackup** — Backup app configs

## How It Works

### Symlinked Files

The installer creates symlinks from your home directory to the dotfiles repository config files:

| Symlink Location | Points To | Purpose |
|-----------------|-----------|---------|
| `~/.zshrc` | `~/.dotfiles/config/zsh/.zshrc` | Zsh configuration |
| `~/.p10k.zsh` | `~/.dotfiles/config/p10k/.p10k.zsh` | Powerlevel10k theme |
| `~/.gitconfig` | Rendered template | Git config with hunk pager + gh auth |
| `~/.npmrc` | `~/.dotfiles/config/npm/.npmrc` | npm configuration |
| `~/.config/ghostty/config` | `~/.dotfiles/config/ghostty/config` | Ghostty terminal settings |
| `~/.config/tmux/tmux.conf` | `~/.dotfiles/config/tmux/tmux.conf` | tmux configuration |
| `~/.config/hunk/config.toml` | `~/.dotfiles/config/hunk/config.toml` | Hunk diff viewer settings |
| `~/.config/yazi/yazi.toml` | `~/.dotfiles/config/yazi/yazi.toml` | Yazi file manager settings |
| `~/.claude/settings.json` | `~/.dotfiles/config/claude/settings.json` | Claude Code settings |
| `~/.claude/skills/` | `~/.dotfiles/config/claude/skills/` | Claude Code skills (version-controlled) |
| `~/.claude/agents/` | `~/.dotfiles/config/claude/agents/` | Claude Code agents (version-controlled) |
| `~/.claude/CLAUDE.md` | `~/.dotfiles/config/claude/CLAUDE.md` | Claude Code config |
| `~/.config/opencode/opencode.json` | Rendered template | OpenCode config |
| `~/.config/opencode/AGENTS.md` | `~/.dotfiles/config/opencode/AGENTS.md` | OpenCode agents config |
| `~/.config/opencode/plugins/` | `~/.dotfiles/config/opencode/plugins/` | OpenCode plugins |
| `~/.config/opencode/skills/` | `~/.dotfiles/config/opencode/skills/` | OpenCode skills |
| `~/.config/opencode/themes/` | `~/.dotfiles/config/opencode/themes/` | OpenCode themes |
| `~/.config/opencode/agents/` | `~/.dotfiles/config/opencode/agents/` | OpenCode agents |
| `~/.config/opencode/commands/` | `~/.dotfiles/config/opencode/commands/` | OpenCode commands |
| VSCode settings | `~/Library/Application Support/Code/User/settings.json` | VS Code settings |
| VSCode keybindings | `~/Library/Application Support/Code/User/keybindings.json` | VS Code keybindings |

### Sourced Files

These files are loaded by `.zshrc` but remain in the dotfiles directory:

- `home/.aliases` — Shell command aliases (Laravel, Git, Composer shortcuts)
- `home/.functions` — Custom shell functions (pest, clone, git-prune, etc.)
- `home/.exports` — Environment variables (PATH, EDITOR, etc.)

### Step Types

| Step | What it does | Skip check |
|------|-------------|------------|
| `brew` | `brew install <package>` | `which <bin>` |
| `cask` | `brew install --cask <package>` | Checks `/Applications/<app>.app` |
| `tap` | `brew tap <repo>` | Checks `brew tap` output |
| `vscode` | `code --install-extension <ext>` | Checks `code --list-extensions` |
| `omz-plugin` | `git clone --depth=1 <repo>` to OMZ plugins | Checks directory exists |
| `symlink` | Backup existing + `ln -sf <from> <to>` | Checks symlink target matches |
| `template-symlink` | Render Go template with vars, then symlink | Checks rendered file matches |
| `git-clone` | `git clone --depth=N <repo> <dest>` | Checks dest exists |
| `run` | Execute shell command | `skip:` command exits 0 if done |
| `defaults` | `defaults write <domain> <key> -<type> <value>` | `defaults read` matches expected value |

## Adding a New Tool

Edit `config/tools.yaml`:

```yaml
  - name: "New Tool"
    description: "What it does"
    checked: true
    steps:
      - type: brew
        package: newtool
      - type: symlink
        from: "config/newtool/config"
        to: "${HOME}/.config/newtool/config"
```

Add config files to `config/newtool/`. That's it — no Go code changes needed.

## Template Variables

Some configs use Go templates with variables stored in `~/.dotfiles-custom/vars.json`:

- **GitName**, **GitEmail** — Git user identity
- **GitGPGKey** — GPG key ID for commit signing (optional; leave empty to skip)
- **GitHubPAT** — GitHub personal access token (for OpenCode MCP server)

These are prompted on first install and cached. Delete `~/.dotfiles-custom/vars.json` to re-prompt.

## Sensitive Data Handling

- `~/.dotfiles-custom/vars.json` is created with `0600` permissions (owner read/write only) and never leaves your machine
- Rendered config files containing sensitive values (e.g. `opencode.rendered.json`, `.gitconfig.rendered`) are gitignored via `*.rendered.*` patterns in `.gitignore`
- The `~/.dotfiles-custom/` directory is outside the repo and never committed
- `dotfiles backup` uses Mackup to sync `dotfiles-custom` to cloud storage for cross-machine backup

## Customization

### Private Aliases, Functions, Exports

Create custom configurations that won't be committed:

```bash
mkdir -p ~/.dotfiles-custom/shell
echo 'alias myserver="ssh user@my.server.com"' > ~/.dotfiles-custom/shell/.aliases
```

These files are automatically loaded by `.zshrc` if they exist:
- `~/.dotfiles-custom/shell/.aliases`
- `~/.dotfiles-custom/shell/.functions`
- `~/.dotfiles-custom/shell/.exports`
- `~/.dotfiles-custom/shell/.zshrc`

### Project-Specific Variables

Use `direnv` for automatic environment loading:

```bash
cd my-project
echo 'export DEBUG=true' > .envrc
direnv allow
```

## Daily Usage

### Laravel/PHP Shortcuts

```
ar        php artisan
mfs       php artisan migrate:fresh --seed
pest      ./vendor/bin/pest
pint      ./vendor/bin/pint
p         Run Pest/PHPUnit tests
pestf     Run filtered test
pestp     Run parallel tests
cu        composer update
cr        composer require
ci        composer install
cda       composer dump-autoload -o
```

### Git Shortcuts

```
nah       git reset --hard; git clean -df
push      git push
pull      git pull
gpo       git push origin
uncommit  git reset --soft HEAD~1
```

### Navigation

```
z dotfiles          Jump to frequently used directories
cd                  Actually runs zoxide's z
ls                  eza with icons
ll                  eza with git status
lt                  eza tree view
```

## Tech Stack

- **[Go 1.22+](https://go.dev/)** — Single static binary
- **[Cobra](https://github.com/spf13/cobra)** — CLI framework
- **[Bubble Tea](https://github.com/charmbracelet/bubbletea) + [Bubbles](https://github.com/charmbracelet/bubbles) + [Lipgloss](https://github.com/charmbracelet/lipgloss)** — Interactive TUI with Catppuccin theme
- **[YAML](https://pkg.go.dev/gopkg.in/yaml.v3) (gopkg.in/yaml.v3)** — Tool manifest
- **Go templates** — Config file rendering

## Credits

Created by Agustin Zamar. Inspired by [freekmurze/dotfiles](https://github.com/freekmurze/dotfiles).
