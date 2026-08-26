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
