# Tasks — ink-ui-steps-1-2

Rewrite installer-TUI steps 1/2 (`tools/tui/src/tui.tsx`) onto @inkjs/ui `MultiSelect`
components with a thin value adapter, rework the frame tests on the `apply.test.tsx`
technique, and bump `TUI_VERSION` v4 → v5 (four marker sites) with a rebuilt binary.
Normative inputs: proposal, installer-tui delta spec, design (ADRs 1–6 reviewer-approved).
Strict TDD is on: every implementation task is preceded by its RED test task.
Per-change specs remain in `openspec/changes/…`; canonical archiving is deferred.

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines (additions + deletions) | ~800–1100 total: Phase 1 ~200–300, Phase 2 ~550–750, Phase 3 ~8–14 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (unit layer) → PR 2 (component swap + frame rework) → PR 3 (markers + rebuild + gates) |
| Delivery strategy | auto-chain |
| Chain strategy | feature-branch-chain (PR 2 is a flagged size exception; see notes) |

```text
Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High
```

**Basis and notes**

- Line basis: design §8 diff sketch (`tui.tsx` −250/+260, `tui.test.tsx` −300/+330, markers ≈ 5 lines) and proposal size hint (~500–900 changed lines).
- PR 1 is additive only (adapters/shapers/quit helper + unit tests), ~200–300 lines — within budget. PR 3 is mechanical, ~8–14 lines — within budget.
- PR 2 (component swap + frame-test rework) lands ~550–750 changed lines and **exceeds the 400-line budget**: flagged size exception, because design §10 approved the `tui.tsx` + `tui.test.tsx` pair as one commit, and splitting it forces a temporary mixed string/component intermediate (step 2 still string-based, viewport machinery half-deleted) that is harder to review than a single coherent swap. If reviewers reject the exception, Phase 2 must split into step-1 swap (PR 2) and step-2 swap + machinery deletion (PR 3), pushing markers to PR 4.
- **Decision needed before apply:** ratify the 3-PR boundary and the PR-2 size exception; the 3-PR shape is a deviation from the design's 2-commit rollout §10 (content unchanged, chain shape only).
- Chain lands on a shared feature branch (`feat/ink-ui-steps-1-2`, repo convention) merged to main at the end; every PR ends green (v4 markers hold through PR 2; resolver still rebuilds on mismatch, so no drift risk).

## Phase 1 — Adapter & option-shaping unit layer (PR 1)

Additive only: new pure functions and their unit tests in `tools/tui/src/tui.test.tsx`.
The old reducer/string views keep rendering during this phase.

- [x] 1.1 RED — `adaptStepOne` unit tests <!-- sdd-owner: implementation -->

Write tests in `tools/tui/src/tui.test.tsx` for `adaptStepOne(value, context)`:
every locked package id (`zsh`, `fzf`, `git`, `gh`, `tmux`) and pseudo-step id
(`zsh-setup`, `git-signing`) maps to `true` regardless of `value`; every toggleable
row id maps to `value.includes(id)`; special installers (`code`, `duti-defaults`,
`dock`, `macos`) are absent → `false`. Suite must go RED (export missing).
Acceptance: spec scenario "Confirm applies the unchanged pipeline" + ADR-1/ADR-3 —
locked reinsertion is the applyConfirmed-critical invariant (dropping locked ids
silently skips brew essentials). <!-- sdd-owner: implementation -->

- [x] 1.2 RED — `adaptStepTwo` unit tests <!-- sdd-owner: implementation -->

Write tests for `adaptStepTwo(value)`: returns `{ [name]: true }` per element; a
multi-target link name is exactly ONE key (never per-target keys, empty array → `{}`).
Acceptance: base "Multi-target names toggle as one unit" + design §6.2 (replaces the
deleted `toggleLink` semantics in unit form). <!-- sdd-owner: implementation -->

