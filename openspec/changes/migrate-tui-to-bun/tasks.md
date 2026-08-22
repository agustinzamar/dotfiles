# Tasks: migrate-tui-to-bun

Mechanical Go→Bun/TypeScript port following the seven design ADRs. Phases 1–5 add `tools/tui/` without touching any existing file, so every intermediate commit keeps the Go installer fully working. Phase 6–7 perform the cutover; Go deletion is last, behind the `pre-go-removal` tag.

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | ~2,000–2,400 total (Ph1 ~350 · Ph2 ~450 · Ph3 ~380 · Ph4 ~550 · Ph5 ~120 · Ph6 ~120 · Ph7 ~250 incl. ~900 deleted Go lines netting negative · Ph8 docs-only) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 = Phases 1–5 (additive TS port, Go untouched) → PR 2 = Phases 6–8 (cutover, wiring, Go deletion) |
| Delivery strategy | ask-on-risk surfaced as **ask-always**: user wants to be asked whenever review-budget risk appears — it appears here (High), so decide before apply |
| Chain strategy | pending |

```text
Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High
```

Note on rollback tension: design.md's rollback plan assumes one revertible PR, which conflicts with the 400-line budget. If the user accepts chaining, keep PR 2 as a single revertible merge commit and tag `pre-go-removal` inside it exactly as designed — the tag restores Go regardless of PR count. This trade-off needs an explicit user decision (ask-always).

---

## Phase 1 — Scaffold `tools/tui/` and port the manifest

