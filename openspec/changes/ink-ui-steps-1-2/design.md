# Design — ink-ui-steps-1-2

Change: rewrite installer-TUI steps 1 and 2 (`tools/tui/src/tui.tsx`) from
custom pure-string views (hand-rolled reducer, fixed keys) onto @inkjs/ui
components, so the whole interactive flow runs on the component interaction
model. Data layer (`manifest.ts`, `install/manifest.sh`, context schema) and
the `applyConfirmed` pipeline stay untouched; selection/check values cross into
`main.ts` through a thin value adapter. Supersedes `tui-default-install`
ADR-2's pure-string frame constraint for steps 1/2 only.

Base: `tui-default-install` merged (Ink/TS TUI, context JSON v1, exit codes
0/10/err, `applyConfirmed` one-path apply, TUI_VERSION marker resolver).
This document designs **only the delta** on top of current `main` — work units
1–9 of the base change are already in.

## 1. Architecture decisions

### ADR-1 — Locked rows are an inert block, not MultiSelect options (verified API finding)

**Decision.** Locked rows (pseudo-steps `zsh-setup`/`git-signing` + locked
packages `zsh`, `fzf`, `git`, `gh`, `tmux`) render as a static, always-checked
row block **above** the component. They are never part of the `options` array
of the step-1 `MultiSelect`, and the adapter re-inserts them into `selected`
as always-true.

**Rationale.** Verified against the INSTALLED package
(`tools/tui/node_modules/@inkjs/ui`, v2.0.0):

- `MultiSelectProps.options` is `Array<{ label: string; value: string }>` —
  no per-option disabled flag exists.
- `isDisabled` is a **component-global** prop: it maps to
  `useInput(handler, { isActive: !isDisabled })`, i.e. it disables the whole
  selector, not a row. `toggleFocusedOption` never consults any per-row state.

So "each locked row MUST map to the component disabled state" cannot be
realized literally per-row with the stock component. Rejected alternatives:

- Including locked rows as options and reconciling `onChange` to re-add them —
  fights the component, flickers, and still lets space visibly toggle before
  correction.
- A custom checkbox component — reintroduces the DIY input layer this change
  exists to delete.

The inert block satisfies every observable scenario of the delta spec: locked
rows are always visible, always checked, and un-toggleable by construction
(space/enter never reach a locked row because no such option exists). The
delta's "layout is free / 🔒 header not required" clause permits this shape.
This is the change's main spec-interpretation note — flagged for reviewer
confirmation (see §9).

### ADR-2 — One MultiSelect per step; App owns only the quit keys

**Decision.** Step 1 = one `MultiSelect` over toggleable tool rows. Step 2 =
one `MultiSelect` over ADR-3-filtered config links (the "checkbox list":
space toggles, enter submits). `App` keeps a single `useInput` handler that
recognizes **only** the quit keys (`q`, `ctrl+c`) and exits without
submitting. Arrows/space/enter are left entirely to the mounted component —
`App`'s handler returns without dispatching, and the hand-rolled reducer and
`mapInkKey` vocabulary are deleted.

