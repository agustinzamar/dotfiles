# Proposal: Ink-UI Steps 1-2 — full @inkjs/ui adoption for installer selection

## Intent

Installer TUI steps 1 and 2 (`tools/tui/src/tui.tsx`) are custom pure-string views (hand-rolled reducer, fixed keys); the apply phase already adopted @inkjs/ui. Rewriting both on components unifies interaction and removes the DIY keyboard/render layer. Supersedes `tui-default-install` ADR-2's pure-string constraint.

## Scope

### In Scope

- Rewrite step 1 (tool selector) and step 2 (config-link checkbox list) in `tools/tui/src/tui.tsx` with @inkjs/ui components; locked rows → `isDisabled`, defaults → initial checked; category headers/🔒 not required (layout free).
- Adopt the component interaction model: keys change (e.g. arrows + enter-to-submit), not byte-identical to the old ones.
- Preserve `selected`/`checked` → `onSubmit` → `applyConfirmed` (exit 0/10; abort = zero writes) via a thin value adapter in `tui.tsx`.
- TUI_VERSION v4→v5 in exactly three places (`tools/tui/src/main.ts`; `bin/dot` ~L188; `test/tui-resolver.bats` ~L37/L71) plus `make build-tui`.
- Rework `tui.test.tsx` frame tests (ink-testing-library, chalk.level=1 + strip-ansi per `apply.test.tsx`); Prettier-clean.

### Out of Scope

- `manifest.ts` helpers, `install/manifest.sh`, context schema: untouched (no topic/context changes).
- Apply phase and headless `-apply -profile`: unchanged.
- Canonical `openspec/specs/` archiving: deferred (specs live per-change).

## Capabilities

- **New**: none.
- **Modified**: `installer-tui` — delta spec in this change folder: steps 1/2 become component-driven with the component keyboard contract; locked = `isDisabled`; pure-string frame output no longer required.

## Approach

Feed a component tree from existing manifest selectors (`toolRowsGrouped`, `offeredLinks`). Step 1 = checkbox/multi-select with `isDisabled` locked rows, defaults pre-checked; step 2 = checkbox list of ADR-3-filtered links (space toggles, enter submits). An adapter maps component values back to `TuiState` so `main.ts` apply wiring is untouched beyond the version bump; keep App-level q/ctrl+c quit beside component-owned input. Size hint: ~500–900 changed lines incl. tests.

## Affected Areas

| Area                                 | Impact    | Description                        |
| ------------------------------------ | --------- | ---------------------------------- |
| `tools/tui/src/tui.tsx`              | Modified  | Steps 1/2 views + adapter          |
| `tools/tui/src/tui.test.tsx`         | Modified  | Frame tests per component model    |
| `tools/tui/src/main.ts`              | Modified  | TUI_VERSION marker → v5            |
| `bin/dot` + `test/tui-resolver.bats` | Modified  | Resolver markers (~L188, ~L37/L71) |
| `tools/tui/src/manifest.ts`          | Untouched | Data/behavior logic                |

## Risks

| Risk                        | Likelihood | Mitigation                                |
| --------------------------- | ---------- | ----------------------------------------- |
| Component keys change UX    | Med        | Accepted (assumption 2); native hint text |
| q/ctrl+c vs component input | Med        | Keep App-level handler; verify in design  |
| MultiSelect API assumptions | Low        | Pin ^2.0.0; verify in design              |
| Frame tests require rework  | Med        | chalk.level=1 technique                   |

## Rollback Plan

Rendering-only: `git revert` the commits; restore v4 markers in all three places and `make build-tui` (resolver rebuilds on marker mismatch). Fresh-machine bootstrap impact: **none** — no `manifest.sh`/topic/context schema changes, so no context re-emit or bootstrap rebuild.

## Dependencies

- @inkjs/ui ^2.0.0 (existing dep), ink ^6, bun:test; Prettier canonical.

## Success Criteria

- [ ] Steps 1/2 render components; locked rows non-toggleable; defaults pre-checked; step 2 keeps space/enter UX.
- [ ] Quit before confirm exits 10 with zero writes (bun:test assertion).
- [ ] v5 markers in three places; bats resolver suite green; rebuilt binary reports v5.
- [ ] `bun test`, `tsc --noEmit`, `make lint` green.
