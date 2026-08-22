# Verify Report — migrate-tui-to-bun

**Status: PASS (delegated slice: 8.1, 8.3, automated 8.4) — ARCHIVE NOT READY**
(8.2 is USER-owned interactive smoke, deferred to user; checkboxes 8.1–8.4 not yet reconciled in tasks.md; two parent-owned lifecycle rows open.)

Date: 2026-08-22 · Executor: SDD verify · Artifact store: both (this file + Engram `sdd/migrate-tui-to-bun/verify-report`)

## Gate results (all green)

| Command | Result |
| --- | --- |
| `make check` | clean (`bash -n` + `tsc --noEmit -p tools/tui`) |
| `make lint` | clean (`shellcheck -x` + `shfmt -d`, incl. `bin/dot`, `remote-install.sh`) |
| `bats test/` | **62 pass / 0 fail** (52 dot.bats + 5 tui-resolver.bats + 5 remote-install.bats) |
| `cd tools/tui && bun test` | **126 pass / 0 fail**, 756 expect() calls, 6 files |

## Task 8.1 — Go-era legacy profile loads identically under TS binary

Method (Go deleted from worktree): expected behavior derived from `profile.go` @ tag `pre-go-removal` (610a75f) semantics — parse → migrate → reject unknown → fill false → force required → persist-if-migrated — applied to the TS catalog, then diffed against live output of `bin/dot-tui -profile <tmp> -dry-run`.

Input profile (Go-era legacy aggregates):

```json
{"components":{"base":true,"communication":true,"desktop":false}}
```

Derived expectation vs actual stdout — **identical, line for line**:

- Migration per `profile.go`: `communication:true` expands its exact 4 children true; `desktop:false` enables nothing but is removed; `changed=true`.
- Normalization: absent ids filled false; required forced true.
- Plan (brew present, xcode-select detected on this host → `xcode-select --install` silently omitted per plan.go rule; no skip entries):

  ```
  Zsh and plugins: brew install zsh fzf
  Zsh and plugins: dot zsh
  Git, SSH signing, Hunk and GitHub tools: brew install git gh lazygit hunk
  Git, SSH signing, Hunk and GitHub tools: dot git
  Terminal tools: brew install --cask ghostty
  Terminal tools: brew install tmux yazi neovim
  Discord: brew install --cask discord
  Telegram: brew install --cask telegram
  WhatsApp: brew install --cask whatsapp
  Slack: brew install --cask slack
  ```

- Exit 0, empty stderr, no side effects beyond the load-pipeline's own contract.
- Migrated rewrite verified: all four aggregate keys gone, all 31 ids present, communication children true, desktop children false (aggregate was false), base/shell/git/terminal true, exactly one trailing `\n`, no `.profile-*` temp leftovers.
- Round-trip on reload: second dry-run printed a **byte-identical plan** (`diff` clean), and the migrated file was **byte-untouched** (`cmp` clean) — Load Persists Migrated Data + idempotency proven end-to-end.

Intentional, spec-driven deltas vs what the literal Go binary would have printed on the same input (documented Phase 1 deviations, not drift):

1. `shell`/`git`/`terminal` tasks appear because installer-manifest mandates `required: true`; Go-era manifest left them non-required so they would not be forced on.
2. `base` plans only `xcode-select --install` (omitted as detected); `brew install go` was removed from base by ADR-3/spec mandate, whereas the Go binary would have planned it.

## Task 8.3 — Traceability matrix

### installer-manifest

| Scenario | Test | Status |
| --- | --- | --- |
| Catalog size and required fields are stable | manifest.test.ts "has exactly 31 entries" + "every entry has required fields" | PASS |
| No duplicate IDs | "ids are unique" | PASS |
| Baseline components cannot be deselected downstream | "baseline components are present and required" + profile.test.ts "missing ids are filled false and required forced true" | PASS |
| Aggregates absent from catalog | "legacy aggregate ids are absent" (+ "individual replacements exist", "split tool ids stay combined…") | PASS |
| Git component covers Hunk | "git covers hunk in links and commands" | PASS |
| PHP component uses Herd | "php installs through herd, never brew install php" | PASS |

### installer-profile

