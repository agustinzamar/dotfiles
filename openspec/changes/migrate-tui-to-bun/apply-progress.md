# Apply Progress — migrate-tui-to-bun

## Phase 1 (tasks 1.1–1.5) — COMPLETE 2026-07-19

### Completed tasks (checkboxes updated in tasks.md)

- [x] 1.1 Scaffold `tools/tui/package.json` + lockfile
- [x] 1.2 Root `.bun-version` + `tools/tui/tsconfig.json`
- [x] 1.3 RED: `src/manifest.test.ts`
- [x] 1.4 GREEN: `src/manifest.ts`
- [x] 1.5 Aggregate-absence assertion + `brew install go` removed from `base`

### Files changed (all new; no existing file touched)

- `tools/tui/package.json` — name `dot-tui`, private, engines.bun >=1.2, deps react+ink, devDeps typescript / ink-testing-library / @types/react / @types/bun
- `tools/tui/bun.lock` — written by `bun install`; `bun install --frozen-lockfile` re-verified clean (48 pkgs). Note: Bun 1.3 writes text-format `bun.lock`, not the ADR-named legacy binary `bun.lockb` — same artifact, current default format.
- `.bun-version` (root) — `1.3.14` (pinned from local `bun --version`)
- `tools/tui/tsconfig.json` — strict, jsx react-jsx, moduleResolution bundler, noEmit, types ["bun-types"]
- `tools/tui/src/manifest.test.ts` — 10 tests, 323 assertions porting `manifest_test.go` + all six installer-manifest requirements + task-1.5 assertions
- `tools/tui/src/manifest.ts` — typed `Component` interface + `COMPONENTS` (31 entries)

### TDD Cycle Evidence

| Cycle | Seam | RED | GREEN |
| ----- | ---- | --- | ----- |
| 1 | `COMPONENTS` catalog export | `bun test` → `error: Cannot find module './manifest'` (0 pass, 1 fail) — satisfies 1.3 acceptance "fails because manifest.ts does not exist" | after creating manifest.ts → **10 pass, 0 fail, 323 expect() calls** |

Triangulation: automated field-by-field comparison of TS catalog vs Go source confirmed all 31 entries identical on label/category/links/commands, with only the two mandated deviations below.

Typecheck: `tsc --noEmit -p tools/tui` → clean.

### Deviations from design (deliberate, spec-driven)

1. **`required: true` on shell/git/terminal** — Go's data leaves them `false` (its old test only checked `base`). The installer-manifest spec Requirement "Required Baseline Components" says base/shell/git/terminal MUST be `required: true`; spec wins over verbatim data. Downstream note for Phase 2: profile load forces required ids enabled, so these three become forced-on under the TS implementation (spec-intended).
2. **Explicit `default: false, required: false` on every entry** — Go relied on zero values; TypeScript requires the fields per the Component contract and the spec scenario "every entry has boolean default and required".
3. **`bun.lock` instead of `bun.lockb`** — Bun ≥1.2's default text lockfile; frozen-lockfile install verified.
4. Task 1.5's assertions were folded into the initial RED test file (single cycle) per delegation instructions; both 1.5 changes are covered by dedicated tests ("legacy aggregate ids are absent" incl. `databases`, "base keeps xcode-select but has no Go toolchain reference").

### Verification commands

- `cd tools/tui && bun install` → lockfile saved (48 packages)
- `cd tools/tui && bun install --frozen-lockfile` → no changes
- `cd tools/tui && bun test` → 10 pass / 0 fail
- `./node_modules/.bin/tsc --noEmit -p tools/tui` (i.e. `tsc --noEmit -p tools/tui`) → clean

### Workload / PR boundary

~530 new lines across 6 files (within the accepted ~500-line size:exception envelope for this run; single-PR delivery decided by user, no commits this run).

### Remaining work

Phase 2+ untouched: tasks 2.1–8.4 remain `- [ ]` in tasks.md. Parent-owned rows preserved byte-for-byte:

- `- [ ] Start or reuse bounded review over the combined diff before merge.` <!-- sdd-owner: parent -->
- `- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above.` <!-- sdd-owner: parent -->

### Persistence notes

Engram HTTP server unreachable during this run (`mem_search` failed at 127.0.0.7437); openspec side of the `both` store used for apply-progress + tasks checkboxes.

---

## Phase 2 (tasks 2.1–2.4) — COMPLETE 2026-08-22

### Completed tasks (checkboxes updated in tasks.md)