**Rationale.** Ink dispatches every keypress to all mounted `useInput`
handlers, so an App-level quit handler beside component-owned input is safe
(verified pattern: the old frame tests already drove a single `useInput`
through `ui.stdin.write`; ink-testing-library propagates the same way to the
component's internal hook). Keeping quit at App level preserves the
"quit anywhere before confirm → exit 10, zero writes" contract no matter
which step is mounted. The proposal's "q/ctrl+c vs component input" risk is
closed by construction: the component's `useMultiSelect` ignores `q`/`c`,
and `App` ignores arrows/space/enter, so the two handlers never compete.

### ADR-3 — Slim TuiState; adapter functions carry the main.ts contract

**Decision.** `TuiState` shrinks to `{ step, selected, checked, submitted }`.
The component owns focus and scrolling (`focusedValue`,
`visibleFromIndex/ToIndex` inside `useMultiSelectState`), which replace the
hand-rolled `cursor` and the `width`/`height` viewport bookkeeping. Pure,
exported adapter functions map component values back into the payload
`main.ts` already consumes:

- `adaptStepOne(value: string[], context): Record<string, boolean>` —
  `selected` map: every locked/pseudo id → `true`, every toggleable id →
  `value.includes(id)`.
- `adaptStepTwo(value: string[]): Record<string, boolean>` — `checked` map:
  `value` element per link name.
- `defaultValuesFor(context, initialSelected)` / option-row shapers — the
  component's `defaultValue`/`options` inputs.

**Rationale.** `main.ts` calls `applyConfirmed(context, { selected, checked },
opts)` and `roundExitCode(finalState)` (which reads `finalState.submitted`).
Keeping those three fields plus `submitted` means **main.ts changes only on
the TUI_VERSION line**. Locked package rows MUST appear in `selected` as
`true` — `applyConfirmed` derives brew steps from `selectedPackages(context,
withRequiredTaps(context, confirmedIds))`, and locked packages
(`fzf`, `git`, …) are ordinary `context.packages` entries; dropping them
would silently stop installing the essentials. The adapter is the single
place that guarantees this, which is why it reinserts locked ids rather than
trusting the component value (the component never sees them, ADR-1).

### ADR-4 — Step 2 lists `offeredLinks(...).main` only (agents stay pruned)

**Decision.** Step-2 options come from `offeredLinks(context, selectedIds).main`
via the existing `linkRowsForStep`/`stepTwoRows` shapers (unchanged). The
opt-in AI agents group is **not** rendered, matching current `main` behavior.

**Rationale / interpretation note.** The delta spec lists "Opt-in AI agent
links group" among requirements that "remain in force verbatim", but the
delta's MODIFIED config-link-step requirement ("listing ONLY the config links
whose component tag matches a selected tool…") and the proposal's "checkbox
list of ADR-3-filtered links" pin step 2 to the filtered main list. Work
unit 8 of the base change (owner decision) already removed the agents group
from step-2 rendering ("step 2 is now exactly the ADR-3-filtered config
links"), and `stepTwoRows`/tests assert no agents. This change does not
restore it; `offeredLinks` keeps returning `agents` for the filter tests
(manifest.ts untouched). Flagged for reviewers with ADR-1.

### ADR-5 — Empty step-2 list still confirms on enter

**Decision.** If `stepTwoRows` yields zero options (only the locked block
selected → no offered links), the step-2 `MultiSelect` renders with an empty
`options` array; the hint line stays; enter still fires `onSubmit([])` and
the flow confirms with `checked = {}` — "nothing links unless explicitly
checked".

**Rationale.** Verified in `use-multi-select-state.js`: with empty options,
`focusedValue` is undefined but `submit()` unconditionally calls
`onSubmit(state.value)` (`[]`). Skipping the step or auto-advancing would
bypass the explicit confirm action the spec scenario describes. `applyConfirmed`
already tolerates an empty `checked` (link steps simply don't run).

### ADR-6 — Option arrays are memoized; component state resets on options change

**Decision.** Step-1 and step-2 `options` arrays are computed once per mounted
step (`useMemo` keyed on the step's input data: context for step 1; the
submitted step-1 `selected` for step 2).

**Rationale.** Verified in `use-multi-select-state.js`: when `options` change
deep-inequally, the hook resets to `createDefaultState({ ... defaultValue ... })`
— it snaps back to the _default_, losing the user's toggles. Step 1 unmounts
before step 2 mounts (conditional render on `state.step`), so the two
selections never co-live; memoizing prevents accidental resets from
recomputed-but-equal arrays and from parent re-renders.

## 2. Component architecture

### 2.1 Verified @inkjs/ui surface (installed v2.0.0)

`MultiSelect` (`@inkjs/ui/build/components/multi-select/`):

| Aspect               | Verified value                                                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `options`            | `Array<{ label: string; value: string }>` — plain value type, no render prop, no per-option disable                                  |
| `defaultValue`       | `string[]` initially checked values (pre-check)                                                                                      |
| `onChange`           | `(value: string[]) => void` — fires after each toggle (guarded by previous≠current deep compare)                                     |
| `onSubmit`           | `(value: string[]) => void` — fires on enter with the current value array                                                            |
| `isDisabled`         | `boolean`, component-global (`useInput isActive: !isDisabled`)                                                                       |
| `visibleOptionCount` | default 5; scrolls focus window (`visibleFrom/ToIndex`)                                                                              |
| Keys                 | `upArrow`/`downArrow` move focus; `input === " "` toggles focused option; `key.return` submits                                       |
| Reset                | options deep-change → resets to defaults (ADR-6)                                                                                     |
| Rendering            | focused option prefix `figures.pointer`; selected option suffix `figures.tick` (green); selected/focused label colored via ink theme |

`Spinner`/`StatusMessage`/`ConfirmInput` were considered and **not** used in
steps 1/2: the apply phase already renders Spinner/ProgressBar/StatusMessage
(`apply.tsx`); `ConfirmInput` would add a third explicit confirm the fixed
decisions reject (step-2 enter IS the confirm, unchanged from today).

### 2.2 Step 1 — tool selector

````text
App
├─ useInput (quit only: q, ctrl+c → exit(); everything else ignored)
├─ useEffect (state.submitted → onSubmit(TuiState) + exit())
└─ <Box flexDirection="column">                       // step === 1
   ├─ <Text bold> dot installer  step 1/2: choose tools </Text>
   ├─ LockedBlock                                     // static, never options (ADR-1)
   │  └─ rows from toolRowsGrouped(context) where row.locked || row.pseudo
   │     each: <Text> ✔ <label> </Text>               // always checked, non-interactive
   ├─ <MultiSelect
   │     options={toggleableRowsForStep(context)}     // toolRowsGrouped minus locked/pseudo
   │     defaultValue={defaultValuesFor(context, initialSelected)}
   │     visibleOptionCount={height - 4}
   │     onSubmit={(value) => { selected = adaptStepOne(value, context); step = 2; }}
   │   />
   └─ <Text dim> ↑/↓ navigate · space toggle · enter submit · q quit </Text>
```text

**Mapping.**

- Locked requirement → the inert block above the component (ADR-1); their ids
  are always `true` in `selected` via the adapter, so "always installed" holds
  at apply time.
- Defaults (former baseline: `ghostty`, `lazygit`, `hunk`, `yazi`, `neovim`,
  etc.) → `defaultValue`: the pre-checked set = toggleable ids where
  `row.default || row.installed === true`, plus `initialSelected` (test seam).
- Special installers (`code`, `duti-defaults`, `dock`, `macos`) → ordinary
  options, unchecked by default (no `default` flag), toggleable.
- Category headers / 🔒 / `[x]`/`[ ]` mark-up → gone (delta: "layout free").
  Visual grouping is preserved as **contiguous order** (`toolRowsGrouped`
  keeps same-category rows adjacent); no per-group décor because MultiSelect
  has no header/separator concept (ADR-1 rationale; optional dim label prefix
  is a free-layout enhancement, not required).
- Selection surface → `onSubmit(value)` gives the currently checked option
  values on enter; `adaptStepOne` merges locked ids and flips the step.

### 2.3 Step 2 — config-link checkbox list

```text
App
├─ useInput (quit only — unchanged)
└─ <Box flexDirection="column">                       // step === 2
   ├─ <Text bold> dot installer  step 2/2: link configs </Text>
   ├─ <MultiSelect
   │     options={stepTwoOptions(context, selected)}  // per ADR-4: .main links
   │     defaultValue={[]}                            // every row unchecked
   │     visibleOptionCount={height - 4}
   │     onSubmit={(value) => { checked = adaptStepTwo(value); submitted = true; }}
   │   />
   └─ <Text dim> ↑/↓ navigate · space toggle · enter apply · q quit </Text>
```text

**Mapping.**

- Options: `stepTwoRows(context, state)` → `offeredLinks(context, selectedIds)
  .main`; each `ContextLink` becomes `{ label: <name> (+ "<n> targets" for
  multi-row names), value: <name> }` — one row per name, so multi-target names
  toggle as one unit (base requirement preserved by construction: the value
  IS the name; `applyConfirmed` filters `context.links` by `checked[link.name]`).
- Default: `defaultValue={[]}` — nothing links unless explicitly checked.
- Submit semantics: enter fires `onSubmit(value)` → `adaptStepTwo` → `checked`;
  `submitted = true` → App effect runs `onSubmit(state)` then `exit()`
  (identical to today's confirm path; no extra confirm step).
- Quit: `q`/`ctrl+c` handled at App level next to the component's own input
  (ADR-2) → `exit()` without submitting → `main.ts` maps to exit 10.

## 3. State / reducer changes

### 3.1 What survives vs what the component owns

| Piece | Owner | Notes |
| --- | --- | --- |
| `step`, `selected`, `checked`, `submitted` | App (`TuiState`) | `selected`/`checked` are only mutated by adapter output at submit boundaries |
| `cursor`, `width`, `height` | **deleted** | replaced by component focus/scroll state; no more viewport math |
| `Action`, `reducer`, `reduceKey`, `mapInkKey`, `MappedKey`, `InkKeyFlags` | **deleted** | key dispatch replaced by component `useInput` + App quit-only handler (`quitRequested`) |
| `toolView`, `linkView`, `viewportOf`, `LOCK_MARK` | **deleted** | superseded pure-string view layer (delta: no longer required) |
| `initialState(context, initialSelected?)` | survives | trimmed shape; still seeds the base map (locked/pseudo → true, default/installed → true) for the adapter |
| `linkRowsForStep`, `stepTwoRows` | survive unchanged | option shaping for step 2 (`.main` only, ADR-4) |
| `toggleLink` | **deleted** | component toggles; its one-unit semantics move into `adaptStepTwo` unit tests |

`AppProps` stays `{ context, initialSelected?, fixedSize?, onSubmit? }`;
`fixedSize` now only fixes `visibleOptionCount` (deterministic frame tests).

### 3.2 Adapter contract (the only new logic seam)

```text
onSubmit(value: string[])                        // step 1
  → selected = adaptStepOne(value, context)
  → { every locked/pseudo row id: true,
      every toggleable row id: value.includes(id) }
  → step = 2

onSubmit(value: string[])                        // step 2
  → checked = adaptStepTwo(value)                // { [name]: true for name in value }
  → submitted = true                             // App effect: onSubmit(TuiState) + exit()
```text

`main.ts` receives the existing `TuiState` shape it already consumes
(roundExitCode reads `submitted`; applyConfirmed reads `selected`+`checked`).
The data layer never sees component values — no `manifest.ts`/`install/manifest.sh`
change, per fixed decision 5.

## 4. Interaction / key contract (as designed)

| Key | Step 1 | Step 2 | Owner |
| --- | --- | --- | --- |
| `↑` / `↓` | move focus between toggleable options | move focus between link rows | MultiSelect |
| `space` | toggle focused option | toggle focused link row | MultiSelect |
| `enter` | submit step → advance to step 2 | submit/confirm → apply | MultiSelect (`onSubmit`) |
| `q` | quit, nothing submitted | quit, nothing submitted | App |
| `ctrl+c` | quit, nothing submitted | quit, nothing submitted | App |
| `esc`/`tab`/other | ignored | ignored | — |

**Quit paths and exit codes** (unchanged from base, now pinned by the delta):

- Quit (`q`/`ctrl+c`) at step 1, step 2, or any pre-confirm pause → App
  `exit()` → `runTuiRound` resolves `null` → `roundExitCode(null)` =
  `EXIT_ABORTED` = **10**. `applyConfirmed` is never reached, so no profile
  write, no `dot link`, no brew spawn — **zero filesystem writes**.
- Confirm at step 2 → `submitted` → `onSubmit(state)` → exit 0 within the TUI
  round; `runInteractive` then runs the **existing** `applyConfirmed` pipeline
  unchanged: bootstrap → taps → brews → pseudo-steps (`dot zsh`, `dot git`) →
  links → topic installs.
- Apply-phase interruption: `ApplyScreen` mounts no `useInput`, so ink never
  enables raw mode there; `ctrl+c` stays a real SIGINT → `applyConfirmedLive`'s
  abort handler → loud completed-vs-pending summary → exit 1. This
  pre-existing distinction is preserved: during steps 1/2 raw mode IS on
  (MultiSelect's `useInput`), so `ctrl+c` arrives as a keypress and routes to
  the App quit handler → exit 10. During apply it remains a signal → exit 1.

**Input-ordering note.** Ink calls every active `useInput` handler for each
keypress. App's handler is mounted first, sees `q`/`ctrl+c` (exits) and
ignores everything else; the component's handler sees arrows/space/enter and
ignores `q`/`c`. No key is double-consumed; no shared vocabulary survives.

## 5. Sequence diagrams

### 5.1 Happy path: step 1 → step 2 → confirm → apply

```mermaid
sequenceDiagram
    participant U as User
    participant C as MultiSelect (step 1)
    participant A as App (tui.tsx)
    participant L as MultiSelect (step 2)
    participant M as main.ts
    participant P as applyConfirmed pipeline
    U->>C: ↑/↓ focus, space toggle
    U->>C: enter
    C->>A: onSubmit(toggleable values)
    A->>A: selected = adaptStepOne(value) (locked → true)
    A->>A: step = 2  (step-1 MultiSelect unmounts)
    A->>L: render options = stepTwoRows(selected) .main, defaultValue=[]
    U->>L: ↑/↓ focus, space checks rows
    U->>L: enter
    L->>A: onSubmit(link names)
    A->>A: checked = adaptStepTwo(value); submitted = true
    A->>M: onSubmit(TuiState {selected, checked, submitted})
    A->>A: exit() (TUI round resolves, exit 0)
    M->>M: roundExitCode → EXIT_OK
    M->>P: applyConfirmed(context, {selected, checked})
    P->>P: bootstrap → taps → brews → pseudo-steps → dot link* → topic installs
    P-->>M: EXIT_OK / EXIT_ERROR
    M-->>U: exit code (0 = applied summary)
```text

### 5.2 Quit paths: exit 10 with zero writes

```mermaid
sequenceDiagram
    participant U as User
    participant A as App (tui.tsx)
    participant M as main.ts
    participant P as applyConfirmed pipeline
    alt quit at step 1 (or step 2)
        U->>A: q or ctrl+c
        A->>A: exit() — no onSubmit, nothing adapted
        A-->>M: finalState = null
        M->>M: roundExitCode(null) → EXIT_ABORTED (10)
        M-->>U: exit 10 — no profile, no links, no installs
    else confirm reached
        A-->>M: finalState.submitted = true
        M->>M: roundExitCode → EXIT_OK (0)
        M->>P: applyConfirmed (sole writer — runs only here)
    end
```text

## 6. Test strategy rework

### 6.1 Frame-test technique (inherited from `apply.test.tsx`)

- `chalk.level = 1` at module top (test workers disable color detection; the
  point is asserting ink's RENDERED style codes, exactly as the apply-frame
  tests do).
- `stripAnsi(frame)` helper for text assertions (never depend on escape codes
  for words).
- For checked-state assertions prefer **label content + theme color closes**
  (selected/focused labels render green `\x1b[32m` / blue `\x1b[34m` on ink's
  theme). Glyph assertions (`❯`/`✔` from `figures`) are optional: figures can
  ASCII-fallback on non-unicode TERM, so word/color assertions are the
  portable form — mirroring the apply tests' "attribute-specific closes, never
  a bare `\x1b[0m`" rule.
- Driving keys: `ui.stdin.write` + small `delay` (existing `press` helper
  pattern) — ink-testing-library routes the same into MultiSelect's internal
  `useInput`.
- `afterEach(cleanup)`; `fixedSize={TALL}` (100×60) for deterministic
  `visibleOptionCount`.

### 6.2 Which tests survive / die / are added

| Existing block (`tui.test.tsx`) | Verdict | Replacement |
| --- | --- | --- |
| `initialState` | survives (trimmed shape) | same assertions against the base map (locked/pseudo/default/installed → true; `code`/`duti-defaults` unchecked) minus cursor/width/height |
| `toolView` (step-1 string view) | **deleted** | option-row shapers (`toggleableRowsForStep`, `defaultValuesFor`) unit tests + step-1 frame tests |
| `reducer` toggling | **deleted** | step-1 frame tests: space toggles focused option; sibling rows untouched; former defaults start checked and CAN be unchecked (component `defaultValue`); locked rows never appear as options |
| `linkView` (step-2 string view) | **deleted** | step-2 frame tests: options = filtered links only (assert `open-code`/unselected areas absent), all unchecked at mount, multi-target name ONE row (value = name) |
| `toggleLink` | **deleted** → adapter tests | `adaptStepTwo(["ghostty"])` → `checked.ghostty === true` (one unit per name, no per-target keys) |
| `mapInkKey` | **deleted** → `quitRequested` unit | pure helper: `q` (non-ctrl/meta) and `ctrl+c` → quit; arrows/space/enter/`Q` → not quit |
| `frame: two-step flow` | **reworked** | component-frame versions, incl. new assertions: locked block non-toggleable (space on step 1 leaves locked lines byte-identical and never removes their check), default rows pre-checked, space/enter behavior per step, quit on both steps → `onSubmit` never called |
| `main.test.ts` exit-code contract (`roundExitCode`) | survives as-is | already the bun:test assertion for exit 10 (null/unsubmitted → 10) — the "quit-before-confirm exits 10" proof |
| `main.test.ts` TUI_VERSION pin | survives, bumped | v4 → v5 (§7) |
| zero-writes | survives + sharpened | existing `applyConfirmed` dry-run test (writes nothing) still proves the sole writer is inert without confirmation; new frame tests prove `onSubmit` (the only bridge to `applyConfirmed`) never fires on quit |
| `apply.test.tsx`, `manifest.test.ts` | untouched | out of scope |

Delta-spec scenario coverage map: locked rows non-toggleable → step-1 frame
test (space leaves locked block byte-identical); defaults pre-checked →
step-1 frame test (`\x1b[32m` on default labels / tick present); space
toggles link rows → step-2 frame test; enter submits → step-2 frame test
captures `onSubmit` values; quit-before-confirm exit 10 zero writes →
`roundExitCode` unit + quit-frame tests (compositional proof, above).

## 7. Version bump + rebuild list (stale-binary contract)

| # | File | Site | Change |
| --- | --- | --- | --- |
| 1 | `tools/tui/src/main.ts` | `TUI_VERSION` const (~L568) | `dot-tui-context-v4` → `dot-tui-context-v5` |
| 2 | `bin/dot` | resolver comparison (~L188) | `dot_runtime_path` expected marker → v5 |
| 3 | `test/tui-resolver.bats` | stub fixtures (~L37 and ~L71) | both `--version` stub answers → v5 |
| 4 | `tools/tui/src/main.test.ts` | unit pin (~L174) | `expect(TUI_VERSION).toBe("dot-tui-context-v5")` |
| 5 | — | `make build-tui` | rebuild `bin/dot-tui`; verify `bin/dot-tui --version` → `dot-tui-context-v5` |

**Interpretation note (flag for reviewers).** The fixed decision/spec phrase
"exactly three places" counts the three runtime/resolver sites (#1–#3; the
bats file's two stub lines are one site pair). Site #4 is the unit-test mirror
that the base change's work-unit journal explicitly treats as "the 4th,
test-side mirror of the runtime trio" — without it `bun test` goes red on the
very first suite run, so it MUST be bumped in the same commit. This change
renders differently (component theme glyphs/colors), so a v5 bump is required
regardless of the marker bookkeeping.

## 8. Affected files (diff sketch)

| File | Change | Size hint |
| --- | --- | --- |
| `tools/tui/src/tui.tsx` | Steps 1/2 rewritten on MultiSelect: delete view/reducer/`mapInkKey`/`toggleLink`/`LOCK_MARK`; slim `TuiState`; keep `initialState`/`linkRowsForStep`/`stepTwoRows`; add `quitRequested`, option shapers, `adaptStepOne`/`adaptStepTwo`, locked block, component trees | ~−250/+260 |
| `tools/tui/src/tui.test.tsx` | Frame rework per §6; adapter/option/`quitRequested` unit blocks; delete string-view and reducer describes | ~−300/+330 |
| `tools/tui/src/main.ts` | `TUI_VERSION` → v5 only | 1 line |
| `tools/tui/src/main.test.ts` | version pin → v5 only (`roundExitCode` tests untouched) | 1 line |
| `bin/dot` | resolver marker → v5 | 1 line |
| `test/tui-resolver.bats` | two stub markers → v5 | 2 lines |
| `tools/tui/src/manifest.ts` | **untouched** (per fixed decision 5) | — |
| `tools/tui/src/apply.tsx`, `plan.ts`, `context.ts`, `profile.ts`, `Makefile` | **untouched** | — |

## 9. Risks / open items

- **ADR-1 spec reading** (highest): delta says locked rows "MUST map to the
  component disabled state (`isDisabled`)"; the installed component has no
  per-option disable. Design realizes the intent as an inert block +
  always-true adapter. If reviewers require the literal `isDisabled` prop,
  the only stock option is disabling the whole selector (wrong) or forking
  the component (rejected). Confirm before tasks are written.
- **ADR-4 spec reading**: "Opt-in AI agent links group remains in force"
  vs work-unit-8 owner pruning + "listing ONLY component-filtered links".
  Design keeps the pruned behavior (current `main`); confirm.
- **Component keys change UX**: accepted (fixed decision 2); mitigated by the
  hint line and native focus indicator.
- **`figures` glyph portability in tests**: mitigated by color-close/label
  assertions (apply.test.tsx technique).
- **Empty step-2 list** edge (ADR-5): enter still confirms with `checked={}` —
  intended, matches "nothing links unless explicitly checked".

## 10. Rollout & rollback

Rendering-only change: single commit for `tui.tsx` + `tui.test.tsx`, one
mechanical marker commit (or same commit) for the four v5 sites + rebuilt
binary (`make build-tui`). Rollback: `git revert`; restore v4 markers in all
four sites and rebuild — the resolver refuses stale/mismatched binaries and
rebuilds from src, so a reverted tree can never silently run the v5 UI.
Fresh-machine bootstrap impact: **none** — no `manifest.sh`/topic/context
schema changes, no context re-emit, no bootstrap rebuild (proposal rollback
plan confirms).

Gate list before merge: `cd tools/tui && bun test`, `tsc --noEmit -p tools/tui`,
`bats test/` (resolver suite must pass with v5 stubs),
`make lint`, `bin/dot-tui --version` → `dot-tui-context-v5`.
````
