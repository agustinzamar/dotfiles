# Proposal: Migrate the Go TUI installer to Bun + TypeScript

Replace the Go-based TUI installer (`cmd/dot-tui` + `internal/installer`) with a single
Bun/TypeScript implementation using Ink, delete all Go code and toolchain requirements,
and ship the result as a standalone compiled binary that `bin/dot` invokes. This removes
the last non-shell language from the dotfiles repo and gives contributors one language
(TS) for all tooling logic.

## Why

- **Two runtimes to maintain.** Today every contributor who touches the installer needs
  Go 1.26 plus Bubbletea v2 familiarity, while everything else in the repo is Bash.
  A single TypeScript codebase lowers the contribution barrier and drops `go.mod`,
  `go vet`, and `go test` from the maintenance surface entirely.
- **Bootstrap friction.** `bin/dot` currently falls back to `go run cmd/dot-tui`,
  which requires a full Go toolchain on any machine running the installer. A compiled
  Bun binary removes that requirement for end users.
- **Verified scope, known size.** Exploration confirms ~900 lines of Go across four
  files plus ~430 lines of tests, all of which map cleanly to TS equivalents
  (manifest/profile as typed data + zod-style validation, plan as DFS over an array,
  TUI via Ink's React model). The port is mechanical enough to estimate reliably:
  ~900 lines of TS replacing ~900 lines of Go, plus test and build-config changes.

## What Changes

| Area | Change |
| ------ | -------- |
| Runtime | Go 1.26 → Bun + TypeScript (single language for all tooling) |
| TUI framework | Bubbletea v2 → Ink (React for terminals); 1:1 port of keys, panes, viewport, search, review flow, ANSI look |
| New source | `tools/tui/` (or equivalent TS package): `manifest.ts`, `profile.ts`, `plan.ts`, `execute.ts`, `tui.tsx`, `main.ts` |
| Deleted | `cmd/dot-tui/main.go`, `internal/installer/*.go` (~825 LOC), all Go unit tests (~430 LOC), `go.mod`, `go.sum` |
| Distribution | Compiled standalone binary via `bun build --compile`; `bin/dot` invokes the binary with a build-if-missing fallback (`bun build` when Bun exists locally); Go toolchain requirement removed from `bin/dot` |
| Tests | bun:test ports of every existing Go unit test: profile round-trip, legacy-ID migration idempotency, plan skip/applied semantics, execute continue-and-skip-dependents, TUI key handling, manifest stability |
| Build/CI | Makefile: replace `go-test`/`go vet` targets with `bun-test`/typecheck (`tsc --noEmit`) + `bun build --compile`; CI runs the new targets; Bats integration tests keep exercising the real CLI unchanged |

### Ported behavior (must be preserved exactly)

- Manifest: 31 components with id/label/category/default/required/dependencies/links/commands.
- Profile: `{components: map[string]bool}` persistence with atomic tmp+rename writes;
  legacy aggregate-ID migration (communication/desktop/media/databases); validation
  rejecting unknown IDs and missing required components.
- Plan: environment detection (`LookPath`-equivalents for brew/xcode-select/etc.);
  DFS dependency ordering; xcode-select skip-when-present rule; brew-required skip rule.
- Execute: sequential runner, dependency-failure blocking (dependents skipped),
  cancellation support, `sh -c` shell runner with `HOMEBREW_NO_AUTO_UPDATE=1`.
- CLI flags: `-profile` / `-apply` / `-dry-run`; interactive loop otherwise; per-component
  result summary; final `dot link` invocation with `DOT_PROFILE` env var.

## Impact Scope

- **`bin/dot`**: `sub_tui` / `run_profile_install` switch from `go run cmd/dot-tui`
  to invoking the compiled binary (build-if-missing). Go check removed.
- **Makefile**: `check`/`lint`/`test` targets rewire from go-vet/go-test to
  typecheck/bun-test; new `build-tui` target.
- **CI**: pipeline gates updated to the new make targets; Go setup step removed,
  Bun setup step added.
- **Fresh-machine bootstrap** (`install/remote-install.sh` → `bin/dot install`):
  remote machines may have **neither Go nor Bun**. Resolution order:
  1. Prefer a **prebuilt release binary** downloaded during bootstrap (no runtime needed).
  2. Else, if Bun ≥ some minimum version is present, build from source via
     `bun install && bun build --compile` inside `bin/dot`'s fallback path.
  3. If neither is available, print actionable guidance ("run the official bootstrap
     script which installs Bun") instead of failing silently.
  This ordering MUST be stated in the spec delta and verified by a Bats test or
  documented manual check.
- **Docs**: README/install docs referencing `make go-test` or the Go toolchain get
  updated pointers.
- **Unchanged**: Homebrew Bundle flows, `config/` assets, `system/defaults/`,
  shell linting (shellcheck/shfmt), and the Bats suite's external behavior contracts.

## Rollback Plan

This change deletes Go code, so rollback must be git-based, not file-restoration ad hoc:

1. **Single PR, revertible.** Land the entire migration in one merge commit; `git revert`
   restores Go sources, `go.mod`, Makefile targets, CI config, and `bin/dot` atomically.
2. **Tag before deletion.** Tag `pre-go-removal` at the last Go-only commit so the old
   binary remains buildable indefinitely even after history pruning policies change.
3. **Parallel availability window.** Keep the pre-built Bun binary and the tagged Go
   build both referenced in release artifacts until one full bootstrap cycle succeeds
   on a clean machine; only then consider the migration settled.
4. **Trigger conditions for rollback**: fresh-machine bootstrap fails to obtain/build
   the binary, Bats integration tests regress against the TS implementation, or the
   Ink port diverges behaviorally from the documented key/UI contract.

## Risks

| Risk | Mitigation |
| ------ | ----------- |
| Ink/Bun TUI rendering differs from Bubbletea (viewport, ANSI styling, resize) | 1:1 port contract + ported TUI key-handling tests; visual smoke test on macOS Terminal/iTerm before merge |
| `bun build --compile` binary size/startup acceptable? | Measure early in tasks phase; if unacceptable, fall back to invoking `bun run` from source (still no Go) |
| Fresh machines lack Bun and network access to releases | Bootstrap resolution order above (release binary first); document minimum Bun version for source builds |
| Behavioral drift in profile/legacy-migration semantics breaking existing saved profiles | Port the legacy-ID migration table verbatim; round-trip + idempotency tests are mandatory ports |
| CI flakiness from new Bun setup steps | Pin Bun version in CI; keep Bats suite as the behavioral gate it is today |
| Contributors unfamiliar with React-for-terminals | Ink model maps closely to the existing Elm-architecture Bubbletea model; document the mapping in the design phase |

## Success Criteria

- [ ] No Go files, `go.mod`, or Go toolchain references remain in the repo.
- [ ] Every existing Go unit test has a passing bun:test port (profile, migration,
      plan, execute, TUI keys, manifest stability).
- [ ] `make check && make lint && bun test && make test` passes in CI.
- [ ] `bin/dot tui` works on a machine with only the compiled binary (no Go, no Bun).
- [ ] A fresh-machine bootstrap succeeds following the resolution order in this proposal.
- [ ] Saved profiles created by the Go version load identically under the TS version,
      including legacy-ID migration.

## Estimated Footprint

~900 lines of TypeScript replacing ~900 lines of Go, plus ~450 lines of bun:test ports,
plus Makefile/CI/`bin/dot` rewiring (small diffs). Net repository language count: two
(Bash + TypeScript) down from three.

## Next Step

Specs phase: write deltas with Given/When/Then scenarios and RFC 2119 keywords for
manifest, profile (+legacy migration), plan/execute, and TUI interaction contracts.
