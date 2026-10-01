# Feature: the two red suites (agents, git)

**Goal**: make `make test` report only genuine failures. 22 tests fail on `main`;
none of them is a product bug — both suites assert an interface that moved.

**Why now**: CI installs in every commit of this repo yet `main` has been red
since before this work; a permanently red suite hides the next real failure.

**Context**: `bin/dot` dispatches only names in `TOP_COMMANDS`; every other
`sub_*` is reachable through `dot install <name>` (`resolve_install_target`
maps `git` → `sub_git`, and the phase loops in `sub_full` call `sub_$phase`).

## Root causes (evidence, not hypothesis)

- **git.bats (14/14 fail, zero passing)** — `dot_git()` in `test/git.bats:69`
  runs `"$DOT" git "$@"`, but `git` is not in
  `TOP_COMMANDS=" agents backup clean doctor edit help install link unlink update "`,
  so the CLI answers `'git' is not a known command.` and exits 1; every test
  dies at its first `[ "$status" -eq 0 ]`. Observed via
  `bats --print-output-on-failure test/git.bats --filter "the box redirects
  global writes into the scratch config"`. The phase itself is healthy:
  `./bin/dot install git --dry-run` prints `==> 🔧 Configuring git` and exits 0.
- **agents.bats (8 fail)** — all 8 are in the wrapper section
  (`test/agents.bats:44-175`), which runs `gentle-ai sync` with
  `PATH="$REPO_ROOT/bin:$PATH"` expecting `bin/gentle-ai` to wrap the native
  binary. `bin/` holds only `dot`: the wrapper was deleted in
  `ad7a03f chore: remove AI plugin system and npm/pnpm/bun dependencies`, so
  `gentle-ai` resolves to the real installed binary and the fixture's
  expectations (managed blocks merged into `$HOME/.agents/AGENTS.md`) never
  hold. The 21 tests after line 176 — the section merge, `dot agents sync`, and
  the PI close-marker normalization — pass and touch none of that fixture.

## Tasks

- [x] 1. Point `dot_git()` at the phase's supported entry point:
  `"$DOT" install git "$@"`. No production change: the seam exists.
- [x] 2. Delete the wrapper section of `test/agents.bats` (the wrapper tests plus
  `seed_native_on_path` and the native fixture in `setup()`), keeping the merge,
  `dot agents sync`, and PI tests.
- [x] 3. Verify both loops green, then the whole suite, then commit as two work
  units (one per concern).

## Commits

- `96e77e7` test(git): drive the git phase through `dot install git`
- `5b773f7` test(agents): drop the suite for the removed `bin/gentle-ai` wrapper

## Evidence

- Loops: `bats test/git.bats --filter "the box redirects global writes into the
  scratch config"` went red (exit 1, `'git' is not a known command.`) → green;
  `test/git.bats` 14/14 (was 0/14). `test/agents.bats` 20/20 (was 21/29, with the
  9-test wrapper section deleted).
- Whole suite: **194 tests, 0 failures** (was 203 tests, 22 failures).
- `make check` clean, `make lint` clean.
- Not verifiable locally: the Ubuntu half of the CI matrix. The affected tests
  declare their platform through the box's `uname` stub, so they should not be
  platform-sensitive, but the push is where that gets confirmed.
