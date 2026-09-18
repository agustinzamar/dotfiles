# Remove profiles — feature document

## Objective

Delete every trace of the two unused profile systems: the install area-profile
(`~/.config/dot/profile.json`, `DOT_PROFILE`, TUI `--profile`) and the AI SDD
model profile (`ai/gentle-ai/sdd-profile.json` + `dot ai profile-sync`).

## Problem

Two profile layers add concepts, flags, files and sync machinery nobody uses.
The install profile persists per-area selection that is never read back
meaningfully; the AI profile projects model assignments through a script instead
of letting each agent config stand alone.

## Why

User decision: neither feature is used. Simplification drive in this repo
(remove, do not complicate). Fewer concepts, fewer flags, fewer moving parts.

## Scope (authorized)

Delete (5 files, 986 lines):

- `tools/tui/src/profile.ts`
- `tools/tui/src/profile.test.ts`, `tools/tui/src/profile.migration.test.ts`
- `tools/scripts/sync-sdd-profile.ts`
- `ai/gentle-ai/sdd-profile.json`

Edit (no behavior change except removal):

- `tools/tui/src/main.ts` — drop `--profile` flag, profile write step,
  `runFlagMode`, `defaultProfilePath`; bump `TUI_VERSION` v12 → v13
- `tools/tui/src/manifest.ts` — drop `activeProfileAreas`
- `tools/tui/src/main.test.ts`, `manifest.test.ts` — drop profile tests,
  update version assertion
- `install/components.sh` — drop `DOT_PROFILE`/jq branch; static baseline only
- `test/dot.bats` — drop `DOT_PROFILE` tests, drop sdd-profile projection test,
  keep AGENTS.md opt-in assertion without profile file
- `test/tui-resolver.bats` — update marker fixtures + non-TTY test wording
- `bin/dot` — drop `profile-sync` block + `AI_PROFILE_ROWS`, bump marker check
- `install/ai.sh` — drop `ai_apply_model_assignments` + `AI_PROFILE_ROWS`
- `README.md` — rewrite profile paragraph + `link` row
- `remote-install.sh` — selfcheck probe without `-profile`
- Comment-only: `context.ts`, `ai.tsx`, `apply.tsx`

Out of scope (incidental word matches, NOT features):

- `config/vscode/settings.json` (terminal profiles), `system_profiler` uses,
  `.bash_profile` in duti topic, `ai/opencode/opencode.json` (live config stays)

## Constraints

- `install/links.sh` keeps calling `component_selected()` unchanged; the
  component gate stays as a static baseline (base|shell|git|terminal on,
  rest incl. `ai` opt-in). No behavior change for `link` / `link --all`.
- Pre-existing dirty tree (`config/vscode/settings.json`, `install/ai.sh`
  codex line, `install/topics/core`, untracked Brewfile/Caskfile) is NOT mine;
  never stage or commit it. `install/ai.sh` edits go on top, preserving the
  codex-line removal.
- RDD is off (clone-local), so no native review lifecycle; ordinary checks only.

## Tasks

- [x] RP-1: TUI install-profile removal (delete profile.ts, main.ts surgery,
  manifest.ts, version bump v13)
- [x] RP-2: TUI tests update (delete 2 test files, fix main/manifest tests)
- [x] RP-3: Bash install-profile removal (components.sh, dot.bats,
  tui-resolver.bats, README, remote-install.sh, comments)
- [x] RP-4: AI profile-sync removal (json, script, bin/dot block, ai.sh,
  dot.bats AI test)
- [x] RP-5: Full verification (`make bun-test`, `make test`, `make check`)

## Acceptance criteria

- No `profile.json`, `DOT_PROFILE`, `--profile`, `profile-sync`,
  `sdd-profile`, `activeProfileAreas`, `loadProfile`, `saveProfile`,
  `AI_PROFILE_ROWS`, `ai_apply_model_assignments` reference remains in the
  scoped files (incidental matches excluded above stay).
- `make bun-test`, `make test`, `make check` green.
- `dot link` (bare) still skips opt-in components incl. AI files.

## Applicable checks

- `make bun-test` (TUI), `make test` (bats), `make check` (syntax).
- Ordinary checks (deletion work; no strict RED possible). Source: Makefile.

## Delivery

- Forecast: ~1300 diff lines (mostly deletions) — over the ~400 heuristic.
- Strategy: `ask-on-risk` (default). No PR requested; split-vs-exception
  decision deferred to PR time. One work-unit commit per task on this branch.

## Progress

- RP-1..RP-3: commits recorded here as evidence per task._
- RP-4: `ai/gentle-ai/sdd-profile.json` + `tools/scripts/sync-sdd-profile.ts`
  deleted via `git rm`; `bin/dot` profile-sync block + `AI_PROFILE_ROWS` +
  model-assignments call removed; `install/ai.sh` `AI_PROFILE_ROWS` append +
  `ai_apply_model_assignments` removed (pre-existing codex-line removal
  preserved); both Gentle-AI bats tests removed. AI filter: 12/12 pass.
- RP-5: `make bun-test` 129 pass / 0 fail. `make test`: only the 3 proven
  pre-existing failures (dot.bats newline guard from untracked
  Brewfile/Caskfile; manifest.bats real-tree 165+170 from dirty
  `install/topics/core`). `make check` exit 0 after removing the dead
  `makeTempDir`/`makeContextFile` fixture + unused imports RP-2 left in
  `main.test.ts` (TS6133).
- Engram mirror (`odd/remove-profiles/tasks`, id 1282): pending sync, no
  memory tool in this runtime.

## Next step

Feature complete. Decide PR split vs `size:exception` at PR time; no commit
requested yet. Pre-existing dirty files stay unstaged.