- [x] 2.1 RED: `src/profile.test.ts` — defaults, missing-file→defaults, unknown-id rejection (load+save), disabled-required rejection, malformed JSON / missing `components`, normalization fills false + forces required true
- [x] 2.2 RED: atomic-save cases — round-trip after normalization, exactly one trailing `\n`, no `.profile-*` temp leftovers across two saves, mkdir -p of missing target dir (+ existing-dir preservation)
- [x] 2.3 RED: `src/profile.migration.test.ts` — four aggregate tables expand exact child lists when true, disabled aggregate enables nothing but is removed, Go four-aggregate fixture, idempotent second run, load-persists-migrated (file rewritten only on change; clean file byte-untouched; missing file creates nothing)
- [x] 2.4 GREEN: `src/profile.ts` — `defaultProfile`, `loadProfile`, `saveProfile`, `migrateProfileData`

### Files changed (all new; no existing file touched)

- `tools/tui/src/profile.ts` (~160 lines) — legacyComponentIDs table copied verbatim from profile.go; hand-rolled validation per ADR-7 (no zod); error strings match Go's `%q` quoting (`invalid profile: unknown component "x"`, `invalid profile: required component "x" is disabled`, `invalid profile: components is required`); save = validate → mkdir recursive → `JSON.stringify(p,null,2)+"\n"` → tmp `${dir}/.profile-${pid}-${uuid}` → same-directory rename with unlink-on-failure; load pipeline order matches Go exactly (parse→components-object check→migrate→reject unknown→fill false in manifest order→force required→persist only when migrated)
- `tools/tui/src/profile.test.ts` (14 tests) — installer-profile scenarios under Default Profile Derivation / Load Missing File / Validation On Save / Load Normalization / Atomic Save With Trailing Newline
- `tools/tui/src/profile.migration.test.ts` (11 tests) — expected child lists hardcoded from the spec table as independent source of truth (not copied from the implementation)

### TDD Cycle Evidence

| Cycle | Seam | RED | GREEN |
| ----- | ---- | --- | ----- |
| 1 | profile.ts module surface (defaultProfile/loadProfile/saveProfile/migrateProfileData) | `bun test src/profile*.ts` → **0 pass / 2 fail** — `Cannot find module './profile'` from both test files | **35 pass / 0 fail / 493 expect() calls** (full suite incl. manifest tests); `tsc --noEmit -p tools/tui` clean |
| 1a (in-loop fix) | round-trip test data | test used catalog-inexistent id `vlc`; implementation correctly rejected it via validation — fixed the TEST to use `media-vlc` (test bug, not impl change) | suite green after test-data fix |

Note: all RED tests were written before any production code existed, then one GREEN cycle implemented profile.ts; the single mid-cycle failure was a typo in test fixture data caught by the just-built validator.

### Verification commands

- `cd tools/tui && bun test src/profile.test.ts src/profile.migration.test.ts` (RED phase) → 0 pass / 2 fail, module-not-found
- `cd tools/tui && bun test` → **35 pass / 0 fail**, 493 assertions, 3 files
- `./node_modules/.bin/tsc --noEmit -p .` → clean

### Deviations from design

