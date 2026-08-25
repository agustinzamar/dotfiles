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