| Scenario | Test | Status |
| --- | --- | --- |
| Defaults match manifest | profile.test.ts "defaults match manifest", "every component id is present in the default profile" | PASS |
| Missing profile file falls back to defaults | "missing profile file falls back to defaults"; migration.test.ts "missing file load does not create one" | PASS |
| Unknown ID rejected on save | "unknown id rejected on save without writing the file" | PASS |
| Disabled required component rejected on save | "disabled required component rejected on save" | PASS |
| Unknown ID in file rejected on load | "unknown id in file is rejected on load" | PASS |
| Missing IDs filled as false and required forced true | "missing ids are filled false and required forced true" | PASS |
| Malformed JSON rejected | "malformed JSON is rejected", "valid JSON without a components object is rejected" | PASS |
| Save round-trips through tmp-and-rename | "save round-trips through tmp-and-rename", "saved bytes end with exactly one trailing newline", "no temporary files remain after save", "save creates a missing target directory", "mkdir -p semantics…" | PASS |
| Enabled aggregate expands to exact children | migration.test.ts ×4 (communication/desktop/media/databases) + "all four aggregates together mirror the Go fixture" | PASS |
| Desktop aggregate includes communication children | "enabled desktop expands to desktop plus communication children" | PASS |
| Disabled aggregate enables nothing but still removed | "disabled aggregate enables nothing but is still removed" | PASS |
| Second migration run is a no-op | "second migration run is a no-op reporting no change" (+ "migration rejects data without a components object") | PASS |
| Migrated profile is saved back on load | "migrated profile is saved back on load" | PASS |
| Unmigrated profile file is left untouched | "already-migrated profile file is left untouched" | PASS |
| Purpose-level contract (Go profiles load identically) | **live proof in this run** (task 8.1 above) | PASS |

### installer-plan

| Scenario | Test | Status |
| --- | --- | --- |
| Detection reports presence without running tools | plan.test.ts "reports presence from PATH without running tools" (marker-file side-effect probe) | PASS |
| Selected components planned in DFS dependency order | "dependencies are emitted before dependents (DFS)" | PASS |
| Each selected component appears once despite shared dependencies | "shared dependency emitted exactly once, before both dependents" | PASS |
| Unselected components produce no tasks | "unselected components produce no tasks" | PASS |
| Applied component skipped during planning | "applied-set components are excluded even when enabled" | PASS |
| Command skipped when xcode-select already installed | "xcode-select --install omitted when xcode-select detected" | PASS |
| Command kept when xcode-select missing | "xcode-select --install kept when xcode-select missing, rest still planned" | PASS |
| Brew-dependent component fully skipped without brew | "brew-dependent component fully skipped without brew" (exact reason string asserted) | PASS |
| Brew commands planned normally when brew present | "brew commands planned normally when brew present" | PASS |
| Non-brew commands survive a brew skip (same component) | "non-brew commands survive a brew skip inside the same component" | PASS |

### installer-execute

| Scenario | Test | Status |
| --- | --- | --- |
| Task runs via sh and captures combined output | "runs via sh -c capturing combined stdout and stderr with homebrew env" (+ "non-zero exit produces an error with output preserved") | PASS |
| Cancellation skips remaining tasks | "cancellation records remaining tasks as skipped without running them" | PASS |
| Progress fires before each executed task | "progress fires once before each executed task only" (interleaved log ordering) | PASS |
| Sequential execution | "tasks run strictly sequentially in plan order" | PASS |
| Dependent task skipped after dependency failure | "failure blocks dependents while independent components continue" | PASS |
| Independent components continue after failure | same test | PASS |
| Success and failure statuses | "every task yields one result with captured output and timestamps" | PASS |
| One failed command fails the whole component | summarize tests ×5 ("one failed command fails the whole component", "all tasks installed…", "skipped-only component reports the skip reason", "multiple failures concatenate…never across", "components with no results produce no summary entry") | PASS |

### dot-tui

| Scenario | Test | Status |
| --- | --- | --- |
| Initial screen state | tui.test.tsx frame "initial screen: categories in manifest order, defaults marked x, no green check" | PASS |
| Applied components marked with check | frame "applied components show a green check on their row" (+ helper "green check for applied, yellow x for selected, blank otherwise") | PASS |
| Cursor clamped at list edges | reducer "component cursor clamps at both edges", "category cursor clamps at edges" | PASS |
| Sidebar navigation jumps to category start | "sidebar navigation moves the category cursor and jumps the component cursor to category start" | PASS |
| Pane switching tab/left/right | "tab toggles panes in both directions", "left and right also toggle panes" (+ key-vocabulary mapping test) | PASS |
| Space toggles an ordinary component | reducer + frames ("space toggles an ordinary component on and off") | PASS |
| Space ignored for required/applied | "space cannot deselect a required component", "space cannot toggle an applied component", frames "space is a no-op for…" | PASS |
| Category all/none skips required | "selectCategory skips required…", "a selects every ordinary component…", "n clears every ordinary…", frames "a selects the active category, n clears it, required survive", "n on the required Base category leaves base selected" | PASS |
| Query filters case-insensitively; clear restores | "query filters case-insensitively by label; clearing restores the full list", "uppercase query still matches", helper filter tests | PASS |
| Backspace deletes last character | "backspace deletes the last query character" (+ reducer search test) | PASS |
| No matches shows feedback; keys inert | "no matches shows the query; modification keys are inert; enter does not open review" | PASS |
| Enter on empty result does not open review | same frame + "enter on an empty visible set does not open review" | PASS |
| Review lists only selected-not-applied grouped | "review lists only selected-not-applied grouped by category with counts" (+ helpers reviewRows/counts) | PASS |
| Submit versus cancel | "enter or y submits; esc cancels without submitting" | PASS |
| Empty review reports nothing to do | "empty review reports nothing to install" | PASS |
| Long list scrolls with indicators, footer last | "small terminal keeps footer last and shows clipped-row indicators", "long list scrolls to keep the cursor row visible", "review scrolls with indicators and keeps its footer last" | PASS |

