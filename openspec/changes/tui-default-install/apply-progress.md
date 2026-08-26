# Apply Progress — tui-default-install

## Work unit 1 — PR 1: merge + context contract (Phase 0 + Phase 1)

**Status: COMPLETE** · Branch: `feat/tui-default-install-pr1` (stacked on `main` @ merge `7fe252c`) · Commit: `9982f94` · Executor: parent inline (user-approved fallback after repeated provider API errors on delegated `sdd-apply`)

### Phase 0 — Base integration

- [x] Merged `migrate-tui-to-bun` into `main` (merge commit `7fe252c`). One conflict: `.gitignore` — resolved by keeping main's `.omo/`, dropping the stale `tools/tui/` wholesale ignore (source now tracked), keeping `bin/dot-tui` + `*.bun-build`, adding `tools/tui/node_modules/` and `tools/tui/tmp-probe/` for local untracked dirs.
- [x] Confirmation task (grep/read, merged tree): `run_dot_tui()` at `bin/dot:345` resolves prebuilt `bin/dot-tui` → one-time `bun install --frozen-lockfile && bun build --compile --minify` when bun ≥ `.bun-version` → loud error with bootstrap guidance. Makefile has `build-tui` + `bun-test`. `main.ts parseFlags` accepts `-profile/--profile`, `-apply/--apply`, `-dry-run`. **Zero divergence from design.**

### Phase 1 — Context contract (strict TDD)

- [x] RED: `test/manifest.bats` — 10 tests (json_escape unit ×4, golden-file v1 over fixtures, loud failure on unreadable topics dir, real-tree locked/default flags, special topic rows, multi-target link collapse, links.sh drift guard).
- [x] GREEN: `install/manifest.sh` — `json_escape` (pure Bash), `package_rows` (brew/cask/tap extraction; `code`/`duti` → one delegating row each: `code`, `duti-defaults`), `area_for_package` (explicit case table; area tokens resolve to themselves; unknown ids fail), `link_rows` (verbatim), `install_context_json <file>` (JSON v1, no jq; bash 3.2-safe — parallel arrays, no `declare -A`). Sourced from `bin/dot`.
- [x] TRIANGULATE/REFACTOR: drift-guard test in the same suite; identity area-token mapping added after it caught `ai`; case-table dedupe (SC2221); shfmt formatting.

### Reconciliation fix (merge fallout)

- `test/dot.bats` "every tracked config file is wired" — added `config/ohmyposh/theme.omp.json` to `handled` (read straight from repo by `.zshrc`, deliberately not symlinked).

### Gate evidence (all green at commit `9982f94`)

| Gate | Result |
| --- | --- |
| `make check` | clean (bash -n + tsc --noEmit) |
| `make lint` | clean (shellcheck -x + shfmt -d) |
| `bats test/` | 72 pass / 0 fail (was 62; +10 manifest) |
| `cd tools/tui && bun test` | 126 pass / 0 fail |

### Notes for next work units

- `zsh` has no package row (not a brew formula); shell setup is covered by the locked `Zinit/Zsh setup` pseudo-step planned for the TUI delta (PR 2).
- `duti-defaults` (topic row) has no declared dependency on the brew `duti` row in the context schema; if PR 2's filter needs it, extend the packages schema in a v1-compatible way.
- Taps (`timescam/tap`, `koekeishiya/formulae`, `FelixKratz/*`) are emitted as rows; plan.ts ordering (taps before formulas) is a PR 2 concern.

## Work unit 2 — PR 2: TUI delta (Phase 2)

**Status: COMPLETE** · Branch: `feat/tui-default-install-pr2` (stacked on `pr1`) · Commit: `d9263dd` · Executor: delegated `sdd-apply` (provider timeout at 69 turns mid-edit) + parent inline completion (finishing main.ts, fixing 8 stale/broken tests)

### Delivered (all 8 Phase 2 tasks)