- [x] 1.3 RED — Option-shaping tests (`toggleableRowsForStep`, `defaultValuesFor`) <!-- sdd-owner: implementation -->

Write tests: `toggleableRowsForStep(context)` returns `toolRowsGrouped` minus locked/
pseudo rows (never `zsh`, `fzf`, `git`, `gh`, `tmux`, `zsh-setup`, `git-signing`);
`defaultValuesFor(context, initialSelected)` pre-checks `row.default || row.installed`
rows plus the `initialSelected` seam. Acceptance: spec scenarios "User toggles one
package inside a topic group" / "Locked row cannot be deselected" + ADR-1 (locked rows
never enter the component options). <!-- sdd-owner: implementation -->

- [x] 1.4 RED — `quitRequested` unit tests <!-- sdd-owner: implementation -->

Write tests for `quitRequested(input, key)`: `q` with no ctrl/meta and `ctrl+c` → quit;
up/down arrows, space, return, uppercase `Q`, and ctrl-plus-other → not quit. Acceptance:
ADR-2's quit-only App contract; supersedes the `mapInkKey` describe (design §6.2). <!-- sdd-owner: implementation -->

- [x] 1.5 GREEN — Implement adapters, shapers, quit helper <!-- sdd-owner: implementation -->

Implement and export `adaptStepOne`, `adaptStepTwo`, `toggleableRowsForStep`,
`defaultValuesFor`, `quitRequested` in `tools/tui/src/tui.tsx` (pure functions; no
state coupling yet). Do NOT delete reducer/views. Acceptance: `cd tools/tui && bun test`
green — new describes pass and the existing suite is untouched and passing. <!-- sdd-owner: implementation -->

- [x] 1.6 TRIANGULATE — Boundary cases <!-- sdd-owner: implementation -->

Add boundary tests: `adaptStepOne([], context)` still returns locked/pseudo → `true`
(nothing selected = essentials only); `defaultValuesFor` override via `initialSelected`;
`adaptStepTwo` round-trip with duplicate names is idempotent. Acceptance: delta spec
"Nothing selected means nothing offered" precondition (locked block always installed,
ADR-3). <!-- sdd-owner: implementation -->

- [x] 1.7 REFACTOR + verify — PR 1 gate <!-- sdd-owner: implementation -->

Prettier-clean `tui.tsx`/`tui.test.tsx`; confirm the old App still renders unchanged
(additive-only PR); run `cd tools/tui && bun test` and `tsc --noEmit -p tools/tui`.
Acceptance: PR 1 self-contained, green, ≤ ~300 changed lines, reviewable alone. <!-- sdd-owner: implementation -->

## Phase 2 — Component swap + frame-test rework (PR 2)

Rewrite `App` on @inkjs/ui `MultiSelect` (verified v2.0.0 in
`tools/tui/node_modules/@inkjs/ui`) and rework `tui.test.tsx` frame tests on the
`apply.test.tsx` technique (`chalk.level = 1` at module top, ink-testing-library,
stripAnsi for words, color-close/label assertions never bare `\x1b[0m`,
`afterEach(cleanup)`, `fixedSize` 100×60). Keep `initialState` (trimmed shape),
`linkRowsForStep`, `stepTwoRows` and their surviving tests.

- [x] 2.1 RED — Step-1 frame tests + initialState trim <!-- sdd-owner: implementation -->

Rework step-1 describes in `tui.test.tsx`: locked block stays byte-identical after
pressing space (never loses its check, never toggles); former baseline defaults
(`ghostty`, `lazygit`, `hunk`, `yazi`, `neovim`) render pre-checked (green
color-close/label assertion) and CAN be unchecked; space toggles the focused option
and leaves sibling rows' labels byte-identical. Trim the `initialState` describe to
`{ step, selected, checked, submitted }` (drop cursor/width/height); keep
`linkRowsForStep`/`stepTwoRows` shaping tests unchanged; delete the `toolView` and
`reducer toggling` describes (removed-block references). Acceptance: delta spec
"Frame tests assert the component contract" scenario + "Locked row cannot be
deselected" / "Old baseline extras are pre-checked but removable"; suite RED against
the current string App.

