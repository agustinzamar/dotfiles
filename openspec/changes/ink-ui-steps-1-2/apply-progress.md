# Apply Progress — ink-ui-steps-1-2 (Phase 2, PR 2)

Change: `ink-ui-steps-1-2` in `/Users/agustin/dotfiles`. Direct-on-main delivery
(user override; no PRs this run). Scope: Phase 2 ONLY (tasks 2.1–2.5). Phase 1
(adapter/shaping/quit unit layer, tasks 1.1–1.7) landed previously — 164 bun
tests green, `.gitignore`-clean surfaces. No prior apply-progress file existed;
this file starts here and records Phase 2.

## Structured status consumed (native engine, authoritative)

```yaml
schemaName: gentle-ai.sdd-status (spec-driven)
changeName: ink-ui-steps-1-2
artifactStore: openspec
changeRoot: openspec/changes/ink-ui-steps-1-2
artifacts: proposal done / specs done / design done / tasks done / applyProgress done (this file)
taskProgress: total 16, complete 12 (7 Phase-1 + 5 Phase-2), pending 4 (parent lifecycle gates only)
deferredParentActions: 4 unchecked parent rows (post-apply review/merge, not owned by sdd-apply)
taskArtifactErrors: []
applyState: ready
dependencies: proposal/specs/design/tasks/apply all_done|ready; verify blocked (parent review required); archive blocked
actionContext:
  mode: repo-local
  workspaceRoot: /Users/agustin/dotfiles
  allowedEditRoots: ["/Users/agustin/dotfiles"]
  warnings: []
nextRecommended: apply → completed → parent-lifecycle
isNonAuthoritative: false
```

All edits stayed inside `/Users/agustin/dotfiles`. No `workspace-planning` mode,
no edit-root warnings.

## Completed tasks (2.1–2.5) with persisted checkbox updates

All five rows marked `- [x]` in `openspec/changes/ink-ui-steps-1-2/tasks.md`
(verified by re-read after editing; single terminal
`<!-- sdd-owner: implementation -->` marker per task, moved onto the checkbox
line to match the Phase-1 convention — the Phase-2/3 task rows were authored as
`### 2.x` headings with the marker dangling at the acceptance-paragraph end, so
no `- [ ]` checkbox existed to flip; heading text and prose preserved verbatim):

- [x] 2.1 RED — Step-1 frame tests + initialState trim
- [x] 2.2 RED — Step-2 frame tests + quit/exit-10 frames
- [x] 2.3 GREEN — App rewrite on MultiSelect
- [x] 2.4 TRIANGULATE — Corner cases
- [x] 2.5 REFACTOR + verify — PR 2 gate

## TDD cycle evidence (strict TDD per openspec/config.yaml)

| Cycle | Evidence |
| --- | --- |
| RED (2.1/2.2) | Reworked `tui.test.tsx` first (component-frame describes, `initialState` key-set trim, `linkRowsForStep`/`stepTwoRows` shaping, quit frames, TRIANGULATE full-flow). Against the string-based App: 9 failures — `initialState` slim, 4 step-1 frame, 3 step-2 frame, 1 full-flow; 26 pass (surviving Phase-1 unit layer). |
| GREEN (2.3) | Rewrote `App` on `MultiSelect` + `LockedBlock`; slimmed `TuiState`; deleted `Action`/`reducer`/`reduceKey`/`mapInkKey`/`MappedKey`/`InkKeyFlags`/`toolView`/`linkView`/`viewportOf`/`LOCK_MARK`/`selectedMark`/`linkRowLine`/`toggleLink` + cursor/width/height. Gate: `cd tools/tui && bun test` → 158 pass / 0 fail (155 pass after first GREEN, 3 frame-test assertion bugs fixed — see deviations). |
| TRIANGULATE (2.4) | Same `bun test` run covers: locked lines byte-identical across 5 keypresses; locked ids `true` in submitted `selected`; `7zip` (installed:true) pre-checked; lazygit removable; empty step-2 list (fixture `links: []`) confirms with `checked = {}` (ADR-5); quit at step 1 and step 2 (`q` and `ctrl+c`) never call `onSubmit`. |
| REFACTOR (2.5) | `bunx prettier --write src/tui.tsx src/tui.test.tsx`; `bunx prettier --check src` clean; `./node_modules/.bin/tsc --noEmit -p .` exit 0; `cd tools/tui && bun test` re-run after formatting → 158 pass / 0 fail (539 expects); repo `make lint` exit 0 (prettier + shellcheck + shfmt). |

Final gate state: `bun test` 0 / `tsc --noEmit` 0 / `prettier --check src` clean /
`make lint` 0.

## Files changed

- `tools/tui/src/tui.tsx` — App rewrite on `@inkjs/ui` `MultiSelect` v2.0.0
  (verified `use-multi-select-state.js` reset-to-defaults on deep-inequal options,
  empty-list `onSubmit([])`, global `isDisabled`, `{label,value}` Option surface).
- `tools/tui/src/tui.test.tsx` — frame rework on the `apply.test.tsx` technique;
  deleted `toolView`/`reducer`/`linkView`/`toggleLink`/`mapInkKey` describes and
  the `rowIndex`/`key`/`resize` helpers; added shaping + component-frame
  describes.
