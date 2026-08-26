# Delta for installer-tui

Change `ink-ui-steps-1-2` rewrites installer-TUI steps 1 and 2 onto @inkjs/ui
components. This delta amends the base installer-tui spec
(`openspec/changes/tui-default-install/specs/installer-tui/spec.md`).
Superseded pre-existing surface, marked per-requirement with `(Previously: ...)`:

- The custom fixed-key surface of steps 1/2 (hand-rolled reducer, fixed keys)
  is replaced by the component keyboard contract: arrow keys navigate, space
  toggles, enter submits.
- The `tui-default-install` ADR-2 pure-string frame constraint no longer
  applies to steps 1/2; layout is free (category headers and lock markers not
  required).
- Locked rows map to the component disabled state (`isDisabled`, never
  toggleable); former defaults map to pre-checked rows.

Manifest selectors (`toolRowsGrouped`, `offeredLinks`) and the apply phase are
out of scope and unchanged; requirements not listed below remain in force
verbatim (`Multi-target names toggle as one unit`, `Opt-in AI agent links
group`, `Confirmed links apply immediately`, `Abort installs and links
nothing`).

## ADDED Requirements

### Requirement: Quit-before-confirm abort code

If the user quits the TUI at any point before confirming the config-link step
(step 1, step 2, or any pre-confirm pause), the process MUST exit with code 10
and MUST NOT install, link, or otherwise write anything to disk. This
requirement complements the base `Abort installs and links nothing`
requirement by pinning the observable exit code.

#### Scenario: Quit at the link step

- GIVEN the user selected tools and reached the config-link step
- WHEN the user quits the TUI without confirming
- THEN the process exits with code 10, no packages were installed, no links were created, and no filesystem writes occurred

### Requirement: Adapted selection feeds the apply pipeline

The values selected and checked in the component-driven steps MUST be adapted
into the existing TUI state and fed to the existing `applyConfirmed` pipeline.
When the user confirms, application MUST run immediately and unchanged in the
order: bootstrap → taps → brews → pseudo-steps → links → topic installs. The
manifest context schema, the `applyConfirmed` pipeline, and apply-phase
behavior MUST NOT change as a result of this change.

#### Scenario: Confirm applies the unchanged pipeline

- GIVEN the user selected tools and checked link rows
- WHEN the user confirms the link step
- THEN the unchanged application order runs (bootstrap, taps, brews, pseudo-steps, links, topic installs) and the confirmed links exist on disk before the TUI exits

### Requirement: Version-marker rebuild contract

The installer binary MUST report the version marker `dot-tui-context-v5` from
its `--version` output. All three marker sites — the `TUI_VERSION` constant in
`tools/tui/src/main.ts`, the resolver comparison in `bin/dot`, and the resolver
stubs in `test/tui-resolver.bats` — MUST be updated together to `v5` and the
binary rebuilt. When the binary's reported marker does not equal the resolver's
expected marker (stale or missing), the resolver MUST rebuild the binary before
use; this change pins that existing rebuild behavior to the `v5` marker.

#### Scenario: Stale binary triggers rebuild

- GIVEN `bin/dot-tui` reports `dot-tui-context-v4` while `bin/dot` expects `dot-tui-context-v5`
- WHEN bare `dot install` runs the resolver
- THEN the resolver rebuilds the binary and the rebuilt binary reports `dot-tui-context-v5`

### Requirement: Component-rendered frame behavioral coverage

The observable behavior of the component-rendered step-1 and step-2 frames MUST
remain covered by the TUI's automated unit tests: assertions MUST cover that
locked rows are non-toggleable, former defaults render pre-checked, space
toggles link rows, enter submits, and quit-before-confirm exits 10 with zero
writes. The reworked frame tests MUST NOT depend on the superseded pure-string
output shape; test-technique choices are implementation detail.

#### Scenario: Frame tests assert the component contract

