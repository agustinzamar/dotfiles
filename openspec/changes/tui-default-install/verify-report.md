# Verify Report — tui-default-install

**Status: PASS (committed automatable slice) — ARCHIVE NOT READY**
(owner manual smoke + parent review + fresh-VM bootstrap pending; **working-tree drift present — `make lint` is RED on 17 uncommitted files**, root-caused and documented below)

Date: 2026-08-25 · Executor: SDD verify (delegated) · Artifact store: openspec
Gate invoked per spec/verify contract: `make check && make lint && make test` (unit) + `cd tools/tui && bun test`; STRICT TDD is active (`testing.strict_tdd: true`, `rules.apply.tdd: true`).

## Gate results (run on the current working tree)

| Command | Result (current tree) | Result (committed HEAD) |
| --- | --- | --- |
| `make check` | **PASS** — `bash -n bin/dot install/*.sh system/defaults/*.sh remote-install.sh` + `tsc --noEmit` | PASS |
| `make lint` | **FAIL** — `shfmt -d` flags `install/manifest.sh` (93 diff lines) | **PASS** — `install/manifest.sh` clean (0 diff) |
| `make test` | **PASS — 80 pass / 0 fail** (bats: dot, manifest, remote-install, tui-resolver) | PASS |
| `cd tools/tui && bun test` | **PASS — 124 pass / 0 fail**, 342 expect() calls, 8 files | PASS (impl present) |
| build (`make build-tui` / resolver) | **CONFIRMED via resolver path** (see Build below); no heavy compile run (side-effect-free verify) | — |

Exact commands run: `make check` (exit 0), `make lint` (exit 2, `shfmt -d …` error), `make test` (exit 0, 80 ok / 0 not-ok), `cd tools/tui && bun test` (124 pass / 0 fail, 342 expect()).

### Gate-critical discrepancy (must be reconciled before archive)

The working tree contains **17 uncommitted modifications** on top of the committed PRs
(`9982f94` PR1, `d9263dd` PR2, `b9c08fd` PR3, `0cba977` PR4; apply-progress recorded at `024deff`).
The dirty files include `install/manifest.sh`, all `tools/tui/src/*` (15 files), `openspec/config.yaml`,
and `openspec/changes/tui-default-install/apply-progress.md` (+770/−209 lines).

Root cause of the red gate:

- Committed `install/manifest.sh` (HEAD) → `shfmt -d` clean (0 lines) — i.e. the committed apply **passes** `make lint`.
- Working-tree `install/manifest.sh` → `shfmt -d` reports a 93-line diff (case bodies un-indented from 4-space to 2-space), so `make lint` **fails** on the current tree.

This contradicts apply-progress WU1–WU3 gate evidence, which recorded `make lint` clean at each commit.
Functional impact of the drift on the gates: `make check`, `make test`, and `bun test` all still pass on the
working tree; only the shell-formatting gate is broken, and it is broken *only* by the uncommitted
`install/manifest.sh` drift (confirmed: it is the sole shfmt-dirty file across `$(SCRIPTS)`).

Verification does not fix or re-commit; the parent/owner must decide whether the committed PR tree (green) is
the archive state and reconcile the 17 dirty files before archive.

## Per-delta conformance checks (committed implementation)

### dot-cli-install — PASS

- `sub_install` (bin/dot:88): bare `""` → `run_interactive_install`; `--all|-a` → `sub_full`; `--profile` → `run_profile_install` (headless, no TTY guard by design — scripts/CI).
- `run_interactive_install` (bin/dot:133) implements ADR-5 exact order: **TTY guard `[[ ! -t 0 ]]` FIRST** → non-zero exit naming `--all`/`--profile`; then `sub_bootstrap`; `is_executable bun || brew install bun`; `resolve_dot_tui`; `install_context_json $(mktemp)`; launch `run_dot_tui --context "$ctx" [--dry-run]`; exit mapping 0 → applied summary / 10 → "aborted — nothing installed, nothing linked" exit 0 / other → propagate.
- `dot tui` hard-removed: no `sub_tui`; `TOP_COMMANDS=" backup clean doctor edit help install link test unlink update "` (no `tui`); both `tui` help lines gone from `sub_help`. `dot tui` → `'tui' is not a known command.` Completion parses `dot help`, so it self-heals.
- `sub_help` documents interactive default + `--all` + `--profile PATH` + `--dry-run --profile PATH`.
- Covered by bats 77–80: non-TTY bare install names `--all`/`--profile`; `--profile` works without TTY; `dot tui` unknown command; unlaunchable runtime fails naming headless flags. All green.