- [x] 2.2 RED — Step-2 frame tests + quit/exit-10 frames <!-- sdd-owner: implementation -->

Rework step-2 describes: options are `offeredLinks(...).main` only (assert
agents/`open-code`/unselected-area names absent — ADR-4), all unchecked at mount,
space toggles a link row, enter submits with the checked set, multi-target name is
ONE row (value = name). Add quit-frame tests on BOTH steps: `q` and `ctrl+c` →
`onSubmit` never called; keep the exit-10 zero-writes assertion (roundExitCode
null/unsubmitted → 10 in `main.test.ts`, which survives untouched, plus the
applyConfirmed dry-run zero-write proof). Delete `linkView`, `toggleLink`, and
`mapInkKey` describes (removed-block references). Acceptance: delta spec "Quit at the
link step" (exit 10, zero writes) + "Space toggles and enter submits" + "Link list
follows tool selection"; suite RED against current App.

- [x] 2.3 GREEN — App rewrite on MultiSelect <!-- sdd-owner: implementation -->

Rewrite `App` in `tools/tui/src/tui.tsx`: slim `TuiState` to
`{ step, selected, checked, submitted }`; render an inert always-checked `LockedBlock`
row block ABOVE the step-1 `MultiSelect` (static rows from `toolRowsGrouped` where
`locked || pseudo`; never part of `options` — ADR-1); step-1 `MultiSelect` with
`options = toggleableRowsForStep(context)`, `defaultValue = defaultValuesFor(context,
initialSelected)`, `visibleOptionCount` sized from `fixedSize`, `onSubmit → selected =
adaptStepOne(value, context); step = 2`; step-2 `MultiSelect` with
`options = stepTwoRows(context, selected)` (`.main` only — ADR-4), `defaultValue = []`,
`onSubmit → checked = adaptStepTwo(value); submitted = true`; App-level `useInput`
owning ONLY `q`/`ctrl+c` → `exit()` without submitting (ADR-2); `useMemo`-ized option
arrays keyed on each step's input data (ADR-6); enter on an empty step-2 list still
fires `onSubmit([])` → `checked = {}` (ADR-5). Delete `Action`/`reducer`/`reduceKey`/
`mapInkKey`/`MappedKey`/`InkKeyFlags`, `toolView`/`linkView`/`viewportOf`/`LOCK_MARK`/
`selectedMark`/`linkRowLine`, `toggleLink`, and cursor/width/height bookkeeping.
Keep `initialState` (trimmed), `linkRowsForStep`, `stepTwoRows`, `AppProps`, the
submitted → `onSubmit(state)` + `exit()` effect. Acceptance: delta spec "Per-tool
toggleable rows" / "Component-filtered config-link step" / "Adapted selection feeds
the apply pipeline" scenarios; `bun test` green.

- [x] 2.4 TRIANGULATE — Corner cases <!-- sdd-owner: implementation -->

Confirm/complete edge coverage: space on step-1 locked block leaves it byte-identical
and locked ids are still `true` in `selected` at submit (adapter reinsertion);
empty step-2 options → enter confirms with `checked = {}` and `applyConfirmed` tolerates
it (ADR-5 + "Nothing selected means nothing offered"); quit between step-1 submit and
step-2 mount → exit 10 (quit handler mounted throughout); `ctrl+c` during apply stays a
real SIGINT → exit 1 distinction preserved. Acceptance: design §6.2 scenario-coverage
map complete; no regression in `roundExitCode` contract tests.

- [x] 2.5 REFACTOR + verify — PR 2 gate <!-- sdd-owner: implementation -->

