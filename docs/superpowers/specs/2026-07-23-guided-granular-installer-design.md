# Guided Granular Installer Design

## Goal

Replace selection-first installation with a guided installer that asks for consent before every installable item. The user chooses categories, tools, configuration leaves, extensions, plugins, aliases, functions, and individual macOS settings. Each accepted item installs immediately and reports its result before the next prompt.

`dotfiles install` becomes guided mode. Existing tree selection remains available as an advanced mode.

## Technology

- Keep Go, Cobra, YAML manifests, executor, symlink, snapshot, lock, config, and logger packages.
- Upgrade Bubble Tea, Bubbles, and Lip Gloss to their v2 module paths.
- Add `charmbracelet/huh` v2 for confirmation, choice, text input, validation, and note forms. A Huh form is embedded in the Bubble Tea model.
- Do not introduce Node.js, a web UI, or another runtime.

This preserves the single-binary installer and existing executor investment while replacing custom prompt state with maintained terminal form components.

## Commands

| Command | Behavior |
| --- | --- |
| `dotfiles install` | Guided category-to-leaf interactive installation. |
| `dotfiles install --select` | Existing category/tree selection experience for advanced batch choice. |
| `dotfiles install --all --apply` | Noninteractive installation of all eligible deterministic nodes. Interactive setup remains pending and is listed in the summary. |
| `dotfiles install --dry-run` | Never changes machine state; shows planned execution and setup that would be required. |
| `dotfiles install --diff` | Shows planned file changes before installation. |
| `dotfiles install --profile <name>` | Filters nodes by profile before either guided or select mode. |

`--all` and CI mode must not open a browser, ask a question, or generate keys. Values may only come from existing private variables or explicit environment configuration. A summary records every skipped interactive setup action as pending.

## Guided Interaction

The wizard traverses one category at a time.

1. Ask `Configure <category>?`.
2. For an accepted category, ask `Install <tool>?` for every eligible tool.
3. Resolve each missing dependency before its dependent node. The dependency prompt identifies the dependent item. Declining it skips the dependent item with an explicit reason.
4. Execute accepted tool installation immediately. If already installed, report that status but still offer configuration and setup children.
5. Traverse every child node individually: configuration files, extensions, plugins, aliases, functions, and settings.
6. Run node setup workflow, if present, and verify final state.
7. Continue until all selected categories finish, then display complete session report.

Every selectable node uses Yes/No. Nodes with children also offer an optional group shortcut, for example `Install all VS Code extensions?`. The shortcut sets initial answers only; every child remains visible and can be overridden individually. Declining the group shortcut proceeds to individual child prompts.

The wizard permits Back only for unanswered or unexecuted nodes. It never attempts to undo an already completed installation. A future `dotfiles configure <id>` command is the safe way to rerun a completed node's configuration.

## Manifest Model

Use stable IDs and recursive nodes rather than the current `checked` tool plus flat feature model.

```yaml
categories:
  - id: editors-ai
    name: Editors & AI
    nodes:
      - id: vscode
        name: VS Code
        default: true
        steps:
          - type: cask
            package: visual-studio-code
        children:
          - id: vscode-settings
            name: Settings
            default: true
            steps:
              - type: symlink
                from: config/vscode/settings.json
                to: ${HOME}/Library/Application Support/Code/User/settings.json
          - id: vscode-extensions
            name: Extensions
            children:
              - id: vscode-catppuccin
                name: Catppuccin Theme
                default: true
                steps:
                  - type: vscode
                    extension: catppuccin.catppuccin-vsc
```

Rules:

- Every node with steps is an individually selectable leaf.
- A parent may have its own steps and children. Its own steps execute before its children.
- `default` controls initial guided answer only; it never bypasses a prompt.
- `requires` uses stable node IDs, not display names.
- `setup` is a list of typed workflow handler IDs.
- Profiles apply at any node level. A filtered parent does not expose descendants.
- Manifest validation rejects duplicate IDs, missing dependencies, dependency cycles, invalid handler IDs, and nodes that cannot execute any step, setup, or child.

Migration splits current bundles into leaves. Examples: every VS Code extension becomes a separate node; each config symlink, OMZ plugin, shell alias/function file, and macOS default becomes separately selectable. Display-only group nodes organize leaves without bundling consent.

## Setup Workflows

Setup handlers are implemented in Go and referenced by manifest IDs. Complex authentication and key operations do not live in arbitrary YAML shell commands.

### Git