- `src/context.ts` + tests: loads/validates context JSON v1 (`--context <path>`), rejects wrong/missing version, malformed rows.
- `src/filter.test.ts`: table-driven ADR-3 rule — requirement hit/miss, locked-area activity, inactive area, empty selection, agents group always present.
- `src/manifest.ts`: Go-era embedded catalog RETIRED; keeps toolRows/toolGroups/offeredLinks/activeProfileAreas/selectedPackages consuming context packages; lock-pseudo-steps (zsh-setup, git-signing) as informational rows.
- `src/tui.tsx`: two-step flow — step 1 per-tool selector (🔒 locked pinned, per-row toggles, topic groups, code/duti rows), step 2 filtered links (unchecked) + opt-in agents; quit → exit 10, zero writes.
- `src/profile.ts`: ADR-4 area-only profile; migration maps legacy granular ids onto areas; **area-id aggregates (desktop/media) pass through unchanged** so re-migration on every load is a no-op.
- `src/plan.ts`: taps-first ordering, `executeWithProgress` gains `isCancelled` (short-circuit at next step boundary).
- `src/main.ts`: one apply path for interactive + headless `-apply -profile`; mid-apply interruption prints ❌ completed-vs-pending and stops at the next step.
- `runFlagMode` headless: consumes same context JSON + area profile; locked rows always selected; default-active areas (base/shell/git/terminal fallback) honored.

### Parent-inline fixes after the provider timed out

- tsc stale: manifest.test.ts rewritten for the new API (catalog test was obsolete); tui.test.tsx reducer calls gained the `context` arg.
- plan.test.ts: tap fixtures marked `kind: "tap"` (kind-driven plan was right).
- tui.test.tsx: locked-frame test compared before cursor had moved — fixed to capture after reaching fzf.
- profile.migration: implementation was re-expanding area-id aggregates (desktop/media) on second run — isAreaId passthrough; two obsolete expansion tests replaced with the passthrough/stable test.
- main.test.ts: mid-apply interruption test was malformed (op already in calls) — rewritten to assert EXIT_ERROR + next-step short-circuit, with the missing implementation added in main.ts/plan.ts; headless ghostty expectation corrected to default-active terminal fallback.

### Gate evidence (all green at commit `d9263dd`)

| Gate | Result |
| --- | --- |
| `cd tools/tui && bun test` | 124 pass / 0 fail |
| `make check` | clean (bash -n + tsc --noEmit) |
| `make lint` | clean (shellcheck -x + shfmt -d) |
| `bats test/` | 72 pass / 0 fail (regression) |

## Work unit 3 — PR 3 + PR 4: dispatcher flip, removals, tooling/docs (Phase 3 + Phase 4)

**Status: COMPLETE** · Branches: `feat/tui-default-install-pr3` → `b9c08fd`, `feat/tui-default-install-pr4` → `0cba977` (stacked) · Executor: delegated `sdd-apply` (provider timeout at 58 turns; dispatcher + removals + bats done, uncommitted) + parent inline completion (commit PR 3, then PR 4)

### PR 3 — dispatcher flip + removals (commit `b9c08fd`)

- `run_interactive_install` (ADR-5 exact order): TTY guard first → `sub_bootstrap` → ensure bun → resolve runtime → `install_context_json` (mktemp) → launch `--context` → exit mapping 0/10/other.
- `run_dot_tui` refactored into `resolve_dot_tui` (echoes binary path) + launcher: the caller owns exit-code mapping and temp-context cleanup.
- Headless `run_profile_install` now emits the context JSON and passes `--context` (TUI apply refuses without it). No TTY guard on purpose (scripts/CI).
- `sub_tui`, tui help lines, `TOP_COMMANDS` entry removed; completion self-heals via `dot help`.
- Coherence fix found by the delegate: oh-my-posh theme became a tracked link (`ohmyposh` in links.sh) read through the symlink — matches the new link step and retires the earlier `handled` workaround in dot.bats.
- `remote-install.sh`: TTY vs headless documentation comment only.
- 8 new bats (73-80): non-TTY bare install fails naming `--all`/`--profile`; headless profile works without TTY; `dot tui` is an unknown command; unlaunchable runtime fails naming headless flags; resolver forwards `--context`.

### PR 4 — tooling truth + docs (commit `0cba977`)