- GIVEN the step-1 and step-2 frames render through components
- WHEN the TUI's unit test suite runs the reworked frame tests
- THEN the tests assert locked-row non-toggleability, pre-checked defaults, space/enter behavior, and exit-10 zero-write quit

## MODIFIED Requirements

### Requirement: Per-tool toggleable rows

The tool selector (step 1) MUST render every brew/cask entry from the package
manifests (`install/topics/*`) as an individually toggleable row using @inkjs/ui
components. Group toggles MUST NOT exist anywhere in the selector. Rows SHOULD
be grouped visually by topic for scanning, but toggles remain strictly
per-row. Row interaction MUST follow the component keyboard contract (arrow
keys navigate, space toggles a row's selection, enter submits the step) rather
than the pre-change custom fixed keys. Special installers (VS Code extensions,
duti) MUST appear as their own selectable rows.
(Previously: step-1 rows were custom pure-string rows driven by a hand-rolled
reducer with fixed custom keys.)

#### Scenario: User toggles one package inside a topic group

- GIVEN the tool selector shows topic groups containing multiple packages
- WHEN the user navigates to a single package row and presses space
- THEN only that package's selection changes and sibling rows are untouched

#### Scenario: Special installers appear as rows

- GIVEN the manifests include topics with special installers (VS Code extensions, duti)
- WHEN the tool selector renders
- THEN each such topic appears as its own selectable row alongside brew/cask rows

### Requirement: Locked essentials block

The tool selector MUST render the locked Base/Shell essentials rows at the top:
shell + git core only (`zsh`, `fzf`, `git`, `gh`, `tmux`) plus Zinit/Zsh setup
and Git signing config. Each locked row MUST map to the component disabled
state (`isDisabled`), so the block is always installed, always visible, and
NEVER toggleable. A dedicated locked-block marker/header (🔒) and any special
locked-layout rendering are not required; layout is free. All other tools
previously forced by the old baseline (e.g. `lazygit`, `hunk`, `yazi`,
`neovim`, Ghostty) MUST appear as normal per-tool rows, pre-checked by default
and toggleable under the component keyboard contract.
(Previously: the locked block was a custom-marked pure-string block with no
component disabled-state mapping.)

#### Scenario: Locked row cannot be deselected

- GIVEN the tool selector renders the locked essentials rows in the disabled component state
- WHEN the user attempts to toggle any locked row (space or enter)
- THEN the row remains selected and checked and its selection cannot change

#### Scenario: Old baseline extras are pre-checked but removable

- GIVEN a fresh selection session
- WHEN the tool selector renders
- THEN former forced baseline tools like `lazygit` and `neovim` start checked and CAN be unchecked by the user

### Requirement: Component-filtered config-link step

After tool selection, the TUI MUST present step 2 as a checkbox list rendered
with @inkjs/ui components listing ONLY the config links whose `component` tag
matches a selected tool (or which have no component tag and belong to the
locked block), sourced from `install/links.sh` rows shaped
`name|source|target|mode|component|requirement`. Every link row MUST default to
unchecked; nothing links unless explicitly checked. Interaction MUST follow the
checkbox-list contract: space toggles each offered link and enter submits. The
filtering rules are unchanged from the base spec.
(Previously: the link step was a custom pure-string selector with fixed custom
keys; the filtering rules are unchanged.)

#### Scenario: Link list follows tool selection

- GIVEN the user selected only the `terminal` components
- WHEN the config-link selector renders
- THEN it lists links tagged `terminal` (e.g. ghostty, tmux, yazi) and excludes links for unselected components (e.g. vscode)

#### Scenario: Space toggles and enter submits

- GIVEN the config-link checkbox list renders offered links all unchecked
- WHEN the user presses space on one link and then presses enter
- THEN only that link is checked at submit time, and the step submits with the checked set

#### Scenario: Nothing selected means nothing offered

- GIVEN the user kept only the locked essentials block
- WHEN the config-link selector renders
- THEN only untagged links belonging to the locked block are offered, and all remain unchecked