Prettier-clean both files; confirm untouched surfaces: `manifest.ts` helpers,
`install/manifest.sh`, `apply.tsx`, apply phase, headless `-apply -profile`; run
`cd tools/tui && bun test` + `tsc --noEmit -p tools/tui`. Acceptance: PR 2
self-contained and green with v4 markers still in place (marker bump is PR 3);
`offeredLinks` still returns `agents` (manifest untouched) while step-2 options stay
pruned (ADR-4).

## Phase 3 — TUI_VERSION v4 → v5, rebuild, final gates (PR 3)

Four marker sites, per design §7 (the `main.test.ts` pin is the necessary 4th,
test-side mirror of the runtime trio — without it `bun test` fails on first run).

### 3.1 RED — Bump the unit pin first

In `tools/tui/src/main.test.ts` (~L174) change to
`expect(TUI_VERSION).toBe("dot-tui-context-v5")`. Acceptance: `bun test` RED on the
TUI_VERSION contract before any runtime site moves (strict-TDD ordering; design §7
interpretation note). <!-- sdd-owner: implementation -->

### 3.2 GREEN — Bump the three runtime/resolver sites together

Update in one change: `tools/tui/src/main.ts` (~L568) `TUI_VERSION` const →
`"dot-tui-context-v5"`; `bin/dot` (~L188) resolver comparison expected marker → v5;
`test/tui-resolver.bats` stub fixtures (~L37 and ~L71) `--version` answers → v5.
Acceptance: delta spec "Version-marker rebuild contract" scenario "Stale binary
triggers rebuild"; `bun test` green; source marker == resolver expectation == stub
answers. <!-- sdd-owner: implementation -->

### 3.3 Rebuild + resolver verification

Run `make build-tui`; verify `bin/dot-tui --version` prints `dot-tui-context-v5`; run
the bats resolver suite and confirm the stale-rebuild scenario still exercises the
rebuild path (v4-answer stub → rebuild → v5 report). Acceptance: rebuilt binary reports
the v5 marker and the resolver does not spuriously rebuild when markers match. <!-- sdd-owner: implementation -->

### 3.4 Final gates — full config gate

Run `cd tools/tui && bun test`, `tsc --noEmit -p tools/tui`, `bats test/` (resolver
suite green with v5 stubs), `make lint`, then the full gate
`make check && make lint && make test`. Acceptance: proposal success criteria +
`openspec/config.yaml` verify `test_command` all green. <!-- sdd-owner: implementation -->

## Parent lifecycle gates (post-apply)

Grouped separately; bounded review per PR, then chain merge.

- [ ] Start or reuse bounded review of PR 1 (unit layer): `adaptStepOne` locked-reinsertion invariant (the applyConfirmed-critical path) and the `quitRequested` contract. <!-- sdd-owner: parent -->
- [ ] Start or reuse bounded review of PR 2 (component swap): ADR-1 inert-block realization (locked rows never options), ADR-4 agents pruned from step 2, ADR-5 empty-list confirm, ADR-6 memoization, and the frame-test technique parity with `apply.test.tsx`. <!-- sdd-owner: parent -->
- [ ] Start or reuse bounded review of PR 3 (markers): all four v5 sites + rebuilt binary version report and bats stale-rebuild coverage. <!-- sdd-owner: parent -->
- [ ] Lifecycle gate: merge the feature-branch chain to main and confirm the rollback plan (git revert; restore v4 in all four sites; `make build-tui`) is attached to the final PR. <!-- sdd-owner: parent -->

## Out-of-scope guardrails (do not touch)

- `tools/tui/src/manifest.ts` helpers, `install/manifest.sh`, context schema — no topic/context changes (fixed decision 5).
- `apply.tsx`, apply phase, headless `-apply -profile` behavior — unchanged.
- Canonical `openspec/specs/` archiving — deferred; specs stay per-change.
- No new dependencies or `package.json` churn (@inkjs/ui ^2.0.0 already installed); Prettier is canonical for TS/TSX formatting.
