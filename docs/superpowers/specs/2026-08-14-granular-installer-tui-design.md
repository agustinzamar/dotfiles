# Granular Installer TUI Design

## Goal

Add a Bubble Tea interface that installs a mandatory baseline and independently
selected optional components. Persist selections per machine and link only the
configurations selected for applications available on that machine.

## Scope

The first version changes installation selection and linking. It keeps the
existing shell CLI as the bootstrap and compatibility layer. It adds a Go
Bubble Tea application for interactive selection and execution.

The first version does not add parallel execution, rollback, remote profiles,
or a plugin system.

## User Model

The TUI has no broad developer, work, or personal presets. It presents two
groups of independent components:

### Baseline

Baseline components are selected on a new machine:

- Base: Xcode command line tools, Homebrew, and Go.
- Shell: Zsh, Zinit, fzf setup, p10k, plugins, aliases, and completions.
- Git: Git config, GitHub CLI, Lazygit, Delta, and Hunk.
- Terminal: Ghostty, tmux, Yazi, and Neovim.

Go is required by the new CLI and cannot be deselected. Other baseline items
remain selected by default and can be adjusted before execution.

### Optional Components

Optional components start unselected and remain independent:

- PHP tooling.
- Laravel tooling.
- Databases and services.
- AI CLIs, skills, plugins, and related configuration.
- Desktop applications.
- Communication applications.
- Media applications.
- Editors and editor extensions.

Adding an optional component must not select unrelated components in its
category.

## Persistence

The active machine profile is stored at:

```text
~/.config/dot/profile.json
```

The profile stores component IDs and their selected state. It does not store
detected paths, command output, credentials, or generated configuration.

The repository may provide default selections through a tracked profile data
file. A new component is unselected unless it is explicitly part of the
baseline.

The TUI loads the local profile on startup, applies detection state, and saves
changes after a successful selection step. A failed installation does not
discard the selected profile.

## Component Manifest

Installable components are represented as data. Each component has:

- A stable ID.
- A display label.
- A category.
- A default selection state.
- Zero or more Homebrew formulae or casks.
- Zero or more setup tasks.
- Zero or more config link IDs.
- Optional command or application requirements.
- Optional component dependencies.

The manifest must represent Hunk in the Git category and include its package,
setup, and config link as one selected component.

The existing topic files can remain during migration. The installer should
first support the new manifest and retain topic commands for compatibility.

## Linking

The current unconditional `all_links` behavior is replaced by profile-aware
link selection.

Each link record contains:

- A stable link ID.
- A repository source.
- One or more target paths.
- A link mode, including app-writable behavior.
- An optional command or application requirement.
- The component that owns the link.

`dot link` links the current profile only. It skips unselected links and links
whose requirements are absent. Every skip includes a reason.

Examples:

- Git links are available with the Git baseline.
- Hunk links require the Hunk component.
- VS Code links require the VS Code component and the `code` command.
- PHPStorm links require the PHPStorm component.
- AI instruction links require explicit AI selection.

The command `dot link --all` remains an explicit escape hatch. It links all
valid records and reports missing requirements. It is not the default.

Existing backup, idempotency, app-writable, and unlink behavior remains.

## Bootstrap and CLI Architecture

The existing Bash `bin/dot` remains the entry point for remote installation,
Homebrew bootstrap, non-interactive scripts, and compatibility commands.

The Go application lives under a standard Go module and owns the interactive
TUI. The Bash entry point installs Go before it starts the Go application. It
builds or invokes the TUI without requiring Go during the first bootstrap
steps.

The public commands are:

```text
dot tui
dot install --profile PATH
dot install --dry-run --profile PATH
dot link
dot link hunk
dot link --all
dot doctor
```

Existing topic commands continue to work during migration. The TUI is the
recommended path for new installations.

## TUI Flow

1. Detect the operating system, Homebrew, Xcode tools, commands, and apps.
2. Load the local profile.
3. Show baseline and optional components.
4. Allow category navigation, search, and individual selection.
5. Select required dependencies automatically.
6. Build an ordered execution plan.
7. Show commands, links, skipped items, and dependency actions.
8. Require confirmation before execution.
9. Execute tasks sequentially.
10. Show current task, completed count, elapsed time, and output.
11. Report installed, changed, skipped, and failed tasks.
12. Offer to rerun failed tasks.
13. Save the selected profile.

The core keyboard actions are:

```text
Space    toggle the current item
a        select the current category
n        clear the current category
/        search
p        preview the plan
Enter    apply the plan
r        rerun failed tasks
q        quit
```

## Execution and Errors

The executor runs one task at a time. It does not start a dependent task until
its dependency succeeds or is already satisfied.

Each task reports:

- Component ID.
- Human-readable label.
- Command or operation.
- Start and finish time.
- Exit status.
- Captured output.

Failures do not prevent independent later tasks from running. Dependent tasks
are skipped with the failed dependency as the reason. Cancellation stops new
tasks and reports the partial result.

Dry-run mode prints the same ordered plan without changing the filesystem,
installing packages, or changing profile state.

## Non-Interactive Behavior

Existing shell commands remain usable for automation. Profile execution must
not require a terminal. The same manifest and dependency checks must produce
the plan for both the TUI and `dot install --profile`.

## Testing

Tests must cover:

- Manifest parsing and stable component IDs.
- Baseline default selection.
- Go being non-deselectable.
- Independent optional selection.
- Profile load, save, and invalid profile errors.
- Automatic dependency selection.
- Requirement-based link skipping.
- Hunk being in the Git category.
- Plan ordering and dependent-task failure handling.
- Dry-run side-effect protection.
- Existing link backup and idempotency behavior.
- Bubble Tea model updates through deterministic input and output buffers.

The existing Bats suite remains in place for the Bash compatibility layer.

## Migration

1. Add the Go module and a minimal TUI command.
2. Add manifest and profile loading without changing existing commands.
3. Move package entries from coarse topics into granular components.
4. Add profile-aware plan generation and execution.
5. Replace unconditional linking with selected, requirement-aware linking.
6. Update help, completions, README, and tests.

The migration must preserve `--dry-run`, backups, idempotent reruns, and the
current remote bootstrap path.