### dot-cli-bootstrap

| Scenario | Test / evidence | Status |
| --- | --- | --- |
| Dry run prints plan and exits zero without side effects | main.test.ts string-contract tests (skip/task/result/link literals) + **live end-to-end dry-run in task 8.1 this run** (skips-before-tasks ordering trivially holds with zero skips; exit 0) + bats "install --profile forwards apply flags through the resolver" | PASS |
| Apply mode runs, persists, links, reports failure status | unit-level: string builders pinned verbatim from main.go + pipeline parity read (Phase 5); resolver forwarding via bats. Full real `-apply` execution (actual installs + `dot link`) intentionally has no Bats coverage — would install software; covered by parity-by-port + 8.2 manual loop | PARTIAL (unit-proven; live apply covered by 8.2, deferred) |
| One interactive round applies and loops | onSubmit seam unit tests + pipeline port; visual/interactive loop = task 8.2 | PARTIAL (deferred to USER, see below) |
| Quit without submission changes nothing | tui.tsx quit-path tests (Phase 4) + main.ts port parity | PASS (unit) |
| Prebuilt binary used directly on a clean machine | tui-resolver.bats "dot tui runs an existing dot-tui directly without any toolchain" (real compiled binary, stubbed PATH proves no toolchain invoked). Real release-asset download path = remote-install.bats with stub curl/wget; live network asset requires post-release VM | PASS (local) / DEFERRED (live asset) |
| Local Bun builds from source as fallback | "missing binary with sufficient bun builds from source then runs" | PASS |
| Neither binary nor Bun yields guidance | "missing binary with too-old bun prints bootstrap guidance and fails", "missing binary without bun prints bootstrap guidance and fails" (case-insensitive no-Go assertion, official bootstrap URL named, non-zero) | PASS |
| Repo-wide Go absence | this run: `git ls-files '*.go' go.mod go.sum` → empty; worktree has no cmd/internal/go.mod/go.sum; CI workflow uses oven-sh/setup-bun@v2, no setup-go; grep hits confined to docs/superpowers/plans historical planning doc + stale openspec/config.yaml (flagged follow-up, not contributor bootstrap path); rollback tag `pre-go-removal` @610a75f tree confirmed to contain go.mod/go.sum/cmd/internal + 11 .go files | PASS |

### Proposal success criteria (6)

| Criterion | Evidence | Status |
| --- | --- | --- |
| No Go files/toolchain references remain | tracked-file search above; README/bin/Makefile/CI clean | MET (residual: stale openspec/config.yaml context/rules/test_command mention go — known-stale follow-up; docs/superpowers/plans historical doc) |
| Every Go unit test has passing bun:test port | 126 bun:test passes across manifest/profile/migration/plan+execute/TUI/main; ports triangulated against Go tests during Phases 1–5 | MET |
| `make check && make lint && bun test && make test` passes in CI | locally green this run (see gates); CI-green provable only post-push | MET LOCALLY / POST-PUSH ONLY |
| `bin/dot tui` works with only the compiled binary | tui-resolver.bats direct-exec test with toolchain-free PATH | MET (test harness) / VM confirmation deferred (8.4) |
| Fresh-machine bootstrap follows resolution order | remote-install.bats 5 + tui-resolver.bats 5 + static reasoning below | AUTOMATED PORTION MET / real-VM portion deferred |
| Saved Go-era profiles load identically incl. legacy migration | task 8.1 executed this run — outputs identical modulo documented spec-driven deltas; round-trip byte-stable | MET |

## Task 8.4 — automated portion

Proven by existing suites (62 bats green):

- Resolution step 1 (binary present): direct exec, no toolchain invocation (tui-resolver.bats).
- Step 2 (Bun ≥ `.bun-version`, build from source): build-then-run with frozen-lockfile + compile proven via stub bun producing the launched artifact (tui-resolver.bats).
- Step 3 (no/below-min Bun): guidance naming the official bootstrap script URL, explicit non-zero, no Go mentioned (tui-resolver.bats ×2).
- Bootstrap download seam (remote-install.sh): arch-correct asset URL, curl + wget branches, failed-download continues silently with cleanup, unrunnable download dropped via probe, existing binary never re-downloaded (remote-install.bats ×5).

