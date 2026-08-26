# installer-profile Specification

## Purpose

Define what an interactive install persists to the dot profile
(`$DOT_PROFILE`, default `~/.config/dot/profile.json`) and what it must NOT
persist, so TUI-written profiles stay compatible with `component_selected()`,
`dot link` gating, and later `dot update` re-links.

## Requirements

### Requirement: Tool selections persist to the profile

The TUI MUST persist confirmed tool selections to `$DOT_PROFILE` using the
shape `install/components.sh` already reads: `.components[id] == true` for each
selected component id. `component_selected()` MUST keep working unchanged for
`dot link` gating.

#### Scenario: Selected tools land in profile.json

- GIVEN the user selected a set of tools and confirmed the flow
- WHEN the flow completes successfully
- THEN `$DOT_PROFILE` contains `.components[id] == true` exactly for the selected components and locked-block ids

#### Scenario: Profile-aware linking stays consistent

- GIVEN a profile written by a successful TUI run
- WHEN a later bare `dot link` or `dot update` runs
- THEN `_walk_links` gates on the same components via `component_selected()` with no format change

### Requirement: Link choices are not persisted

The TUI MUST apply confirmed link choices immediately but MUST NOT persist them
to `profile.json`. The profile keeps tool selections only; future bare
`dot link` runs remain free-form.

#### Scenario: Link choices leave no trace in the profile

- GIVEN the user checked some link rows and confirmed
- WHEN the flow completes and `$DOT_PROFILE` is inspected
- THEN no link names or link section appear in the profile

#### Scenario: Later free-form link run is unaffected

- GIVEN a TUI run linked a subset of offered links
- WHEN the user later runs bare `dot link`
- THEN that run walks all component-selected links as usual, independent of what the TUI run linked

### Requirement: Additive profile writes are rollback-safe

Profile writes MUST be additive JSON at `$DOT_PROFILE`; absent fields MAY fall
back to existing defaults (`component_default_selected`) so stale or missing
profile files do not break other commands.

#### Scenario: Missing profile falls back to defaults

- GIVEN no `$DOT_PROFILE` exists on disk
- WHEN any command calls `component_selected()` for base/shell/git/terminal ids
- THEN those ids resolve as selected per existing defaults
