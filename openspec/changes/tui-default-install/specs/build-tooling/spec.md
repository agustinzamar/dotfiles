# build-tooling Specification

## Purpose

Keep the repo's SDD configuration and Make targets truthful about the actual
TUI runtime after the Go tree is gone and the Bun/TS TUI under `tools/tui/` is
the runtime this change builds on (base: `migrate-tui-to-bun` merged into main).

## Requirements

### Requirement: Config describes the Bun runtime

`openspec/config.yaml` MUST describe the real stack: the Bash CLI (`bin/dot`),
the Bun/TS TUI under `tools/tui/`, and Homebrew Bundle. It MUST NOT reference
Go 1.26, bubbletea, `internal/installer`, `cmd/dot-tui`, or `make go-test`.

#### Scenario: No stale Go references in config

- GIVEN the updated `openspec/config.yaml`
- WHEN it is inspected for stack and testing descriptions
- THEN no Go-era tooling (`go test`, `go vet`, bubbletea, `cmd/dot-tui`) is named and the Bun runtime is

### Requirement: Makefile checks target the real runtime

The `check`/`test` Make targets MUST exercise checks that exist on `main`:
shell linting for Bash assets and the actual Bun/TS checks for `tools/tui/`.
Targets invoking `go vet ./...` or `go build ./...` over a tree with no Go
packages MUST be re-pointed or removed.

#### Scenario: make check passes without Go

- GIVEN the aligned Makefile on a machine with bun installed but no Go project
- WHEN `make check` runs
- THEN shell checks pass and TUI runtime checks execute against `tools/tui/` with no Go invocation
