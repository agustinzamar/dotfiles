# Dot CLI Bootstrap Specification

## Purpose

Define the `dot-tui` command-line contract (flags and interactive loop) and how
`bin/dot` resolves or obtains the compiled installer binary on machines that may have
neither Go nor Bun — notably fresh-machine bootstrap via `bin/dot install`.

## Requirements

### Requirement: Non-Interactive Flag Mode

With `-profile <path>`, the binary MUST load the profile from that path (failing with a
non-zero exit on invalid profiles), print one `skip <id>: <reason>` line per skip entry,
then print one `<label>: <command>` line per planned task. With `-dry-run`, or when
`-apply` is absent, it MUST stop after printing the plan without executing anything.
With `-apply` only, it MUST execute the plan, save the profile back to the given path,
run `dot link` with `DOT_PROFILE=<path>` in the environment, and exit non-zero if any
component failed or linking failed.

#### Scenario: Dry run prints plan and exits zero without side effects

- GIVEN a valid profile file and `-profile <path> -dry-run`
- WHEN the binary runs
- THEN skip lines precede task lines on stdout
- AND no installation commands execute, no profile rewrite occurs, and exit code is 0

#### Scenario: Apply mode runs, persists, links, and reports failure status

- GIVEN a profile whose plan includes a failing component and `-profile <path> -apply`
- WHEN the binary runs to completion
- THEN per-component results are printed (`✅ installed` / `⚠️ skipped` / `❌ failed`)
- AND the profile file is saved after execution
- AND `dot link` runs exactly once with `DOT_PROFILE` set to the profile path
- AND the process exits non-zero because a component failed

### Requirement: Interactive Loop Persists Then Applies

Without `-profile`, the binary MUST default the profile path to
`${XDG_CONFIG_HOME:-$HOME/.config}/dot/profile.json`, run the TUI selection, and on
submission: save the submitted profile, plan against the applied set, execute, mark
successfully installed components as applied, invoke `dot link` with `DOT_PROFILE` set,
and re-open the TUI for another round. Quitting without submission MUST end the program.

#### Scenario: One interactive round applies and loops

- GIVEN an interactive session where the user submits a review containing component X
- WHEN X installs successfully and linking succeeds
- THEN the profile file contains X enabled
- THEN X is marked applied so an immediately following round plans no tasks for X
- AND "✅ Config links installed" style confirmation is printed
- AND the TUI reopens rather than exiting

#### Scenario: Quit without submission changes nothing

- GIVEN an interactive session ended with `q` and no submitted review
- WHEN the binary exits
- THEN nothing is executed, no profile is written, and no link runs

### Requirement: Binary Resolution Order For bin/dot

`bin/dot`'s TUI entry points MUST resolve the installer binary in this exact order:

1. A prebuilt release binary, when available locally or downloadable during bootstrap,
   requiring neither Go nor Bun at runtime.
2. Otherwise, when Bun of at least the documented minimum version is present, build
   from source inside `bin/dot` (`bun install` + compile step) and use that binary.
3. Otherwise, print actionable guidance directing the user to the official bootstrap
   script (which installs Bun) instead of failing silently or mentioning Go.

The Go toolchain MUST NOT be referenced anywhere in this resolution path.

#### Scenario: Prebuilt binary used directly on a clean machine

- GIVEN a machine with neither Go nor Bun but a valid prebuilt release binary present
- WHEN `bin/dot tui` is invoked
- THEN the prebuilt binary runs without any toolchain invocation

#### Scenario: Local Bun builds from source as fallback

- GIVEN no prebuilt binary, Bun ≥ minimum version installed, and the repo checked out
- WHEN `bin/dot tui` is invoked
- THEN `bin/dot` builds the binary from source using Bun and then launches it
- AND no Go command is invoked

#### Scenario: Neither binary nor Bun yields guidance

- GIVEN no prebuilt binary and no Bun on PATH
- WHEN `bin/dot tui` is invoked
- THEN the user sees actionable bootstrap guidance naming the official bootstrap script
- AND the failure is explicit (non-zero exit) rather than silent

### Requirement: No Go Remains In The Bootstrap Path

After this change, `bin/dot`, the Makefile, and CI MUST NOT reference the Go toolchain,
`go run`, `go.mod`, or `go test`; their gates SHALL be typecheck plus `bun test`, with
Bats integration tests continuing to exercise the real CLI unchanged.

#### Scenario: Repo-wide Go absence

- GIVEN the repository after implementation
- WHEN searching all tracked files for Go sources, `go.mod`, `go.sum`,
  or `go run cmd/dot-tui` invocations
- THEN no matches exist outside of historical git history
- AND `bin/dot tui` still works end-to-end per the scenarios above
