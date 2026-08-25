# Tasks — tui-default-install

Base precondition: `migrate-tui-to-bun` is merged into `main` **before** any task below runs.
Test gates (re-pointed by this change's build-tooling delta — drop all Go-era references):
until Phase 4 lands use `make check && make lint && make test`; after Phase 4, `make check`
itself runs `bash -n` + `tsc --noEmit -p tools/tui` + `bun test`, so the single gate is
`make check && make lint && make test`. STRICT TDD applies: sequence RED → GREEN → TRIANGULATE → REFACTOR.

## Review Workload Forecast

| Field | Value |
| ------- | ------- |
| Estimated changed lines | ~1100–1400 (new `install/manifest.sh` ~180 + bats ~150; TUI delta ~400 + bun tests ~300; `bin/dot` ~120; Makefile/config/README ~80) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (merge base + context contract) → PR 2 (TUI delta) → PR 3 (dispatcher flip + removals) → PR 4 (tooling/docs + gates) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

```text
Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High
```

PR boundaries match design §6's four revertible commits. Reverting PR 3 alone restores
the old default entry point.

---

## Phase 0 — Base integration (PR 1, first half)

- [x] Merge `migrate-tui-to-bun` into `main`, reconciling main's newer commits (oh-my-posh prompt change, `t3-code` cask) so that `tools/tui/`, `run_dot_tui()` in `bin/dot`, and `make build-tui` / `make bun-test` all exist on the merged tree. <!-- sdd-owner: implementation -->
- [x] Confirm in the merged tree (cheap grep/read, do NOT re-derive designs): `bin/dot` `run_dot_tui()` resolves prebuilt `bin/dot-tui` → one-time `make build-tui` when bun ≥ required → loud error; Makefile has `build-tui` (`bun install --frozen-lockfile && bun build --compile src/main.ts --outfile bin/dot-tui`) and `bun-test`; `tools/tui/src/main.ts` `parseFlags` accepts `-profile/--profile`, `-apply/--apply`, `-dry-run`. Record anything that diverges before building on it. <!-- sdd-owner: implementation -->

## Phase 1 — Context contract: `install/manifest.sh` (PR 1, second half)

Covers dot-cli-install groundwork + design §ADR-2. Single Bash parser, JSON v1 contract, no jq dependency.

- [x] RED: add `test/manifest.bats` with a golden-file test for `install_context_json`: fixture topics + `links.sh` rows → expected JSON v1 (`locked`, `packages` with `{id,topic,kind,area,locked,default}`, multi-target `links` entries collapsing into one entry with multiple `rows`); include string-escaping cases (`"`, `\`, control chars, `Application Support` paths). Assert the script fails loudly when `install/topics/*` is unreadable. <!-- sdd-owner: implementation -->
- [x] GREEN: create `install/manifest.sh` implementing `json_escape` (pure Bash), `package_rows` (parse `install/topics/*`: strip comments/blanks, extract `brew`/`cask`/`tap` lines; special-installer topics `code` and `duti` become one delegating row each), `area_for_package` (explicit case table over areas `base`,`shell`,`git`,`terminal`,`vscode`,`ai`,`ai-herdr`,`claude`,`dev`,`media`,`desktop`), `link_rows` (emit `all_links` + `optional_links` verbatim), and `install_context_json <file>`. Source it from `bin/dot`. Locked members (`zsh`,`fzf`,`git`,`gh`,`tmux`) carry `"locked": true`; former baseline tools (`lazygit`,`hunk`,`yazi`,`neovim`, Ghostty) carry `"default": true`. Run `make check && make lint && make test`. <!-- sdd-owner: implementation -->
- [x] TRIANGULATE + REFACTOR: add a drift-guard test asserting every component/requirement token used in `install/links.sh` resolves to ≥1 package row via `area_for_package` (a `links.sh` rename can never silently orphan a link); then tidy the case table and emitter. Re-run gates. <!-- sdd-owner: implementation -->

## Phase 2 — TUI delta under `tools/tui/src/` (PR 2)

Covers installer-tui + installer-profile deltas. All bun tests co-located (`*.test.ts`), views stay pure-string Ink components covered by `ink-testing-library`.

- [x] RED: write `src/context.test.ts` for the context loader — valid v1 file loads; wrong/missing `version` rejected; malformed `packages`/`links` rows rejected; matches `profile.ts` hand-rolled style. <!-- sdd-owner: implementation -->
- [x] GREEN: create `src/context.ts` (~20 lines) loading + validating the context file passed via `--context <path>`. Run gates. <!-- sdd-owner: implementation -->
- [x] RED: table-driven bun tests for the ADR-3 link-filter rule: requirement hit, requirement miss, locked-area activity, inactive area, empty-selection (only locked-block untagged links offered), optional `agents` group always present and independent of selections. <!-- sdd-owner: implementation -->
- [x] GREEN: retire the embedded package/command tables in `src/manifest.ts` (Go-era source of truth); keep planning/metadata helpers and consume context `packages` instead; expose the filter rule as a pure function over confirmed selections. <!-- sdd-owner: implementation -->
- [x] RED: selector rendering tests — locked row ignores toggle key entirely; sibling rows in one topic group toggle independently; former-baseline rows start checked (`default: true`) and CAN be unchecked; multi-target link name renders as ONE row and toggles both targets together. <!-- sdd-owner: implementation -->
- [x] GREEN: implement the two-step flow in `src/tui.tsx` — Step 1: per-tool selector, locked essentials pinned at top with 🔒 marker, visual topic grouping, strictly per-row toggles, special `code`/`duti` rows included. Step 2: filtered link list (all unchecked) followed by the opt-in AI-agent group (unchecked). Quit anywhere before confirm → exit 10 with ZERO filesystem writes (profile write happens only after link confirmation). <!-- sdd-owner: implementation -->
- [x] RED: profile-semantics tests — confirmed apply writes `$DOT_PROFILE` with `.components[id] == true` for active area ids ∪ locked areas; NO link names/section appear in the profile; absent profile fields fall back to defaults. <!-- sdd-owner: implementation -->
- [x] GREEN: wire apply orchestration in `src/main.ts` — parse `--context` argv (+ forward `--dry-run`), confirm → atomic profile write (`src/profile.ts`) → planned brew installs via `src/plan.ts` (rows → `brew install x` / `brew install --cask x`) → `dot link <name>` subprocess per checked link → `dot install code` / `dot install duti` when selected. Exit codes: 0 success, 10 aborted, other non-zero propagated loudly. Mid-apply interruption prints a loud ❌ completed-vs-pending summary before exiting non-zero. Rework `-apply -profile` headless mode to consume the same context JSON + area-level profile (one code path, cannot diverge; no UI mounts). <!-- sdd-owner: implementation -->
- [x] TRIANGULATE + REFACTOR: tmpdir-based abort tests (quit at tool step, at link step, during apply) assert zero writes outside tmpdir; dedupe shared render/state helpers across steps. Run full gates (`make check && make lint && make test`). <!-- sdd-owner: implementation -->

## Phase 3 — Dispatcher flip and removals in `bin/dot` (PR 3)

Covers dot-cli-install + fresh-machine-bootstrap deltas. This PR flips the default entry point — smallest individually revertible unit.

- [x] RED: extend bats (`test/*.bats`): bare `dot install` under closed stdin exits non-zero naming `--all` and `--profile` (harness has no TTY — assert for free); `dot tui` → ordinary unknown-command error; `dot help` contains no `tui`, documents interactive default + both headless flags; completion parsed from `dot help` excludes `tui` and still lists all remaining top commands; `--all` and `--profile <name>` dry-run paths behave unchanged and never open a UI; runtime-bootstrap failure path exits non-zero naming the headless alternatives (never silent, never falls back to baseline). <!-- sdd-owner: implementation -->
- [x] GREEN: add `run_interactive_install` in `bin/dot` with ADR-5's exact order — (1) existing flag parse keeps `--all|-a` → `sub_full`, `--profile` → `run_profile_install`; (2) TTY guard `[[ -t 0 ]]` FIRST, else loud non-zero exit pointing at headless flags (no provisioning, piped curl dies in ms); (3) `sub_bootstrap` (CLT + Homebrew); (4) `is_executable bun || brew install bun`, then merged `run_dot_tui()` resolution; (5) `DOT_CONTEXT=$(mktemp)` + `install_context_json`; (6) launch `run_dot_tui --context "$DOT_CONTEXT"` (argv, not env); (7) exit mapping: 0 → applied summary, 10 → "aborted — nothing installed, nothing linked", exit 0, other non-zero → propagate. Point the bare `sub_install` case at it. <!-- sdd-owner: implementation -->
- [x] Hard-remove `dot tui`: delete `sub_tui`, the `tui` token from `TOP_COMMANDS`, and both `tui` help lines in `sub_help`; rewrite the install help section (interactive default + `--all`/`--profile`). No shim. Completion follows help automatically. Run gates. <!-- sdd-owner: implementation -->
- [x] `remote-install.sh`: comment/docs-only delta noting bare invocation is interactive and needs a TTY, headless = append `--all` or `--profile <name>` (pass-through via `"$@"` already works). Keep the revert-to-pin-`--all` rollback available. Run gates. <!-- sdd-owner: implementation -->

## Phase 4 — Tooling truth and docs (PR 4)

Covers build-tooling delta.

- [x] Makefile: delete `go-test` target and the `go vet ./...` line in `check`; `check := bash -n $(SCRIPTS)` + `tsc --noEmit -p tools/tui` + `bun test tools/tui` (via `make -C tools/tui check` if such a target exists post-merge, otherwise inline); drop `go-test` from `.PHONY`; leave `lint` (shellcheck/shfmt) unchanged. Verify `make check` passes on a machine with bun and no Go project. <!-- sdd-owner: implementation -->
- [x] `openspec/config.yaml`: rewrite context to “Bash CLI (`bin/dot`) + Bun/TS Ink TUI (`tools/tui/`) + Homebrew Bundle”; testing block → unit `bun test`, integration bats; verify/test commands → `make check && make lint && make test`; remove every Go reference (go vet, go test, go build, bubbletea, `internal/installer`, `cmd/dot-tui`, `make go-test`) from rules.apply and quality_tools. This task itself re-points the strict-TDD gate used by later applies. <!-- sdd-owner: implementation -->
- [x] `README.md`: document bare `dot install` as interactive, `--all` / `--profile <name>` as headless paths (incl. scripted/CI usage and `make install` behavior), and that `dot tui` no longer exists. Run final full gate `make check && make lint && make test`. <!-- sdd-owner: implementation -->

## Phase 5 — Apply-phase verification

- [ ] Owner manual smoke (post-apply, per design §5): run bare `dot install --dry-run` end-to-end in Terminal.app and iTerm2; verify locked block, per-row toggles, filtered link step, opt-in agents group, abort-at-each-step cleanliness, exit codes 0/10. <!-- sdd-owner: implementation -->

## Parent-gated actions (post-apply only)

- [ ] Start or reuse bounded review of the applied change. <!-- sdd-owner: parent -->
- [ ] Verify the fresh-VM bun-bootstrap branch on clean hardware before removing the `remote-install.sh` `--all` rollback pin. <!-- sdd-owner: parent -->

---

## Spec-delta coverage map

| Delta | Covered by |
| --- | --- |
| dot-cli-install | Phase 3 (dispatcher, headless flags, TTY guard, removals, help/completion) |
| installer-tui | Phase 2 (per-row selector, locked block, link step, multi-target, opt-in agents, immediate apply, abort semantics) |
| installer-profile | Phase 2 (area-level profile writes, link choices never persisted, additive/fallback-safe) |
| fresh-machine-bootstrap | Phase 0 (base resolver), Phase 3 (bun bootstrap ordering, remote-install pass-through, loud failure) |
| build-tooling | Phase 4 (Makefile, openspec/config.yaml) + Phase 1/2 tests exercising the real gates |

Design files-changed table fully mapped: `bin/dot` (P3), `install/manifest.sh` (P1),
`remote-install.sh` (P3), `context.ts` / `manifest.ts` / `tui.tsx` / `main.ts` / `plan.ts` (P2),
`Makefile` + `openspec/config.yaml` + `README.md` (P4).