- `openspec/changes/ink-ui-steps-1-2/tasks.md` — 2.1–2.5 marked `[x]` (see below).
- `openspec/changes/ink-ui-steps-1-2/apply-progress.md` — this file.

Untouched (verified via `git status --porcelain`, empty for all of these):
`tools/tui/src/main.ts` (v4 marker intact → Phase 3), `main.test.ts` (roundExitCode
contract + applyConfirmed dry-run zero-write proof green as-is), `manifest.ts`,
`apply.tsx`, `bin/dot`, `test/tui-resolver.bats`, `install/manifest.sh`.

## Deviations from design

1. **`Text dim` → `Text dimColor`** in `tui.tsx` hint lines: installed ink v6
   (`build/components/Text.d.ts`) exposes Chalk-v5 naming; `dim` is not a valid
   prop there. Visual intent (a dim hint line) preserved.
2. **`quitRequested` key param typed `Partial<Key>` from ink** instead of the
   deleted `InkKeyFlags`/`MappedKey` types: ink's `Key` has all-required fields,
   so the Phase-1 unit call sites (`{}`, `{ctrl: true}`) need the partial form.
   Deletion list honored; App wiring unchanged.
3. **tasks.md checkbox mechanics**: Phase-2 task rows were `###` headings without
   `- [ ]` lines; converted the five headings to `- [x]` checkbox rows with the
   single terminal owner marker on the checkbox (Phase-1 convention) so completion
   is machine-visible. No content changed; Phase 3 heading rows and the four
   parent gate rows untouched.
4. **Step-2 ghostty label assertion** uses the full `ghostty (2 targets)` label
   inside the ANSI color segment (the color wraps the whole label, not just the
   bare name).
5. **Option-order correction in the step-1 toggle test**: `7zip` (topic `core`,
   installed) is option index 1 — the fixture's core group is rendered as
   `ghostty, 7zip, lazygit, hunk, yazi, …`, so the byte-identical sibling trio is
   ghostty/7zip/hunk and the post-toggle focus lands on hunk then yazi.

Design claims verified against installed `@inkjs/ui@2.0.0` (ADR-1/5/6):
`MultiSelectProps.options` is `{label,value}[]` with no per-option disabled;
`isDisabled` is component-global; empty options still fire `submit() →
onSubmit([])`; options deep-change resets to defaults (memoized per step, ADR-6).

## Remaining tasks (exact unchecked lines in tasks.md, all parent-owned)

```text
- [ ] Start or reuse bounded review of PR 1 (unit layer): `adaptStepOne` locked-reinsertion invariant (the applyConfirmed-critical path) and the `quitRequested` contract. <!-- sdd-owner: parent -->
- [ ] Start or reuse bounded review of PR 2 (component swap): ADR-1 inert-block realization (locked rows never options), ADR-4 agents pruned from step 2, ADR-5 empty-list confirm, ADR-6 memoization, and the frame-test technique parity with `apply.test.tsx`. <!-- sdd-owner: parent -->
- [ ] Start or reuse bounded review of PR 3 (markers): all four v5 sites + rebuilt binary version report and bats stale-rebuild coverage. <!-- sdd-owner: parent -->
- [ ] Lifecycle gate: merge the feature-branch chain to main and confirm the rollback plan (git revert; restore v4 in all four sites; `make build-tui`) is attached to the final PR. <!-- sdd-owner: parent -->
```

## Workload / PR boundary

- Diff scope is exactly `tui.tsx` + `tui.test.tsx` (495 insertions / 526
  deletions). This is the flagged PR-2 size exception (~550–750 line forecast;
  actual ≈ 1021 changed lines) — per tasks.md the design approved the
  `tui.tsx` + `tui.test.tsx` pair as one commit; splitting would force a
  temporary mixed string/component intermediate.
- No commits this run (parent owned). v4 markers still in place in all four
  sites → resolver/rebuild contract unharmed; Phase 3 (marker bump + rebuild +
  gates) is untouched for the next phase.
- `offeredLinks` still returns `agents` (manifest untouched, asserted by the
  surviving `linkRowsForStep` shaping test) while step-2 options stay pruned
  (ADR-4).

## Notes for verify

- Quit/exit-10: compositional proof — `roundExitCode` (null/unsubmitted → 10)
  and `applyConfirmed` dry-run zero-write assertions live untouched in
  `main.test.ts`; new frame tests prove `onSubmit` (the only bridge to
  `applyConfirmed`) never fires on `q`/`ctrl+c` from either step.
- `ctrl+c` during apply stays a real SIGINT → exit 1: `ApplyScreen` mounts no
  `useInput` (covered by the untouched mid-apply interruption tests in
  `main.test.ts`); during steps 1/2 raw mode is on, so `ctrl+c` routes to the
  App quit handler → exit 10.

## Phase 3 — TUI_VERSION v5 markers, rebuild, final gates

- main.test.ts unit pin bumped first (RED), then main.ts const + bin/dot resolver + tui-resolver.bats stubs (GREEN); 5/5 sites v5, 0 v4.
- `make build-tui` -> `bin/dot-tui --version` => `dot-tui-context-v5`.
- Gates: bun 158/158, tsc clean, prettier clean, batcheck/lint clean, bats 86/86.