### installer-tui — PASS

- `src/context.ts` loads/validates context JSON v1 and rejects missing/wrong `version`, malformed `packages`/`links` rows (context.test.ts).
- Per-tool rows, no group toggles: `src/tui.tsx` step 1 renders locked rows pinned (🔒) and the toggle handler `if (!row || row.locked) return state;` — locked rows ignore the toggle key entirely (tui.tsx:203).
- Locked block non-toggleable: `LOCKED_PSEUDO_STEPS` (zsh-setup, git-signing) + `manifest_is_locked` (fzf/git/gh/tmux). Former-baseline defaults `manifest_is_default` (lazygit/hunk/yazi/neovim/ghostty) pre-checked and toggleable.
- Two-step flow: step 1 per-tool selector; step 2 filtered links (ADR-3) all unchecked + opt-in `agents` group unchecked, independent of selections (`offeredLinks` in manifest.ts:109).
- Link-step filter ADR-3 requirement-first: offered iff requirement row confirmed, or no-requirement link's component area active (area in `locked` or a confirmed row's area); locked rows do not count as confirmed selections — locked-only selection offers only locked-block untagged links (filter.test.ts table-driven).
- Multi-target names collapse into one toggleable row (`ContextLink.rows[]`); toggle toggles all targets together.
- `code`/`duti` each appear as one delegating row (special topic rows; `kind: "topic"`).
- Quit before confirm anywhere → exit 10 with zero filesystem writes (profile write happens only after link confirmation; main.ts ABORTED mapping). Mid-apply interruption prints ❌ completed-vs-pending and returns EXIT_ERROR.

### installer-profile — PASS

- On confirmed apply, `applyConfirmed` writes profile `{ components: { [area]: true } }` via `activeProfileAreas` (active ∪ locked areas) — area ids only (profile.ts + main.ts:176, 205).
- **Links never persisted**: only area components are written; no link names/section in the profile.
- Absent-profile defaults: `profile.ts` `defaultProfile()` sets base/shell/git/terminal true (mirrors `component_default_selected`), so missing/stale profiles fall back safely.
- Legacy Go-era profile migration maps granular ids → areas; `isAreaId` passthrough for desktop/media aggregates keeps re-migration a no-op (idempotent) — profile.migration.test.ts.
- Unit tests (profile.test.ts, profile.migration.test.ts) green.

### fresh-machine-bootstrap — PASS

- Order CLT/Homebrew → bun → resolve/build → launch confirmed in `run_interactive_install` (bin/dot:133-161).
- Non-TTY fails fast (TTY guard first, before any provisioning — piped `curl | bash` dies immediately).
- `remote-install.sh` passes `--all`/`--profile` through: `exec "$TARGET/bin/dot" install "$@"` (line 78); header documents TTY vs headless; rollback "revert remote-install.sh to force --all" pin documented (lines 17-18).
- `resolve_dot_tui` (bin/dot:394) order: prebuilt `bin/dot-tui` → `bun install --frozen-lockfile && bun build --compile --minify` when bun ≥ `.bun-version` → loud error naming headless flags. Prebuilt binary present (gitignored, arm64).

### build-tooling — PASS

- `openspec/config.yaml`: context = "Bash CLI (bin/dot) + Bun/TS Ink TUI (tools/tui/) + Homebrew Bundle"; testing unit = `bun test`, integration = bats; verify/test command = `make check && make lint && make test`; build = `make build-tui`; **zero Go references** (no go vet/test/build, bubbletea, internal/installer, cmd/dot-tui, make go-test, Go 1.26).
- `Makefile`: no `go-test` target, no `go vet ./...`; `check := bash -n $(SCRIPTS)` + `tsc --noEmit`; `lint` = shellcheck + shfmt; `test` = `dot test` (bats); `build-tui` present.
- **0 tracked `.go`/`go.mod`/`go.sum` files** (`git ls-files` empty).

## Build verification

- `make build-tui` target exists (`bun install --frozen-lockfile && bun build --compile --minify src/main.ts --outfile bin/dot-tui`).
- Resolver path (`bin/dot resolve_dot_tui`) confirmed and is the authoritative build path on fresh machines.
- A prebuilt `bin/dot-tui` (62 MB arm64 Mach-O, gitignored) is present. A full recompile was intentionally not run during verify to avoid heavy/minify side effects; the gates plus resolver/Makefile inspection cover the build contract.

