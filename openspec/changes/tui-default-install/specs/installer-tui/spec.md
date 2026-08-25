# installer-tui Specification

## Purpose

Define the interactive install flow presented by the Bun TUI (`tools/tui/`)
when launched by bare `dot install`: a per-tool selector, a visible locked
essentials block, a component-filtered config-link step, opt-in AI agent
links, and abort semantics.

## Requirements

### Requirement: Per-tool toggleable rows

The tool selector MUST render every brew/cask entry from the package manifests
(`install/topics/*`) as an individually toggleable row. Group toggles MUST NOT
exist anywhere in the selector. Rows SHOULD be grouped visually by topic for
scanning, but toggles remain strictly per-row.

#### Scenario: User toggles one package inside a topic group

- GIVEN the tool selector shows topic groups containing multiple packages
- WHEN the user toggles a single package row
- THEN only that package's selection changes and sibling rows are untouched

#### Scenario: Special installers appear as rows

- GIVEN the manifests include topics with special installers (VS Code extensions, duti)
- WHEN the tool selector renders
- THEN each such topic appears as its own selectable row alongside brew/cask rows

### Requirement: Locked essentials block

The tool selector MUST render a locked Base/Shell essentials block at the top:
shell + git core only (`zsh`, `fzf`, `git`, `gh`, `tmux`) plus Zinit/Zsh setup
and Git signing config. The block MUST always be installed, always be visible,
and never be toggleable. All other tools previously forced by the old baseline
(e.g. `lazygit`, `hunk`, `yazi`, `neovim`, Ghostty) MUST appear as normal
per-tool rows, pre-checked by default.

#### Scenario: Locked block cannot be deselected

- GIVEN the tool selector is open
- WHEN the user attempts to interact with the essentials block
- THEN the block stays marked locked and none of its members can be toggled off

#### Scenario: Old baseline extras are pre-checked but removable

- GIVEN a fresh selection session
- WHEN the tool selector renders
- THEN former forced baseline tools like `lazygit` and `neovim` start checked and CAN be unchecked by the user

### Requirement: Component-filtered config-link step

After tool selection, the TUI MUST present a second selector listing ONLY the
config links whose `component` tag matches a selected tool (or which have no
component tag and belong to the locked block), sourced from `install/links.sh`
rows shaped `name|source|target|mode|component|requirement`. Every link row
MUST default to unchecked; nothing links unless explicitly checked.

#### Scenario: Link list follows tool selection

- GIVEN the user selected only the `terminal` components
- WHEN the config-link selector renders
- THEN it lists links tagged `terminal` (e.g. ghostty, tmux, yazi) and excludes links for unselected components (e.g. vscode)

#### Scenario: Nothing selected means nothing offered

- GIVEN the user kept only the locked essentials block
- WHEN the config-link selector renders
- THEN only untagged links belonging to the locked block are offered, and all remain unchecked

### Requirement: Multi-target names toggle as one unit

Link names that map to multiple targets (e.g. `ghostty`, `yazi`, `vscode`)
MUST render as one toggleable row under a single label and toggle together,
matching how `link_named` treats names.

#### Scenario: Ghostty row toggles both targets

- GIVEN the link selector shows `ghostty` covering two target paths
- WHEN the user checks the `ghostty` row and confirms
- THEN both ghostty targets are linked together

### Requirement: Opt-in AI agent links group

The config-link selector MUST offer the AI agent links (`optional_links` in
`install/links.sh`) as a final opt-in group, unchecked by default. This group
MUST be independent of tool selections.

#### Scenario: AI links offered but not forced

- GIVEN the user reaches the link step
- WHEN the AI agent links group renders
- THEN each optional link is visible, unchecked, and links only if the user checks it before confirming

### Requirement: Confirmed links apply immediately

Confirmed link choices MUST be applied (symlinks created) immediately when the
user confirms the link step, without requiring a separate `dot link` run.

#### Scenario: Confirm applies links in-session

- GIVEN the user checked some link rows and confirmed
- WHEN the flow finishes
- THEN the confirmed symlinks exist on disk before the TUI exits

### Requirement: Abort installs and links nothing

Quitting or aborting the TUI at ANY point in the flow (tool step, link step,
or during application) MUST install nothing and link nothing. No partial state
from an aborted run MAY leak to disk beyond what prior sessions already wrote.

#### Scenario: Quit at the link step

- GIVEN the user selected tools and reached the config-link step
- WHEN the user quits the TUI without confirming
- THEN no packages were installed, no links were created, and the existing profile is unchanged

#### Scenario: Abort during application

- GIVEN the user confirmed and application has started
- WHEN the TUI is interrupted mid-application
- THEN the run reports the interruption loudly rather than silently continuing
