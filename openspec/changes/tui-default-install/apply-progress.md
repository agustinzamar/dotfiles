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