Static reasoning — no-Go-no-Bun machine walkthrough of `remote-install.sh`: clone/tarball needs only git/curl/wet (no language runtime); Darwin-only arch detect maps arm64/x86_64 to release assets; download failures are silent (`|| rm -f` partials) so flow reaches `exec bin/dot install`, whose resolver lands in step 3 guidance on such a machine — i.e., worst case is actionable guidance, never silent breakage, matching the proposal resolution order. The execute-probe uses `-profile <nonexistent> -dry-run </dev/null` (terminating, side-effect-free) instead of the ADR-5 `-h` sketch, which empirically lingers forever on the TS binary (documented Phase 7 deviation).

Requires a real VM (cannot be automated here):

- Live network fetch of an actual `releases/latest/download/dot-tui-darwin-*` asset (none exists yet — nothing pushed/released).
- End-to-end `dot install` on genuinely clean macOS (Xcode CLT prompts, first-run Homebrew).
- Visual confirmation that the downloaded release binary launches the UI on both arches.

## Task 8.2 — USER-owned, deferred

Interactive Terminal.app/iTerm2 visual smoke (two-pane layout, ANSI colors, search, review submit, viewport indicators, resize redraw, full install→link→reopen round) was NOT attempted, per orchestrator instruction. It blocks merge per the proposal risk mitigation.

## Strict TDD compliance (strict_tdd: true)

- TDD Cycle Evidence tables present for Phases 1–7 with RED→GREEN transitions (including continuation runs and in-loop fix cycles).
- All referenced test files exist and currently pass (126 bun:test + 62 bats, this run).
- Assertion quality audit: sampled tests use independent sources of truth — hardcoded spec tables in migration tests (drift fails loudly), marker-file side-effect probes for detection, Go-source-verbatim string literals in main.test.ts, raw-ANSI frame assertions per ADR-2. No tautologies, ghost loops, type-only assertions, or smoke-only tests found in changed/created tests. Implementation-detail CSS-style assertions: none (ANSI constants are part of the pinned UI contract per ADR-2/spec, not incidental details).

## Review workload / PR boundary

- Chained PRs were recommended; user decision on record supersedes: single PR via explicitly recorded `size:exception` (High budget risk accepted, ask-always satisfied). Returned boundary matches that recorded strategy across Phases 1–7 notes.
- Stale-text follow-up: tasks.md front-matter still reads `Chain strategy: pending` although the decision is recorded in apply-progress — parent may reconcile wording.
- No scope creep observed: work stayed within phases 1–8 tasks; no commits made this run (per plan).

## Unchecked task markers (archive blockers)

Exact unchecked implementation-task lines in tasks.md:

- `- [ ] 8.1 Verify a saved Go-era profile loads identically: …` — **work complete, proven by this report; checkbox reconciliation pending (parent/apply owns ticking)**
- `- [ ] 8.2 Manual Terminal/iTerm visual smoke test before merge: …` — genuinely outstanding, USER-owned
- `- [ ] 8.3 Walk all six spec deltas scenario-by-scenario …` — **work complete, matrix above; reconciliation pending**
- `- [ ] 8.4 Fresh-machine bootstrap dry validation: …` — **automatable portion complete; VM portion inherently post-release**

Parent-owned rows preserved:

- `- [ ] Start or reuse bounded review over the combined diff before merge.` <!-- sdd-owner: parent -->
- `- [ ] Decide chain strategy (single revertible PR vs PR1+PR2 split) given the ask-always budget signal above.` <!-- sdd-owner: parent -->

Because unchecked implementation markers remain (and 8.2 is user-owned), this is NOT a clean archive-ready pass.

## Exact blockers to archive

1. Task 8.2 interactive smoke — must be performed and evidenced by the user in Terminal.app + iTerm2.
2. Checkbox reconciliation of 8.1/8.3/8.4-automated in tasks.md based on this report (stale-checkbox exception applies once reconciled).
3. Parent-owned review-over-combined-diff and chain-strategy rows.
4. Post-push/post-release items: CI green on the branch, published release assets, real fresh-machine/VM bootstrap validation (rollback trigger if it fails).

## Follow-up flags (not fixed here, per instructions)

- `openspec/config.yaml` is Go-era stale (context, rules.apply guidelines `make go-test`, verify/build test_commands, testing layers reference go test/vet). Update at config-maintenance time.
- tasks.md `Chain strategy: pending` line vs recorded single-PR decision.
- Historical doc `docs/superpowers/plans/2026-08-15-individual-app-tui.md` still mentions Go tooling (historical record; harmless, optional cleanup).