- `Install Git?` checks `git` first. Missing Git invokes Xcode Command Line Tools installation.
- If macOS installation requires user completion, mark Git setup pending and explain that rerunning the installer resumes setup after Xcode finishes.
- After Git is available, `Configure Git identity?` reads global `user.name` and `user.email`.
- Prompt only missing values. Existing values remain unchanged unless user explicitly selects an edit action.

### Homebrew

- `Install Homebrew?` detects `brew` then installs it if missing.
- Brew-dependent nodes cannot run without Homebrew. The wizard offers Homebrew as dependency and records a clear skip if declined.

### GitHub CLI

- `Install GitHub CLI?` installs `gh` when needed.
- `Authenticate with GitHub now?` runs native `gh auth login` only after acceptance. The TUI suspends for the child process, then resumes and verifies with `gh auth status`.
- After successful authentication, `Configure Git credential helper?` runs `gh auth setup-git` after consent.
- Credentials, tokens, and auth output are never added to manifest variables, logs, snapshots, or rendered configuration.

### Signed Commits

- `Set up signed commits?` appears after Git setup.
- User chooses SSH or GPG.
- SSH path: detect public keys, select an existing key or create a new ed25519 key after confirmation, optionally register its public part with authenticated GitHub, then configure Git SSH signing.
- GPG path: detect secret keys, select an existing key or launch interactive key generation, optionally register its public part with authenticated GitHub, then configure Git GPG signing.
- Both paths configure the signing key and `commit.gpgsign`, then verify configuration without creating a commit.
- Key generation never overwrites an existing key. Selection displays path and fingerprint only. Private keys remain outside repository, logs, variables, and snapshots.

### Hunk

- `Want Hunk for diff reviews?` controls Hunk installation.
- After installation, prompt independently for its config symlink and for `Use Hunk as global Git pager?`.
- Git `core.pager` is never set to Hunk until Hunk is installed and the user accepts that leaf.

### Generic Nodes

Generic nodes install their typed manifest steps then verify using existing skip checks. Every existing optional feature is converted into a selectable leaf. This includes terminal configs, editor settings, individual editor extensions, shell helpers, AI tool configs, app configs, and macOS defaults.

## Installation Session

Introduce a shared installation-session service used by guided, select, and noninteractive paths.

The session owns:

- manifest traversal and dependency resolution;
- answers and status for every node;
- one installation lock;
- snapshots of changes and rollback metadata;
- executor invocation and structured results;
- safe variable access and redacted output;
- final summary.

Node statuses are `installed`, `already-present`, `declined`, `skipped-dependency`, `pending-setup`, `failed`, and `would-install`. Each result includes a human-readable reason. The same status model drives TUI output, noninteractive stdout, logs, and tests.

Interactive external commands use Bubble Tea's child-process execution support so terminal control returns to `gh`, `ssh-keygen`, or GPG temporarily. The wizard re-detects state when the child process exits instead of trusting an exit code alone.

On failure, guided mode offers Retry, Skip, or Quit. Failure in one node does not silently approve another node. Package installs and authentication are not globally reversible; file changes retain existing snapshot and rollback handling. The final report distinguishes failed changes from pending user-driven setup.

## Testing

- Manifest tests validate IDs, trees, profiles, dependencies, handler references, and migrations from current manifest content.
- Planner tests cover category gates, every-leaf prompts, group shortcut overrides, dependency accept/decline, profile filters, and Back behavior.
- Workflow tests use a fake command runner for Git identity, `gh auth status`, `gh auth login`, `gh auth setup-git`, SSH key selection/generation, GPG selection/generation, GitHub key registration, and Hunk pager safeguards. Tests never create keys or authenticate live.
- Session and executor integration tests cover dry run, already-present skip, failure retry, skip after failure, locking, snapshots, and summaries.
- TUI tests cover form navigation, keyboard interaction, child-process suspend/resume, and rendered snapshots.

## Acceptance Criteria

- Default install mode requests consent for each category, tool, and every installable child leaf.
- User can choose every VS Code extension independently.
- User can choose every config, shell helper, plugin, and macOS setting independently.
- Git identity is only prompted when missing and is configured immediately after Git acceptance.
- GitHub authentication runs only after `gh` installation and explicit consent, then verifies its result.
- Signed commit setup supports both SSH and GPG, reuse or generation, and optional GitHub registration.
- Hunk pager configuration cannot be selected without Hunk installation.
- Select and all modes retain clear, safe semantics and share installation session behavior.
- Installer does not log credentials or private key material.