1. Test files track temp dirs in an array cleaned by bun:test `afterAll` (Go's `t.TempDir()` auto-cleanup has no direct equivalent; `defer` is not a TS concept). Tests still never write inside the repo.
2. Migration-test expected child lists are hardcoded literals from the installer-profile spec table rather than importing the implementation's `legacyComponentIDs`, so table drift fails loudly.

### Workload / PR boundary

~330 new lines across 3 new files (Phase 2 forecast ~450; under). Same PR-1 slice as Phase 1 (additive TS port, Go untouched), no commits this run.

### Remaining work

Phase 3+ untouched: tasks 3.1–8.4 remain `- [ ]` in tasks.md. Parent-owned rows preserved byte-for-byte:

- `- [ ] Start or reuse bounded review over the combined diff before merge.` <!-- sdd-owner: parent -->
- `- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above.` <!-- sdd-owner: parent -->

### Persistence notes

Engram reachable this run; apply-progress mirrored to Engram topic `sdd/migrate-tui-to-bun/apply-progress` (project dotfiles).

---

## Phase 3 (tasks 3.1–3.3) — COMPLETE 2026-08-22

### Completed tasks (checkboxes updated in tasks.md)

- [x] 3.1 RED: `src/plan.test.ts` planner cases — hunk-inside-git (Go port), xcode-select omitted-iff-detected (both directions incl. mixed component), applied-set exclusion (Go port), DFS dependency order, shared dependency once, unselected→no tasks, brew-prefixed component fully skipped with reason "Homebrew is not installed" / planned normally with brew, non-brew commands survive a brew skip in the same component, detectEnvironment PATH-scan-no-execution (marker-file side-effect probe)
- [x] 3.2 RED: executor cases — strictly sequential order, failure blocks dependents ("dependency failed") while independents continue and their commands never run, progress fires once before each executed task only (interleaved log proves ordering; no events for skipped/cancelled), cancellation records remaining as skipped/"cancelled" without running them, one result per task with status/output/timestamps, summarize roll-up (failed-whole-component output reset+concat with newlines, skipped reason passthrough, installed-only-when-all-ran, cross-component isolation, empty→empty)
- [x] 3.3 GREEN: `src/plan.ts` — detectEnvironment (Bun.which over the spec's 8 command names, explicit PATH option so live env mutations are observed; zero execution), planFrom/plan/planWithApplied DFS planner, executeWithProgress sequential runner (Go check order preserved: dependency-failure → cancellation → progress → run), shellRunner (`Bun.spawn(["sh","-c",op])`, HOMEBREW_NO_AUTO_UPDATE=1 + HOMEBREW_NO_ENV_HINTS=1 on inherited env, merged stdout+stderr capture, non-zero exit → err with output preserved, AbortSignal forwarded), summarize ported line-for-line from cmd/dot-tui/main.go

### Files changed (all new; no existing file touched)

- `tools/tui/src/plan.test.ts` (~430 lines, 23 tests) — installer-plan + installer-execute scenario coverage; synthetic DFS fixtures via `comp()` helper; fake async runner records invocations
- `tools/tui/src/plan.ts` (~230 lines) — full ADR contract surface: `Task`/`Skip`/`Result`/`ComponentSummary` types, `Runner`/`Progress` types, `detectEnvironment`, `shellRunner`, `planFrom`/`plan`/`executeWithProgress`/`summarize`

### TDD Cycle Evidence

| Cycle | Seam | RED | GREEN |
| ----- | ---- | --- | ----- |
| 1 | plan.ts module surface (planner + executor + summarize + shellRunner + detectEnvironment) | `bun test src/plan.test.ts` → **0 pass / 1 fail** — `Cannot find module './plan'` | **23 pass / 0 fail / 81 expect() calls** |
| 1a (in-loop test fixes, impl already correct) | (1) hunk-port test used `profileWith()` which strips required baseline ids incl. git → switched to `defaultProfile()` as Go's test does; (2) progress-log expected literal omitted the third progress event → fixed literal | suite green after test fixes; no production-code change needed for either |
| 1b (impl fix driven by test) | detectEnvironment ignored runtime `process.env.PATH` mutations (Bun.which snapshots PATH at startup) → now passes `Bun.which(name, { PATH: process.env.PATH })` explicitly, matching Go LookPath live-PATH behavior | detection test green |

Typecheck: `tsc --noEmit -p tools/tui` → clean.
Full suite triangulation: `cd tools/tui && bun test` → **58 pass / 0 fail / 574 assertions across 4 files**.

### Deviations from design

1. **`plan()` returns a plain `{tasks, skips}` object, not `Promise<...>`** — planning is pure/synchronous (no I/O), matching Go. The design Contracts block sketches a Promise return; awaiting a plain value is transparent at call sites, so this stays compatible while being honest about sync semantics.
2. **Extra export `planFrom(components, …)`** — the real manifest carries no `Dependencies` today (orchestrator-noted fact), so DFS/blocking scenarios need synthetic fixtures. `planFrom` is the injected-component test seam; `plan()` delegates to it with the verbatim `COMPONENTS` catalog, mirroring Go's closure over `Components()`. Public `plan(profile, env, applied?)` signature unchanged from design.
3. **detectEnvironment via `Bun.which` with explicit `PATH` option** — Bun.which otherwise snapshots the environment at process start; explicit pass-through keeps live-mutation semantics of Go's `exec.LookPath` and makes the function testable without spawning subprocesses.
4. **shellRunner concatenates stdout then stderr** rather than byte-interleaving (Go's `CombinedOutput` interleaves at the fd level). Spec only requires "output contains text from both streams"; asserted accordingly.

### Verification commands

- `cd tools/tui && bun test src/plan.test.ts` (RED phase) → 0 pass / 1 fail, module-not-found
- `cd tools/tui && bun test src/plan.test.ts` (GREEN) → 23 pass / 0 fail, 81 assertions
- `cd tools/tui && bun test` → **58 pass / 0 fail**, 574 assertions, 4 files
- `./node_modules/.bin/tsc --noEmit -p .` → clean

### Workload / PR boundary

~660 lines across 2 new files (test ~430 + impl ~230; Phase 3 forecast ~380 — tests carry the overage). Same PR-1 slice as Phases 1–2 (additive TS port, Go untouched), no commits this run.

### Remaining work

Phase 4+ untouched: tasks 4.1–8.4 remain `- [ ]` in tasks.md. Parent-owned rows preserved byte-for-byte:

- `- [ ] Start or reuse bounded review over the combined diff before merge.` <!-- sdd-owner: parent -->
- `- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above.` <!-- sdd-owner: parent -->

### Persistence notes

Engram reachable; apply-progress mirrored to Engram topic `sdd/migrate-tui-to-bun/apply-progress` (project dotfiles).

## Phase 4 (tasks 4.1–4.4) — COMPLETE 2026-08-22 (continuation run after mid-GREEN timeout)

### Completed tasks (checkboxes updated in tasks.md)

- 4.1–4.3 (RED): `tools/tui/src/tui.test.tsx` — written in the prior run (35 pass / 16 fail at continuation start); all 51 tests now green.
- 4.4 (GREEN): `tools/tui/src/tui.tsx` brought to green against the full frame contract.

### Files changed

- `tools/tui/src/tui.tsx` — fixedSize resize seeding, mapInkKey "q" vocabulary, text-key routing (`/`,`a`,`n`) onto Go handlers, empty-visible-set a/n text no-op while searching, extracted `categoryToggle` helper.
- `tools/tui/src/tui.test.tsx` — corrected mis-ported expectations only (see deviations); no coverage removed.

### TDD Cycle Evidence

| Cycle | Seam | Start | End |
| ----- | ---- | ----- | --- |
| Continuation start (prior run timed out mid-GREEN) | tui.test.tsx full file | 93 pass / 16 fail across suite (35 pass / 16 fail in tui.test.tsx) | — |
| GREEN fix 1: fixedSize early-return before resize dispatch | App useEffect / tea.WindowSizeMsg analog | 11 of 16 failures collapsed to 1-row viewports | resolved |
| GREEN fix 2: mapInkKey "q" → `{key:"q"}` + App mode-dependent handling | mapInkKey unit seam | pinned helper test red | resolved |
| GREEN fix 3: main-switch routing of Ink text payloads ("/"→search, "a"/"n"→categoryToggle) | reducer key switch | search/category frame tests red (typed keys were dispatched as inert text) | resolved |
| GREEN fix 4: spec rule — a/n/space no-op while visible set empty (spec scenario "No matches shows empty result feedback") | reducer searching branch | no-matches frame test red | resolved |
| Final triangulation | full suite | — | tui.test.tsx **51 pass / 0 fail**; suite **109 pass / 0 fail / 734 assertions / 5 files**; `tsc --noEmit -p .` clean |

### Deviations from design / test corrections (Go tui.go is ground truth)

1. **Test fix: `firstIndexInCategory(COMPONENTS,"Communication")` expected 16 → 15.** Discord sits at index 15 in both the Go and TS manifests; original expectation was arithmetic mis-port.
2. **Test fix: scroll-test cursor 20 → 24 downs.** indices[24] is desktop-linearmouse (indices[20] is finetune); row format is `cursor + " " + mark + " " + label`, so unselected rows render as `>   LinearMouse`.
3. **Test fixes: ANSI close codes.** Ink's renderer normalizes raw `\x1b[0m` resets into attribute-specific closes (`\x1b[39m` colors, `\x1b[22m` bold/dim, `\x1b[27m` reverse — verified empirically). Frame assertions now match the rendered vocabulary (`CLOSE_COLOR`/`CLOSE_MODE`); implementation still emits the exact Go constants per ADR-2/design.
4. **Test fix: review-flow `[Base]` assertion inverted.** Required defaults are selected-not-applied, so Go `reviewRows` correctly lists `[Base]`; replaced `not.toContain("[Base]")` with `toContain("[Base]")` + `not.toContain("[PHP]")` (unselected categories absent).
5. **Test fix: enter-on-empty-set final assertions.** Go/spec pin "enter exits search mode"; corrected test asserts search exited (query retained, full list restored) without review opening, replacing an over-specified "No matches persists" expectation.
6. **Implementation refinement: searching branch treats literal text "a"/"n"/space as no-ops when the visible set is empty**, per dot-tui spec scenario "a/n/space are no-ops while the visible set is empty". Typing them with a non-empty filtered set still appends (typing "slack" requires it). Go's blanket Text-append is narrowed by this explicit spec scenario.
7. **mapInkKey maps input "q" → `{key:"q"}`** so App can own quit outside search (tea.Quit analog) while translating it back to text inside search (Go appends it to the query); other printable chars stay `{key:"text",text}` per the pinned contract, and the reducer's main switch routes `/`,`a`,`n` text payloads onto their Go handlers.

### Verification commands

- `cd tools/tui && bun test src/tui.test.tsx` → **51 pass / 0 fail / 160 expect() calls** (was 35/16)
- `cd tools/tui && bun test` → **109 pass / 0 fail / 734 expect() calls across 5 files**
- `bunx tsc --noEmit -p .` → clean
- No commits made.

### Workload / PR boundary

Phase 4 slice (~550 forecast; ~1,000 lines total across tui.test.tsx ~600 + tui.tsx ~430 from both runs). Same PR-1 boundary (additive TS port, Go untouched). Review Workload Forecast flags ask-always budget risk (High) — parent-directed continuation treated as the assigned work-unit slice within PR 1; chain-strategy decision remains parent-owned.

### Remaining work

Phases 5–8 untouched: tasks 5.1–8.4 remain `- [ ]`. Parent-owned rows preserved byte-for-byte:

- `- [ ] Start or reuse bounded review over the combined diff before merge.` <!-- sdd-owner: parent -->
- `- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above.` <!-- sdd-owner: parent -->

### Persistence notes

Engram reachable; apply-progress mirrored to Engram topic `sdd/migrate-tui-to-bun/apply-progress` (project dotfiles).

## Phase 5 (tasks 5.1–5.2) — COMPLETE 2026-08-22

### Completed tasks (checkboxes updated in tasks.md)

- [x] 5.1 RED: `src/main.test.ts` — stdout/stderr string contract pinned before implementation
- [x] 5.2 GREEN: `src/main.ts` — flag parsing, flag-mode pipeline, interactive loop; additive `onSubmit` seam in `tui.tsx`

### Files changed (all new except the tui.tsx additive seam; no existing behavior touched)

- `tools/tui/src/main.test.ts` (new, 17 tests) — RED-first contract artifact for 5.1: every expected literal copied verbatim from `cmd/dot-tui/main.go` Printf formats and traced to dot-cli-bootstrap "Non-Interactive Flag Mode" / "Interactive Loop Persists Then Applies" scenarios (`skip <id>: <reason>`, `<label>: <command>`, `🔧 %s...`, `✅ %s installed`, `⚠️ %s skipped: %s`, `❌ %s install failed`, `✅ Config links installed`, `❌ Config links failed`); plus single-dash/double-dash/-flag=value flag parsing (incl. `-apply=false` Go bool parity) and `${XDG_CONFIG_HOME:-$HOME/.config}/dot/profile.json` derivation with injected env.
- `tools/tui/src/main.ts` (new, ~230 lines) — full entrypoint port of `cmd/dot-tui/main.go`: exported pure string builders + `parseFlags` + `defaultProfilePath` as the only unit seams (ADR-1: main stays thin; pipeline runs under `import.meta.main` ≙ Go's `func main`); manual argv parser (Go flag pkg accepts `-f`, `--f`, `-f=v` — node:util.parseArgs does NOT accept single-dash long forms, so manual handling per task wording); flag mode load→plan→print skips→print tasks→stop unless -apply→execute(progressPrinter)→summarize+printResult→saveProfile→`dot link` with `DOT_PROFILE`→exit codes matching Go (1 on load/save/link/component failure); interactive loop mounting fresh `<App initialApplied={applied}>` per round via `render(createElement(App, …))` + `waitUntilExit`, quit-without-submission exits cleanly (no write/no link), MarkApplied reduces to mutating the applied record passed to the next mount, link failure prints ❌ + combined output but continues looping (Go parity).
- `tools/tui/src/tui.tsx` (additive only) — optional `AppProps.onSubmit?: (state: TuiState) => void`; the submitted effect now calls `onSubmit?.(stateRef.current)` immediately before `exit()` (the `finalModel` return value of Go's `tea.NewProgram().Run()` analog). `stateRef` declaration moved above the effects (no behavior change). Existing 51 TUI tests untouched and green.

### TDD Cycle Evidence

| Cycle | Seam | RED | GREEN |
| ----- | ---- | --- | --- |
| 1 | main.ts module surface (string builders + parseFlags + defaultProfilePath) | `bun test src/main.test.ts` → **0 pass / 1 fail** — `Cannot find module './main'` | **16 pass / 0 fail** |
| 1a (in-loop extension) | `-apply=false` boolean-value parity noticed during side-by-side read | added test → red against parser | parser handles `-flag=v`; **17 pass / 0 fail** |

Interactive-loop coverage note: render-loop behavior is intentionally not unit-tested (ADR-1/ADR-6: Bats gates it in Phases 6/8); the RED step here is the documented string-contract test per task 5.1's own wording.

### Verification commands

- `cd tools/tui && bun test src/main.test.ts` (RED) → 0 pass / 1 fail, module-not-found
- `cd tools/tui && bun test` → **126 pass / 0 fail**, 756 assertions, 6 files (109 prior + 17 new)
- `./node_modules/.bin/tsc --noEmit -p .` → clean
- Live smoke (dry-run, no side effects): `bun run src/main.ts -profile <tmp> -dry-run` → skip/task plan lines printed, exit 0; missing profile path → defaults loaded (Go LoadProfile semantics), exit 0

### Side-by-side parity check (task 5.2 acceptance)

Read `cmd/dot-tui/main.go` against `src/main.ts` function-by-function: flags → parseFlags; execute() progress-once-per-component → progressPrinter closure over a started Set; summarize → already ported line-for-line in plan.ts (Phase 3); printResult → identical status switch incl. stderr-only failed output; linkProfile → Bun.spawn(["dot","link"]) with DOT_PROFILE on inherited env, combined capture; flag-mode ordering (results printed BEFORE saveProfile, then link, then failed-flag exit) preserved exactly; interactive error paths print-and-return exit 0 like Go.

### Deviations from design

1. **Manual argv parsing instead of `node:util.parseArgs`** — design.md's Contracts block claimed parseArgs accepts single-dash forms; it does not (strict mode rejects `-profile`). Task 5.2 explicitly permits "manual aliasing"; both `-x` and `--x` and `-x=v` are handled.
2. **Additive `onSubmit` prop on App** — ADR-2 sketched reading "submitted selection from a ref/callback" without pinning the mechanism; this is that callback, minimal-surface, default-undefined so all Phase-4 tests pass unmodified.

### Workload / PR boundary

~300 new lines across 3 files (~230 impl + ~130 test minus shared header; forecast ~120 — tests carry the overage, consistent with Phases 2–4). Same PR-1 slice (additive TS port, Go untouched); delivery decision on record: size:exception accepted, single PR. No commits this run.

### Remaining work

Phases 6–8 untouched: tasks 6.1–8.4 remain `- [ ]`. Parent-owned rows preserved byte-for-byte:

- `- [ ] Start or reuse bounded review over the combined diff before merge.` <!-- sdd-owner: parent -->
- `- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above.` <!-- sdd-owner: parent -->

(Note: chain-strategy row is superseded by the recorded user decision — single PR via size:exception — but remains parent-owned in tasks.md.)

### Persistence notes

Engram reachable; apply-progress mirrored to Engram topic `sdd/migrate-tui-to-bun/apply-progress` (project dotfiles); tasks observation updated.

## Phase 6 (tasks 6.1–6.5) — COMPLETE 2026-08-22 (continuation; prior run finished 6.1 only)

### Completed tasks (checkboxes updated in tasks.md)

- [x] 6.1 Makefile targets `build-tui`/`bun-test`, `check`→tsc, `.gitignore` gains `bin/dot-tui` (done in prior run; entry verified present this run)
- [x] 6.2 Binary measured: **59 MB** (`62,321,890` bytes), cold start **0.051 s** for a full `-profile <tmp> -dry-run` plan (build + first exec). Fallback decision: numbers acceptable — no fallback to `bun run src/main.ts` needed; the compiled binary's startup cost is negligible and it removes the runtime Bun requirement per spec resolution step 1.
- [x] 6.3 RED: `test/tui-resolver.bats` — 5 tests, confirmed 0 pass / 5 fail against the Go-era `bin/dot`
- [x] 6.4 GREEN: `bin/dot` rewritten with single `run_dot_tui()` resolver
- [x] 6.5 `.github/workflows/test.yml`: setup-go → oven-sh/setup-bun@v2

### Files changed

- `test/tui-resolver.bats` (new, 5 tests) — resolution scenarios: binary present→direct exec, no toolchain on PATH (asserts args passthrough); absent+bun@pin stub→"Building dot-tui" then runs built artifact (stub bun's `build --compile --outfile X` writes an executable stand-in, proving the resolver launches what the build produced); absent+too-old bun→guidance, non-zero, no build attempted; absent+no bun→guidance naming `curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash`, non-zero, case-insensitive no-Go assertion; plus `install --profile <p> --dry-run` forwarding exactly `-apply -profile <p> -dry-run` through the resolver. Harness: real `bin/dot-tui` moved aside in setup, restored byte-for-byte in teardown.
- `bin/dot` — added `version_at_least()` (`sort -V`, verified working on macOS BSD sort) and `run_dot_tui()`: exact 3-step order from dot-cli-bootstrap "Binary Resolution Order For bin/dot" — (1) `[[ -x bin/dot-tui ]] → exec`; (2) `bun --version` ≥ `.bun-version` pin → announce build on stderr, `bun install --frozen-lockfile && bun build --compile --minify src/main.ts --outfile bin/dot-tui` in `tools/tui`, then `exec`; (3) otherwise ADR-4 guidance text (official bootstrap script URL), exit 1. `run_profile_install` and `sub_tui` now call `run_dot_tui`. All `is_executable go` / `go run cmd/dot-tui` / `brew install go` fallback lines deleted.
- `.github/workflows/test.yml` — `actions/setup-go@v6`+`go-version-file: go.mod` replaced by `oven-sh/setup-bun@v2` with `bun-version-file: .bun-version`; new `Install TUI dependencies` step (`bun install --frozen-lockfile`, required before `make check` typechecks); gates now `make lint`, `make check`, `make test` (Bats), `bun test` from `tools/tui`, plus `make build-tui` smoke. No Go setup or `make go-test` remains.

### TDD Cycle Evidence

| Cycle | Seam | RED | GREEN |
| ----- | ---- | --- | ----- |
| 1 | `run_dot_tui()` resolution order via `dot tui` / `dot install --profile` public CLI | `bats test/tui-resolver.bats` → **0 pass / 5 fail** (all fail because current `bin/dot` requires `go`) | **5 pass / 0 fail** |

### Verification commands

- `bats test/tui-resolver.bats` (RED) → 0 pass / 5 fail
- `bats test/tui-resolver.bats` (GREEN) → 5 pass / 0 fail
- `make check` → `bash -n` clean + `tsc --noEmit -p tools/tui` clean
- `make lint` → `shellcheck -x` + `shfmt -d` clean on all SCRIPTS incl. modified `bin/dot`
- `make bun-test` → **126 pass / 0 fail**, 756 assertions, 6 files
- `make test` (full Bats suite) → **57 pass / 0 fail** (52 pre-existing + 5 new)
- `rm -f bin/dot-tui && make build-tui` → fresh binary, 51 installs checked, compile clean
- grep for `go run|setup-go|go-test|is_executable go` across `bin/dot`, Makefile, CI workflow → no matches

### Measurements (task 6.2 acceptance)

- `bin/dot-tui`: **59 MB** / 62,321,890 bytes (bun build --compile --minify, 533 modules, Bun 1.3.14)
- Cold start: `time bin/dot-tui -profile <tmp>/p.json -dry-run` → **real 0m0.051s** (user 0.047s, sys 0.010s), exit 0, full plan printed
- Decision: size/startup acceptable; compiled-binary path kept as designed (no `bun run src/main.ts` fallback wiring needed).

### Deviations from design / notes

1. Design's `bun_ok` sketch became an inline `bun --version` ≥ `.bun-version` comparison using `sort -V` (macOS BSD sort supports it; verified empirically). Below-minimum Bun falls into guidance step 3, matching the spec's "Bun ≥ minimum" condition for step 2; covered by a dedicated boundary test.
2. Task wording suggested `time bin/dot-tui -h`; `-h` is not a ported flag (interactive mode mounts, Ink errors on non-TTY stdin and the process lingers — same class of behavior as running the TUI without a TTY, not a regression introduced here). The spec'd non-interactive equivalent `-profile <p> -dry-run` was used for the measurement instead; interactive-TTY smoke is Phase 8 task 8.2.
3. Orchestrator handoff said `.gitignore` lacked `bin/dot-tui`; the entry was already present (landed with 6.1 in the prior run) — verified, not duplicated.
4. An earlier draft of the bats file included an "exec-replaces process" test that was implementation-coupled and unassertable robustly; dropped before RED per TDD skill anti-patterns (tests verify behavior at seams).
5. CI needed an explicit `bun install --frozen-lockfile` step because `make check` invokes `tools/tui/node_modules/.bin/tsc`, which doesn't exist on a fresh checkout.

### Workload / PR boundary

~150 lines this phase (forecast ~120): bin/dot rewrite ~55 net, new bats file ~120, workflow ~15. Same PR-2 cutover slice as planned (Phases 6–8); delivery decision on record: size:exception accepted, single PR. No commits made.

### Remaining work

Phase 7–8 untouched: tasks 7.1–8.4 remain `- [ ]`. Parent-owned rows preserved byte-for-byte:

- `- [ ] Start or reuse bounded review over the combined diff before merge.` <!-- sdd-owner: parent -->
- `- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above.` <!-- sdd-owner: parent -->

### Persistence notes

Engram HTTP server unreachable at run start (mem_search failed, 127.0.0.1:7437); openspec side of the store used for apply-progress + tasks checkboxes. Engram mirror retried at end of run — see final status in the phase report.

## Phase 7, tasks 7.1–7.2 only — COMPLETE 2026-08-22

Scope guard honored: 7.3 (tag) and 7.4 (Go deletion) EXPLICITLY DEFERRED — no git tags created; `cmd/dot-tui`, `internal/installer`, `go.mod`, `go.sum` verified untouched.

### Completed tasks (checkboxes updated in tasks.md)

- [x] 7.1 RED→GREEN: `test/remote-install.bats` (5 tests) + best-effort release-binary download in `remote-install.sh`
- [x] 7.2 README/install docs: Go references replaced with Bun pointers + new "The installer binary" section

### Files changed

- `test/remote-install.bats` (new, 5 tests) — bootstrap download seam: arch-correct asset URL (`dot-tui-darwin-arm64`/`-amd64` matched against live `uname -m`) served by a stub curl → binary lands at `$TARGET/bin/dot-tui` executable and flow reaches `exec bin/dot install`; wget branch covered with a downloader-free restricted PATH so the stub wget is the only candidate; failed download (exit 22) → non-zero-status bootstrap continues with no binary left behind; garbage download fails the execute probe → dropped, bootstrap continues; existing `bin/dot-tui` → downloader never contacted (`URL_LOG` empty), file byte-untouched. Harness: sandbox `$TARGET` fakes a clone (`.git/` + stub `git` for the pull branch), stub `bin/dot` proves the final exec line is reached; non-Darwin hosts skip.
- `remote-install.sh` (+30 lines) — Darwin-only arch detect via `uname -m` (arm64/x86_64→amd64), skips when `$TARGET/bin/dot-tui` already executable, `curl -fsSL -o` / `wget -qO` from `$REPO_URL/releases/latest/download/<asset>` with `|| rm -f` cleanup of partial transfers, `chmod +x || rm -f`, then an execute-probe: real binary must exit 0 on `-profile <nonexistent> -dry-run </dev/null` or it is removed and bin/dot's resolver takes over. Failure paths are silent under `set -Eeuo pipefail`.
- `README.md` — "Go is required and cannot be disabled" → "Those four are required and cannot be disabled"; "Bubble Tea installer" → "terminal installer"; line-count reference 37 → 67 lines; new **The installer binary** section documenting the 3-step resolution order (prebuilt release ← downloaded by remote-install.sh during bootstrap; Bun source-build ≥ `.bun-version`; guidance), contributor-only `brew install oven-sh/bun/bun`, and that no language toolchain is needed at runtime.

### TDD Cycle Evidence

| Cycle | Seam | RED | GREEN |
| ----- | ---- | --- | ----- |
| 1 | remote-install.sh best-effort download, observed end-to-end through the script's public behavior (files on disk + final exec) | `bats test/remote-install.bats` → 2 fail + 1 harness bug (second `run` clobbered `$output` in test 5 — test fixed, not impl) | **5 pass / 0 fail** |
| 1a (in-loop fix) | wget stub missed the combined `-qO` output flag → fixed stub parsing (`-o/-O/-qO` variants); no production change | test 2 red | suite green |

Execute-probe design deviation (documented): ADR-5 pins `"$TARGET/bin/dot-tui" -h >/dev/null 2>&1 \|\| rm -f`. Empirically verified this run that the compiled TS binary LINGERS forever on `-h </dev/null` (unknown flags are ignored by parseFlags → interactive mount on non-TTY stdin; killed after 3 s, matching the Phase 6 deviation note). A literal ADR-5 probe would hang every bootstrap. Substituted the spec-conformant terminating probe `-profile <nonexistent> -dry-run </dev/null`: verified exit 0 on the real binary, exit 127 on garbage, zero side effects (dry-run never writes), per dot-cli-bootstrap "Dry run prints plan and exits zero without side effects". Design intent ("verify it executes, drop if not") fully preserved.

### Verification commands

- `bats test/remote-install.bats` (RED) → 3 fail (download unimplemented); (GREEN) → **5 pass / 0 fail**
- `make check` → bash -n clean + tsc clean
- `make lint` → shellcheck -x + shfmt -d clean incl. modified `remote-install.sh`
- `make test` → **62 pass / 0 fail** (57 prior + 5 new)
- `cd tools/tui && bun test` → 126 pass / 0 fail (unchanged, untouched)
- Repo-wide grep `make go-test|go run|go.mod|Go 1.|setup-go|go vet|golang` over README/bin/Makefile/install/system/.github/docs → no matches
- `git tag | grep pre-go` → none; `cmd/dot-tui internal/installer go.mod go.sum` all present (deferred scope untouched); no commits made

### Deviations from design

1. Execute-probe uses dry-run instead of literal `-h` (see TDD evidence block; empirical hang proof).
2. One informational echo (`==> Fetching prebuilt dot-tui (<asset>)`) before the download — failures themselves stay silent; matches the script's existing `==>` progress style. Interpreted "silent on failure" as no error output/no abort, not zero stdout during a ~59 MB transfer.
3. Partial-transfer cleanup added (`curl/wget … \|\| rm -f`): without it, a mid-download failure would leave a truncated non-executable file that then fails the probe anyway — belt-and-braces consistent with ADR-5's drop-if-unrunnable check.

### Workload / PR boundary

~150 lines this slice (~120 bats + ~30 script + README edits; forecast ~250 incl. deferred 7.3/7.4). Same PR-2 cutover slice (Phases 6–8); delivery decision on record: size:exception accepted, single PR. No commits this run.

### Remaining work

Tasks 7.3, 7.4 (deferred to a later run by orchestrator instruction), 8.1–8.4 remain `- [ ]`. Parent-owned rows preserved byte-for-byte:

- `- [ ] Start or reuse bounded review over the combined diff before merge.` <!-- sdd-owner: parent -->
- `- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above.` <!-- sdd-owner: parent -->

### Persistence notes

Engram unreachable at run start; retry status recorded at end of run.