- `openspec/config.yaml` fully rewritten to Bun reality (no Go references anywhere; unit = bun test, integration = bats; gates `make check && make lint && make test`; build = `make build-tui`; strict-TDD gate re-pointed).
- `README.md`: interactive default + headless flags, `dot tui` gone, two-step installer flow documented, installer-binary section updated to the resolver + context JSON.
- Makefile verified already Bun-realigned post-merge (no go-test); no change needed.

### Gate evidence (all green at `0cba977`)

| Gate | Result |
| --- | --- |
| `make check` | clean (bash -n + tsc --noEmit) |
| `make lint` | clean (shellcheck -x + shfmt -d) |
| `cd tools/tui && bun test` | 124 pass / 0 fail |
| `bats test/` | 80 pass / 0 fail (was 72; +8 new contract tests) |

## Work unit 4 — PR 5: TUI-first + bootstrap-on-confirm + PATH-proof detection (commit `be726a2`)

**Status: COMPLETE** · Branch: `feat/tui-default-install-pr5` · Executor: parent inline (verify remediation — found during the owner's real smoke run)

### Bug (owner smoke report)

Bare `dot install` on this already-set-up Mac installed Xcode CLT + Homebrew before showing the TUI. Root cause: `sub_bootstrap` detected via PATH (`type brew`, `xcode-select` unqualified); macOS GUI-launched terminals start with a bare `/usr/bin:/bin:/usr/sbin:/sbin` PATH, so the present installs looked missing and were reinstalled.

### Fix

- `run_interactive_install`: TTY guard → resolve runtime only (prebuilt needs nothing) → show TUI. No Xcode/Homebrew provisioning before the selector. PATH normalization for the TUI's subprocesses moved AFTER resolution.
- Hidden `dot bootstrap` dispatch (not in TOP_COMMANDS/help); the TUI's apply phase runs it as its FIRST step (post-confirm) via the absolute `$DOTFILES_DIR/bin/dot` path, so bootstrap happens only after the user confirms.
- `sub_bootstrap` PATH-independent: `/usr/bin/xcode-select -p` + known Homebrew paths (`/opt/homebrew/bin/brew`, `/usr/local/bin/brew`) by path, never `type`.
- `dot_runtime_path` resolves bun PATH-first (bats stubs stay deterministic) with known-locations fallback for GUI-PATH shells; `DOT_RUNTIME_BUN_LOOKUP=path` forces PATH-only in the resolver suite (the real bun at /opt/homebrew was defeating stubs).
- Regression bats: `bootstrap` hidden-but-dispatchable; PATH-stripped bootstrap never reinstalls Homebrew (2 new tests; resolver suite 9/9).

### Gate evidence (green at `be726a2`)

| Gate | Result |
| --- | --- |
| `make check` | clean |
| `make lint` | clean |
| `bats test/` | 82 pass / 0 fail |
| `cd tools/tui && bun test` | 124 pass / 0 fail |

## Work unit 4b — PR 5 (second commit `f98950e`): stale-binary version gate

**Bug (owner report)**: the TUI still showed grouped tools ("Composer, Herd and PHPStorm"). Cause: the prebuilt `bin/dot-tui` on disk predated the context delta (grouped-label UI); the resolver trusted ANY prebuilt binary, so the per-tool selector never shipped.

**Fix**: `dot_runtime_path` gates the prebuilt binary on `bin/dot-tui --version` output exactly `dot-tui-context-v1` (TUI_VERSION in main.ts); stale/foreign binaries fall through to a rebuild from src. Resolver stubs answer `--version`; new stale-rebuild test; unit test pins the marker. Local binary rebuilt (`make build-tui`): next `dot install` runs the per-tool installer. Gates green: bun 125/125, bats 83/83, check/lint clean.

## Work unit 5 — repeated category headers + tap rows shown as bare selectable items

**Status: COMPLETE** · Branch: `feat/tui-default-install-pr5` · Executor: parent inline (found reviewing the owner's screenshot after commit `6b0de35` landed the fine-grained category taxonomy in `install/manifest.sh`)

### Bug 1 (owner screenshot): `[Desktop]` header repeats non-contiguously

`toolView`/`reduceKey` indexed `toolRows(context)` directly — raw context/topic-file
order — and printed a new `[Category]` header on every adjacency break. `toolGroups`
(true grouping) already existed in `manifest.ts` but nothing rendered from it, so any
topic whose rows weren't contiguous in the source Brewfile (e.g. `7zip`, topic `core`,
declared after `Browsers` in the fixture) reprinted its header.

**Fix**: new `toolRowsGrouped(context)` = `toolGroups(context).flatMap(g => g.rows)`.
`toolView` and `reduceKey` BOTH switched to it (display and cursor navigation must
share one order or the highlighted row drifts from the interacted-with row). The
existing adjacency-check header logic becomes correct once fed pre-grouped input —
no other rendering logic changed.

### Bug/decision 2 (owner screenshot + explicit product decision): bare tap ids as checkbox rows

`koekeishiya/formulae` and `FelixKratz/formulae` rendered as their own toggleable
rows (raw tap id as label — `install/manifest.sh`'s comment called this deliberate:
"tap rows keep their full tap name, they ARE the tap"). Owner decision when asked:
hide taps from the selector entirely; auto-include the `brew tap` step whenever any
sibling formula/cask from the same topic file is selected.

**Fix**: `toolRows()` now skips `kind === "tap"` (same treatment as `kind === "topic"`).
New `withRequiredTaps(context, selected): Set<string>` in `manifest.ts` returns
`selected` plus every tap id whose topic matches a selected non-tap package's topic
(Homebrew Bundle semantics: a topic's taps cover every formula/cask in that file).
`applyConfirmed` (main.ts) wires it in right after building the confirmed id set —
the one code path both interactive and headless apply share, so neither can diverge.

### Regression found while fixing

`tui.test.tsx`'s `rowIndex()` test helper hand-rolled a COPY of the row order
("mirror toolRows") instead of calling the real function — it silently drifted the
moment production code moved to the grouped order. Replaced with a direct call to
`toolRowsGrouped(fixtureContext)`, so it can never desync from production again.

### Test evidence (RED → GREEN, TDD)

| Test | RED | GREEN |
| --- | --- | --- |
| `manifest.test.ts`: tap rows excluded from `toolRows`, sibling still toggleable | new | pass |
| `manifest.test.ts`: `toolRowsGrouped` keeps same-category runs contiguous | new | pass |
| `manifest.test.ts`: `withRequiredTaps` auto-includes / no-ops correctly (3 cases) | new | pass |
| `tui.test.tsx`: `[core]` header appears exactly once despite non-contiguous `7zip` | fail (2 occurrences) | pass |
| `main.test.ts`: tap installed automatically when only a sibling formula is checked | fail (missing `brew tap ...`) | pass |

### Gate evidence (green)

| Gate | Result |
| --- | --- |
| `make check` | clean |
| `make lint` | clean (found and fixed a pre-existing `shfmt` indentation drift in `install/manifest.sh` unrelated to this fix) |
| `bats test/` | 84 pass / 0 fail |
| `cd tools/tui && bun test` | 136 pass / 0 fail |
| `tsc --noEmit -p tools/tui` | clean |

## Work unit 6 — full category taxonomy audit (owner request, pre-merge)

**Status: COMPLETE** · Branch: `feat/tui-default-install-pr5` · Executor: parent inline

Owner asked for a full audit of `manifest_category()` before merging to `main`, beyond
the specific examples given ("analyze, don't do only what I said"). Cross-referenced
every `brew`/`cask`/`tap` line in `install/topics/*` against `manifest_category()` by
generating a real context JSON and grouping it through the already-fixed
`toolRowsGrouped`.

### Confirmed already fixed by work unit 5

`aerospace` (with yabai/skhd/sketchybar/borders) and `linearmouse` (with the other
Tweakers) were already correctly categorized in the data — they only *looked* wrong
in the owner's screenshot because of the pre-fix header-repeat bug. No data change
needed for those two.

### Real bugs found and fixed

1. **Duplicate declaration**: `unar` was declared in BOTH `install/topics/core` and
   `install/topics/media` — the exact same formula rendered as two separate
   selectable rows. Removed from `media` (stays in `core`, next to `7zip`).
2. **Uncategorized fallthrough**: any package not in `manifest_category()`'s case
   table falls back to its raw topic filename ("core"/"desktop"/"dev"/"media",
   always lowercase), producing headers that mix Title-Case categories with raw
   lowercase ones in the same selector. Orphans found and fixed: `fzf`, `git`,
   `gh`, `lazygit`, `hunk`, `tmux`, `poppler`, `dockutil`, `duti`, `herd`.
3. **New categories** (owner-requested + audit-driven): `Git` (git/gh/lazygit/hunk),
   `Services` (herd/orbstack — owner's "Orbstack & Herd together"), `Linters`
   (shellcheck/shfmt/actionlint/swiftformat — owner's "linters grouped"), `Prompt`
   (oh-my-posh today; starship/p10k have no brew/cask packages yet so there was
   nothing literal to group, but the category now exists for when they do).
4. **Reassigned orphans to existing categories**: `poppler` → Filesystem (yazi
   preview dependency), `dockutil`/`duti` → Utilities, `tmux` → Terminals, `fzf` →
   Shell.
5. **Deliberately left alone**: `AI` stays one category (agents + consumer apps +
   Gentle-AI's own tools) — broad but coherent; splitting it wasn't requested and
   would be scope creep.

### Test evidence (RED → GREEN, TDD)

Two new bats tests added to `test/manifest.bats` against the REAL `install/topics/`
tree (not synthetic fixtures, since this is a real-data audit): a regression guard
asserting NO toggleable package's category ever equals its raw lowercase topic name,
and an exact-count assertion that `unar` appears exactly once. Both failed before the
fix (`fzf` orphaned, `unar` duplicated) and pass after.

### Gate evidence (green)

| Gate | Result |
| --- | --- |
| `make check` | clean |
| `make lint` | clean |
| `bats test/manifest.bats` | 13/13 (2 new) |
| `bats test/` (full) | 86 pass / 0 fail |
| `cd tools/tui && bun test` | 136 pass / 0 fail |
| Live render probe (real context → `toolRowsGrouped`) | every category Title-Cased, no repeats, no duplicates |

## Work unit 7 — tmux unlocked + TUI_VERSION v2 (stale-binary rebuild)

**Status: COMPLETE** · Branch: `feat/tui-default-install-pr5` · Executor: parent inline

Owner re-reported pre-fix symptoms (2x Monitoring/Filesystem/Text, Git tools split,
aerospace/linearmouse alone, bare tap ids) after all data-side fixes were already
committed. Root cause was NOT data: the compiled `bin/dot-tui` on disk predated the
fixes, and `dot_runtime_path` only rebuilds when `--version` output differs from the
hardcoded marker — which no source change had bumped.

- `tmux` removed from `manifest_is_locked` (real preference, not forced); now a
  `manifest_is_default` member (pre-checked, toggleable) like lazygit/hunk/yazi.
  bats locked/defaults test updated (RED before, GREEN after).
- `TUI_VERSION` bumped `dot-tui-context-v1` → `-v2` in `main.ts` (with a comment
  pinning the 3-place sync contract) and matched in `bin/dot`'s resolver check and
  `test/tui-resolver.bats` fixtures; unit test pins v2.
- Noted: the owner's editor reformats `install/manifest.sh` case-bodies to 2-space,
  which shfmt rejects — re-ran `shfmt -w` before gating.
- Rebuilt binary (`make build-tui`): `bin/dot-tui --version` → `dot-tui-context-v2`.
  Gate green: bats 86/86, bun 136/136, check/lint clean.

## Work unit 8 — step 2 = pure links; code to the main list; new "System" category

**Status: COMPLETE** · Branch: `main` (post-merge) · Executor: parent inline

Owner request on top of the merged flow:

1. **Step 2 loses the opt-in AI-agents group and the gated extra installs.** The
   optional links (`agents` from links.sh) are no longer offered in the TUI; step 2
   is now exactly the ADR-3-filtered config links. `offeredLinks` still returns
   `agents` for the filter tests, but nothing renders them.
2. **`code` (VS Code extensions) moved to the main listing** and is no longer a
   gated step-2 extra. All `kind: "topic"` rows became first-class step-1 rows
   (`toolRows` only excludes taps now): `code` → category **Editors**, plus human
   labels ("VS Code extensions", "Default file handlers", "Dock defaults", "macOS
   defaults") wired in `_manifest_label` since it previously fell back to the bare id.
3. **New "System" category** for `duti-defaults`, and two brand-new emitted rows
   `dock`/`macos` (delegating rows kind `topic`, topic `system`) that run
   `dot dock` / `dot macos`. `area_for_package` gained the `system` area token.
   Apply side: `topicCommandFor()` maps code/duti-defaults/dock/macos to their
   subcommands; unknown topic ids are skipped (coverage is implied: the drift guard
   only inventories link tokens, not topic rows).

The reducer's enter-merge of `special` selections and `specialRowsForStep`/
`toggleSpecial`/`special` state were deleted; `stepTwoRows` returns plain links.

**Version**: TUI_VERSION bumped v2 → v3 (renders differently now), pinned in
main.ts + bin/dot + test/tui-resolver.bats fixtures; binary rebuilt (v3).

### Test evidence (RED → GREEN)

All behavioral tests updated as the contract changed: initialState now expects
code/duti-defaults present-and-unchecked; toolView asserts `[Editors]`/`[System]`
groups and NO opt-in/extra-install output in step 2; the old "step-2 extras"
describe was removed; tap-exclusion and category tests keep their meaning. bats
adds topic-row-count=4 (code, duti-defaults, dock, macos), their topics/labels
and the System/Editors category assertions.

### Gate evidence (green)

| Gate | Result |
| --- | --- |
| `make check` | clean |
| `make lint` | clean |
| `bats test/` | 86 pass / 0 fail |
| `cd tools/tui && bun test` | 134 pass / 0 fail |
| `tsc --noEmit -p tools/tui` | clean |
| `bin/dot-tui --version` | `dot-tui-context-v3` |

## Work unit 9 — ink-ui components (ADR-2 relaxation: pure views render via components)

**Status: COMPLETE** · Branch: `feat/ink-ui-components` (off `main` @ `ae413a1`) · Executor: delegated implementation · Commit: see branch (do NOT push/merge — owner reviews)

Owner request: adopt vadimdemedes/ink-ui (`@inkjs/ui@2.0.0`, peer ink ≥5 — runs on installed ink 6.8 / react 19.2) and replace the hand-built text widgets where the component contract preserves the pinned behavior exactly.

### Adopted — apply phase (interactive only, main.ts + new src/apply.tsx)

- New `src/apply.tsx`: `ApplyScreen` renders `@inkjs/ui` **Spinner** (running step label), **ProgressBar** (steps done/total, clamped 0–100), **StatusMessage** per finished step (`success` ✓ / `error` ✖ / `warning` ⚠ variants on ink's theme icons + colors), and a final **Badge** (`Done` green / `Failed` red) whose commit triggers `useApp().exit()` — ink's unmount keeps the final frame visible (`log.done()`), so the summary stays on screen.
- `ApplyUiBridge`: the async `applyConfirmed` pipeline feeds the tree through a typed `ApplyUi` seam (`progress/result/error/finished`); events arriving before mount are queued and flushed on registration. `applyConfirmed` keeps its ONE logic path: with `ui` present it routes progress/results/summaries to the tree, without it output stays on the plain 🔧/✅/❌ console lines.
- `runInteractive` mounts the screen only for a real apply; **dry-run keeps plain console plan lines** (no UI mounts) and headless `-apply -profile` never mounts a UI — the spec's no-UI-mount contract holds untouched.
- **SIGINT safety (verified in ink 6.8 source)**: ink enables stdin raw mode ONLY while a `useInput` hook is mounted; `ApplyScreen` registers none, so ctrl+c stays a real signal and `applyConfirmedLive`'s abort handler (loud completed-vs-pending summary → `EXIT_ERROR`) keeps working. `signal-exit`'s re-raise is suppressed too (it only fires when its listener is the sole SIGINT listener; applyConfirmedLive's handler is always registered during apply).
- `TUI_VERSION` bumped `dot-tui-context-v3` → `-v4` in `main.ts` (renders differently now) and matched in `bin/dot`'s resolver check + `test/tui-resolver.bats` stub fixtures. The `main.test.ts` unit pin follows (keeps `bun test` green — the 4th, test-side mirror of the runtime trio). Binary rebuilt: `bin/dot-tui --version` → `dot-tui-context-v4`.

### NOT adopted — step-1 selector stays custom (hard requirement)

**`MultiSelect` cannot preserve the pinned contract**, so per the owner's fallback the custom selector (+ linkage in the reducer) stays byte-identical. Evidence from the installed package + docs: `MultiSelect` is a flat, UNCONTROLLED list (`options: {label, value, isDisabled?}[]`, `defaultValue`, `onChange`/`onSubmit` arrays); it renders no `[Category]` group headers, has no locked-block semantics beyond per-option `isDisabled` (which would change the locked rows' render and cursor behavior), and owns its selection state internally — it cannot be driven by the existing byte-identical reducer/key contract (space toggles the row, locked rows ignore space, enter advances, q quits, up/down navigate). `ConfirmInput` was also NOT added before step-2 apply: enter-to-confirm already IS the confirmation, and inserting a prompt would alter the pinned key contract and the spec's "apply immediately when the user confirms" reading.

### Frame-test guidance baked in

Ink normalizes a bare `\x1b[0m` into attribute-specific closes (`\x1b[39m` colors, `\x1b[22m` bold/dim, `\x1b[27m` reverse), so the new `apply.test.tsx` asserts rendered closes: red error icon `\x1b[31m`/`\x1b[39m`, dim step output `\x1b[2m`/`\x1b[22m`, green Done badge `\x1b[32m`/`\x1b[39m`, and `not.toContain("\x1b[0m")`. The bun test worker disables color detection, so `chalk.level = 1` is set at the top of the file to force real codes (chalk never emits a bare reset).

### Test evidence (RED → GREEN)

- RED: `apply.test.tsx` (new, 13 tests) — module missing, frames lacked rendered closes at default chalk level; `main.test.ts` ui-seam describe (4 tests) failed on missing `ui` option + wrong planned-step counts; v4 pin failed vs v3 const; resolver bats 1/5/7 failed when `bin/dot` was bumped before the stubs.
- GREEN: `src/apply.tsx` + main.ts wiring; all 149 bun tests pass; `bats test/` 86/86.
- TRIANGULATE: reducer finish is terminal (late events inert); dry-run ignores the ui seam; failure/interruption events flow (`result:failed`, `error:❌ Interrupted…`) with `finished:false`; ProgressBar % clamped; `\x1b[0m` never emitted.

### Gate evidence (green)

| Gate | Result |
| --- | --- |
| `make check` | clean (bash -n + tsc --noEmit) |
| `make lint` | clean (shellcheck -x + shfmt -d; pre-existing install/manifest.sh 2-space quirk flattened with shfmt -w before gating) |
| `bats test/` | 86 pass / 0 fail |
| `cd tools/tui && bun test` | 149 pass / 0 fail (was 134; +13 apply +2 net main: -0/+15) |
| `tsc --noEmit -p tools/tui` | clean |
| `bin/dot-tui --version` | `dot-tui-context-v4` |

### Notes for next work units

- Dep budget held: only `@inkjs/ui@^2.0.0` added (+ its transitive chalk/cli-spinners/deepmerge/figures via bun.lock).
- The apply UI is interactive-only by design; if the owner later wants the headless path styled too, the `ui` seam is the seam — pass a UI render only when stdout is a TTY, never by default (spec: headless MUST NOT mount a UI).
- Uncommitted pre-existing working-tree formatting changes in `tools/tui/src/tui.tsx` + `tools/tui/src/manifest.test.ts` were preserved untouched and are NOT part of this branch's commits.
    