- [x] 1.1 Scaffold `tools/tui/package.json` (name `dot-tui`, private, `engines.bun >=1.2`, deps `react`+`ink`, devDeps `typescript`, `ink-testing-library`, `@types/react`, `@types/bun`) and commit the resulting `bun.lockb`. Acceptance: `bun install --frozen-lockfile` succeeds in CI-reproducible form; runtime dep set matches ADR-6 exactly. <!-- sdd-owner: implementation -->
- [x] 1.2 Create root `.bun-version` pinning the Bun version and `tools/tui/tsconfig.json` (strict, `jsx: react-jsx`, `moduleResolution: bundler`, `noEmit`). Acceptance: `tsc --noEmit -p tools/tui` runs clean on an empty `src/`; `.bun-version` is the single version source of truth per ADR-3. <!-- sdd-owner: implementation -->
- [x] 1.3 RED: write `tools/tui/src/manifest.test.ts` porting `manifest_test.go` — catalog has exactly 31 entries, unique ids, required fields present, baseline (`base`,`shell`,`git`,`terminal`) required, git covers Hunk links+commands, php uses Herd not `brew install php`. Acceptance: test fails because `manifest.ts` does not exist (installer-manifest spec: all six requirements' scenarios covered). <!-- sdd-owner: implementation -->
- [x] 1.4 GREEN: create `tools/tui/src/manifest.ts` with the typed `Component` interface and `COMPONENTS` array transcribed verbatim from `manifest.go`. Acceptance: `bun test` green; catalog assertions satisfy installer-manifest scenarios "Catalog size and required fields are stable", "No duplicate IDs", "Git component covers Hunk", "PHP component uses Herd". <!-- sdd-owner: implementation -->
- [x] 1.5 Add the aggregate-absence assertion (ids `communication`/`desktop`/`media`/`databases` not in catalog) and remove `brew install go` from `base`'s commands per the ADR-3 manifest consequence, keeping `xcode-select --install`. Acceptance: new test asserts none of the four legacy ids exist and base's commands exclude `go`; satisfies installer-manifest "Aggregates absent from catalog" and proposal success criterion "no Go toolchain references". <!-- sdd-owner: implementation -->

## Phase 2 — Port profile persistence and legacy migration

- [x] 2.1 RED: write `tools/tui/src/profile.test.ts` using `fs.mkdtemp` under `os.tmpdir()` — defaults match manifest, missing-file→defaults, unknown-id rejection on load and save, disabled-required rejection, malformed JSON / missing `components` rejected, normalization fills false and forces required true. Acceptance: fails before `profile.ts` exists; maps 1:1 onto installer-profile scenarios under "Default Profile Derivation", "Load Missing File Returns Defaults", "Profile Validation On Save", "Load Normalization". <!-- sdd-owner: implementation -->
- [x] 2.2 RED: extend `profile.test.ts` with atomic-save cases — round-trip equals saved selection after normalization, bytes end with exactly one `\n`, no temp files remain in the target dir, save creates a missing target directory. Acceptance: satisfies installer-profile "Save round-trips through tmp-and-rename". <!-- sdd-owner: implementation -->
- [x] 2.3 RED: write `tools/tui/src/profile.migration.test.ts` mirroring `profile_migration_test.go` — each of the four aggregate tables expands its exact child id list when true, enables nothing when false, key always removed, idempotent second run reports unchanged, load-persists-migrated writes back only when changed. Acceptance: satisfies installer-profile "Legacy Aggregate Migration", "Migration Idempotency", "Load Persists Migrated Data" (all nine scenarios). <!-- sdd-owner: implementation -->
- [x] 2.4 GREEN: implement `tools/tui/src/profile.ts` — `defaultProfile`, `loadProfile` (missing→defaults, parse→migrate→reject unknown→fill false→force required→persist only on change), `saveProfile` (validate first, mkdir recursive, `JSON.stringify(p,null,2)+"\n"`, tmp `${dir}/.profile-${pid}-${uuid}` then same-directory rename, unlink on failure), `migrateProfileData` returning `{profile, changed}` with the child-list table copied verbatim. Hand-rolled validation, no zod (ADR-7). Acceptance: `bun test` green across both profile test files. <!-- sdd-owner: implementation -->

## Phase 3 — Port planning and sequential execution

- [x] 3.1 RED: write `tools/tui/src/plan.test.ts` planner cases with an injected env map — DFS dependency order (deps before dependents), shared dependency emitted once, unselected components produce no tasks, applied-set components excluded, `xcode-select --install` omitted iff xcode-select detected, brew-prefixed component fully skipped with reason "Homebrew is not installed" when brew absent and planned normally when present. Acceptance: satisfies every scenario in installer-plan spec. <!-- sdd-owner: implementation -->
- [x] 3.2 RED: extend `plan.test.ts` executor cases with an async fake runner — strictly sequential order, progress callback fires once before each executed task only, failure blocks dependents ("dependency failed") while independent components continue, cancellation records remaining as skipped/"cancelled", one result per task with status/output/timestamps, summarize aggregates per component (failed whole-component, skipped reason, multi-failure output concatenation, no entry for unplanned components). Acceptance: satisfies every scenario in installer-execute spec. <!-- sdd-owner: implementation -->
- [x] 3.3 GREEN: implement `tools/tui/src/plan.ts` exporting the ADR contract surface — `detectEnvironment()` (PATH scan, no execution), `plan()`, `executeWithProgress(tasks, runner, signal?, progress?)`, `summarize()`, and `type Runner`. Production runner: `Bun.spawn(["sh","-c",op])` with `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_ENV_HINTS=1`, merged stream capture, AbortSignal checked before each task. Acceptance: `bun test` green; runner env matches installer-execute "Task runs via sh and captures combined output". <!-- sdd-owner: implementation -->

## Phase 4 — Port the Ink TUI

- [x] 4.1 RED: write `tools/tui/src/tui.test.tsx` pure-view/reducer unit ports first — `visibleIndices`, `firstIndexInCategory`, `clampViewport`, `counts`, `reviewRows`, `stateMark` free functions plus reducer transitions for tab/left/right pane toggle, cursor clamping at edges, sidebar navigation jumping component cursor to category start. Acceptance: satisfies dot-tui "Pane Switching And Navigation" scenarios. <!-- sdd-owner: implementation -->
- [x] 4.2 RED: extend `tui.test.tsx` with ink-testing-library frame tests — initial screen (categories in manifest order, default/required marked `x`, no `✓`), applied rows show green `✓`, space toggles ordinary components only, required/applied immune, `a`/`n` category all/none skip required, search filters case-insensitively by label/category with empty-query restore, no-match message with query and inert keys, enter on empty result does not open review. Acceptance: satisfies dot-tui "Two-Pane Selection Layout", "Toggle Rules For Space", "Search Filtering" scenarios; frames assert raw-ANSI strings per ADR-2. <!-- sdd-owner: implementation -->
- [x] 4.3 RED: add review-flow and viewport frame tests — review lists only selected-not-applied grouped by category with counts, submit (enter/y) vs cancel (esc), q quits, "nothing to install" empty state, long lists scroll keeping cursor visible with "↑ more"/"↓ more" indicators and footer always last. Acceptance: satisfies dot-tui "Review Flow" and "Viewport Keeps Footer Visible" scenarios. <!-- sdd-owner: implementation -->
- [x] 4.4 GREEN: implement `tools/tui/src/tui.tsx` — `TuiState` mirroring the Go `Model` field-for-field in one `useReducer`, `useInput` key switch with review-mode precedence first, `useStdoutDimensions`→resize dispatch, pure view helpers rendering through `<Text>` with the exact ANSI constants from `tui.go` (`ansiDim`/`ansiGreen`/`ansiYellow`/`ansiBold`/`ansiReverse`), `useApp().exit()` after submit. Acceptance: `bun test` green; rendered frames byte-match the documented UI contract. <!-- sdd-owner: implementation -->

## Phase 5 — Entrypoint and flag parity

- [x] 5.1 RED: add a thin Bats-level harness expectation first — document (as a failing placeholder test or checklist item in this task) the exact stdout strings `-profile/-apply/-dry-run` must emit (`skip <id>: <reason>`, `<label>: <command>`, `🔧 %s...`, `✅/⚠️/❌` result lines, link confirmations); direct unit coverage lives in Phases 2–3, `main.ts` stays thin per ADR-1. Acceptance: string constants enumerated and traceable to dot-cli-bootstrap "Non-Interactive Flag Mode" scenarios. <!-- sdd-owner: implementation -->
- [x] 5.2 Implement `tools/tui/src/main.ts` — flag parsing via `node:util.parseArgs` accepting single-dash forms (`-profile`, `-apply`, `-dry-run`), flag pipeline (load→print skips then plan→stop unless `-apply`→execute→save→`dot link` with `DOT_PROFILE`→non-zero exit on failure), and the interactive loop mounting fresh `<App initialApplied={…}>` rounds per the ADR-2 sequence diagram (quit-without-submission exits cleanly, no write/no link). Acceptance: behavior parity with `cmd/dot-tui/main.go` verified by reading side-by-side; satisfies dot-cli-bootstrap flag-mode and interactive-loop requirements (Bats gate comes in Phase 6/8). <!-- sdd-owner: implementation -->

## Phase 6 — Build target, resolver rewiring, Makefile/CI swap

- [x] 6.1 Add Makefile targets: `build-tui` (per ADR-3: frozen-lockfile install + `bun build --compile --minify src/main.ts --outfile $(DOTFILES_DIR)/bin/dot-tui`), rename `go-test`→`bun-test`, swap `check`'s `go vet`→`tsc --noEmit -p tools/tui` (keep `bash -n`), update `.PHONY`. Add `bin/dot-tui` to `.gitignore`. Acceptance: `make check && make lint && make bun-test && make test` passes locally with Go still present. <!-- sdd-owner: implementation -->
- [x] 6.2 Measure compiled binary size and cold-start early (design risk): run `make build-tui`, record `bin/dot-tui` size and `time bin/dot-tui -h`; evaluate against the documented fallback (`bun run src/main.ts` behind the same resolver). Acceptance: numbers recorded in this change's notes; fallback decision documented if size/startup is unacceptable. <!-- sdd-owner: implementation -->
- [x] 6.3 RED: write Bats tests for the three resolution scenarios in `test/` — binary present→runs directly (stub-free, no toolchain), binary absent+bun≥min stub→builds from source then launches, binary absent+no bun→guidance naming the official bootstrap script with non-zero exit. Toggle `$DOTFILES_DIR/bin/dot-tui` existence and stub `bun` on PATH. Acceptance: fails against current `bin/dot`; satisfies dot-cli-bootstrap "Binary Resolution Order For bin/dot" scenarios. <!-- sdd-owner: implementation -->
- [x] 6.4 GREEN: rewrite `bin/dot` — introduce single `run_dot_tui()` resolver implementing the exact 3-step order with the `.bun-version` minimum check and ADR-4 guidance text; point `sub_tui` and `run_profile_install` at it; delete all `is_executable go` / `go run` lines. Acceptance: Bats green; `shellcheck -x` and `shfmt -d` clean (`make lint`). <!-- sdd-owner: implementation -->
- [x] 6.5 Update `.github/workflows/test.yml` — replace `setup-go`+`make go-test` with `oven-sh/setup-bun@v2` reading `bun-version-file: .bun-version`, gates become `make lint`, `make check`, `bun test` (from `tools/tui`), `make test`, plus a `make build-tui` smoke step. Acceptance: CI green on the branch; no Go setup step remains (dot-cli-bootstrap "No Go Remains In The Bootstrap Path", CI portion). <!-- sdd-owner: implementation -->

## Phase 7 — Bootstrap path, docs, and Go removal (last)

- [x] 7.1 Update `remote-install.sh`: best-effort release-binary download between clone and `exec bin/dot install` — detect arch (`dot-tui-darwin-arm64`/`-amd64`), curl/wget download, `chmod +x`, execute-check (`-h >/dev/null 2>&1 || rm -f`), silent on any failure so flow falls into the ADR-4 resolver. No Brew-based Bun install topic added. Acceptance: shellcheck/shfmt clean; matches dot-cli-bootstrap resolution step 1 and ADR-5. <!-- sdd-owner: implementation -->
- [x] 7.2 Update README/install docs: replace Go toolchain references (`make go-test`, Go 1.26 prerequisite) with Bun pointers (`.bun-version`, contributor-only `brew install oven-sh/bun/bun`) and release-binary notes. Acceptance: repo-wide grep finds no contributor-facing instruction requiring Go. <!-- sdd-owner: implementation -->
- [x] 7.3 Tag `pre-go-removal` at the last Go-only commit BEFORE any deletion commit. Acceptance: `git tag --points-at` confirms the tag resolves to a tree containing `go.mod`, `cmd/dot-tui/**`, `internal/installer/**` (rollback plan requirement). <!-- sdd-owner: implementation -->
- [x] 7.4 Delete `cmd/dot-tui/**`, `internal/installer/**`, `go.mod`, `go.sum` in one commit immediately after the tag. Acceptance: repo-wide tracked-file search for Go sources/`go.mod`/`go.sum`/`go run cmd/dot-tui` returns nothing (dot-cli-bootstrap "Repo-wide Go absence"); full gate suite still green. <!-- sdd-owner: implementation -->

## Phase 8 — Final verification pass

- [x] 8.1 Verify a saved Go-era profile loads identically: take a profile written by the tagged Go version containing legacy aggregate ids, run `dot install --profile <path> --dry-run` under the TS binary, and diff the printed plan/skips against the Go binary's output on the same input (buildable from the `pre-go-removal` tag). Confirm migrated file round-trips identically on reload. Acceptance: outputs identical; satisfies installer-profile Purpose contract and proposal success criterion on saved profiles. <!-- sdd-owner: implementation -->
- [x] 8.2 Manual Terminal/iTerm visual smoke test before merge: run `dot tui` interactively in both Terminal.app and iTerm2 — two-pane layout, ANSI colors, search, review submit, viewport indicators, resize redraw, one full install→link→reopen round. Acceptance: interaction contract visually matches the Go binary side-by-side; recorded as checklist evidence (proposal risk mitigation). <!-- sdd-owner: implementation -->
- [x] 8.3 Walk all six spec deltas scenario-by-scenario (installer-manifest, installer-profile, installer-plan, installer-execute, dot-tui, dot-cli-bootstrap) and tick off the task/test satisfying each; then verify the proposal's six success criteria checkboxes. Acceptance: every scenario traces to ≥1 passing test or documented manual check; success criteria all met. <!-- sdd-owner: implementation -->
- [x] 8.4 Fresh-machine bootstrap dry validation: on a VM/container without Go or Bun, confirm `remote-install.sh` obtains the binary (release asset or falls into resolver guidance) and `bin/dot tui` reaches the UI. Acceptance: proposal success criterion "fresh-machine bootstrap succeeds following the resolution order"; triggers the documented rollback condition if it fails. <!-- sdd-owner: implementation -->

## Parent-owned lifecycle actions

- [ ] Start or reuse bounded review over the combined diff before merge. <!-- sdd-owner: parent -->
- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above. <!-- sdd-owner: parent -->
