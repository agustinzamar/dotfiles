# dot-cli-install Specification

## Purpose

Define how the `dot` CLI (`bin/dot`) dispatches the `install` command after
this change: bare `dot install` launches the interactive TUI, headless flags
survive for scripts and CI, non-TTY stdin fails loudly, and the separate
`dot tui` entry point is hard-removed with help and completion kept correct.

## Requirements

### Requirement: Bare install dispatches to the TUI

The `sub_install` dispatcher MUST resolve a bare `dot install` (no flags) to a
TUI launch instead of the legacy `bootstrap + baseline + link` sequence.

#### Scenario: Bare install opens the TUI

- GIVEN a machine where the TUI runtime is available
- WHEN the user runs bare `dot install`
- THEN the Bun TUI from `tools/tui/` opens with the tool selector as its first step

### Requirement: Headless paths remain available

`dot install --all` MUST run the full phases headlessly and
`dot install --profile <name|path>` MUST apply a saved profile headlessly.
Both paths MUST NOT open the TUI.

#### Scenario: Full headless install

- GIVEN a scripted or CI environment
- WHEN the user runs `dot install --all`
- THEN bootstrap, baseline-equivalent phases, and linking run without any TTY interaction

#### Scenario: Profile-based install

- GIVEN a saved profile at `$DOT_PROFILE` or an explicit path
- WHEN the user runs `dot install --profile <name>`
- THEN only the profile-selected components are installed and linked, without opening the TUI

### Requirement: Non-TTY stdin fails loudly

When stdin is not a TTY and neither headless flag is given, bare
`dot install` MUST fail immediately with a clear error pointing at
`dot install --all` and `dot install --profile`. It MUST NOT hang and MUST NOT
silently skip installation.

#### Scenario: Piped stdin without flags

- GIVEN stdin is piped (e.g. `curl ... | bash` forwarding no TTY) and no flags are passed
- WHEN `dot install` runs
- THEN it exits non-zero with a message naming the headless alternatives

### Requirement: dot tui is hard-removed

The CLI MUST remove the `tui` subcommand entirely: delete `sub_tui`, drop the
`tui` entry from `TOP_COMMANDS`, and remove both `tui` help lines. No
deprecation shim remains. Shell completion (which parses `dot help`) MUST stay
correct after removal.

#### Scenario: tui subcommand is gone

- GIVEN the updated `bin/dot`
- WHEN the user runs `dot tui`
- THEN it reports an unknown-command error consistent with other removed commands

#### Scenario: Completion stays correct

- GIVEN the removed `tui` entry
- WHEN completion parses `dot help` output
- THEN `tui` does not appear in completions and all remaining top commands complete correctly

### Requirement: Help documents the new dispatch

`sub_help` MUST document that bare `dot install` opens the interactive
installer and that `--all` / `--profile` are the headless alternatives.

#### Scenario: Help output matches behavior

- WHEN the user runs `dot help`
- THEN the install section describes the interactive default and both headless flags