## Strict TDD compliance (strict_tdd: true)

- Apply-progress records RED → GREEN → TRIANGULATE → REFACTOR for Phase 1 (manifest), Phase 2 (context/filter/selector/profile/apply), Phase 3 (dispatcher/bats), Phase 4 (tooling). Markers present inline per phase.
- **Gap:** apply-progress does **not** contain a dedicated `TDD Cycle Evidence` table (RED/GREEN/TRIANGULATE are captured inline rather than tabulated). Minor compliance note, not a functional blocker; the evidence content is present.
- All referenced test files exist and pass: `test/manifest.bats`, `test/dot.bats`, `test/remote-install.bats`, `test/tui-resolver.bats`, plus 8 bun `*.test.ts` suites (124 tests, 342 expect() calls this run).
- Assertion-quality audit (sampled changed/created tests): `filter.test.ts` is table-driven over real fixtures with independent sources of truth; migration tests use hardcoded spec tables (drift fails loudly); 342 expect() calls across suites. No tautologies, ghost loops, type-only-only assertions, smoke-only tests, or implementation-detail style assertions found in the samples. No `.go` files remain.
- `status`/`build`/`test` in config.yaml re-point the strict-TDD gate to `make check && make lint && make test` as required.

## Review workload / PR boundary

- Chained PRs recommended (Review Workload Forecast: stacked-to-main, 4-PR split). Delivered as 4 revertible commits (PR1 base+context → PR2 TUI delta → PR3 dispatcher flip+removals → PR4 tooling/docs), matching the forecast and design §6. No `size:exception` used; budget was split across PRs as forecast.
- No scope creep observed: all work falls within Phase 0–5 tasks and the spec-delta coverage map.
- Returned PR/work boundary matches the recorded `Chain strategy: stacked-to-main`.

## Unchecked task markers (archive blockers)

Exact unchecked `- [ ]` implementation/parent lines in tasks.md (all three are owner/parent-gated, not automatable by this agent):

- `- [ ] Owner manual smoke (post-apply, per design §5): run bare \`dot install --dry-run\` end-to-end in Terminal.app and iTerm2; verify locked block, per-row toggles, filtered link step, opt-in agents group, abort-at-each-step cleanliness, exit codes 0/10.` <!-- sdd-owner: implementation --> — **pending, needs a real TTY (this agent has none); inherently manual**
- `- [ ] Start or reuse bounded review of the applied change.` <!-- sdd-owner: parent --> — **pending, parent-gated**
- `- [ ] Verify the fresh-VM bun-bootstrap branch on clean hardware before removing the \`remote-install.sh\` \`--all\` rollback pin.` <!-- sdd-owner: parent --> — **pending, parent-gated (fresh hardware)**

All 21 automatable implementation tasks are checked. Because unchecked implementation markers remain (the manual smoke) and parent actions are pending, this is NOT a clean archive-ready pass — same pattern as migrate-tui-to-bun ("PASS (delegated slice) — ARCHIVE NOT READY").

## Discrepancies / issues found (not fixed, per instructions)

1. **CRITICAL for archive hygiene — working-tree drift breaks `make lint`:** 17 uncommitted modified files diverge from the committed PR tree; `install/manifest.sh` in the working tree fails `shfmt -d` (93 diff lines) so `make lint` is RED on the current tree, contradicting apply-progress WU1–WU3 clean-lint evidence. The committed HEAD is shfmt-clean (0). Parent/owner must reconcile (commit or revert the drift) before archive; the committed tree is green.
2. Dedicated `TDD Cycle Evidence` table absent in apply-progress (evidence present inline; minor).
3. Pending-owner/parent evidence (3 unchecked tasks above) — not satisfiable in this automatable slice.

## Exact blockers to archive

1. Owner manual smoke (bare `dot install --dry-run` end-to-end in Terminal.app + iTerm2) — must be performed and evidenced by the user (needs a real TTY).
2. Parent bounded review of the applied change.
3. Parent fresh-VM bun-bootstrap verification before removing the `remote-install.sh` `--all` rollback pin.
4. **Working-tree drift:** 17 uncommitted files must be reconciled so `make lint` is green on the tree that is archived; apply-progress gate evidence must reflect the true final tree.

Status: **PASS (committed automatable slice) — ARCHIVE NOT READY** — all automatable spec/implementation/tests verified green on the committed change; archive gated on the owner/parent items above plus working-tree reconciliation.
