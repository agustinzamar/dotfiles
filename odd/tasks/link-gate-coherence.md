# Feature: make the link map's requirement gate coherent

**Goal**: turn the repo's six red guards green and make the requirement gate mean
the same thing to every walker, without weakening any check.

**Why now**: the gate added for the gated export snippets exposed that `dot
doctor` ignored it, and while measuring that, the red suites turned out to have a
different root cause than the dangling rows.

**Context**: `install/links.sh` carries `name|source|target|mode|component|requirement`.
`link_file` gates on the requirement; `check_link` (doctor) did not, because
`_walk_links` never passed it down.

## Tasks

- [x] 1. Implement `dot link --all` (`--all` and `all`), the documented verb.
  - Why: `README.md` documents `link --all` as "Force-link every valid config
    explicitly", and `test/doctor.bats` explains that bypassing the component and
    requirement gates is what makes a complete tree reachable in a box. `sub_link`
    had no such case, so `--all` fell through to `link_named "--all"` →
    `grep: unrecognized option '--all'` → exit 1. This was the real cause of the
    14 red tests, not the config drift.
  - Why both spellings: `install/links.sh`'s own comment says `dot link all`.
- [x] 2. Drop the two stale `claude` map rows.
  - Why: commit 6e64fd6 replaced link-managed Claude settings with a merge, and
    `config/claude/` no longer exists in the repo. The live `~/.claude/settings.json`
    is app-written (it now carries a herdr SessionStart hook), and
    `statusline-command.sh` exists nowhere. Under `set -Eeuo pipefail` a missing
    source aborts the walk, so both rows broke `dot link --all` and the
    `every source in the link map exists` guard.
- [x] 3. Exempt `config/.gitignore` from the orphan guard.
  - Why: repo metadata, not an installable config. Deleting the file was the
    alternative; the root `.gitignore` already ignores `config/.atl/`.
- [x] 4. Make `dot doctor` requirement-aware.
  - Acceptance: `_walk_links` passes the row's requirement to the action;
    `check_link` treats a row as absent-by-design when the binary is missing.
  - Fixture note: the Library-target test now has to `stub code`, because it
    removes the symlink of a `code`-gated row and wants that to be a fault.
- [x] 5. Delete the dead mysql-client block from `system/.exports`.
  - Why: it gates on `/opt/homebrew/opt/mysql-client/bin`; the installed formula
    is `mysql` (26.7.0_3, linked into `/opt/homebrew/bin`), so the block never
    fired and the PATH entry it would add is redundant.
- [x] 6. Fix `dot link <name>` for any requirement-gated name.
  - Why: `link_named` read the requirement through a pipe into an
    early-exiting `awk`, so the map writer took SIGPIPE and,
    under `set -o pipefail` + `set -e`, the CLI died with exit 141 before
    linking anything. `vscode`, `hunk` and `lazygit` were all dead that way;
    the gated export rows are what made it visible.
  - Fix: read the map once and filter it through here-strings, the precedent
    documented in `install/php.sh`.

## Commits

- `d5ab2ad` fix(link): implement the documented `dot link --all` (tasks 1-2)
- `7124058` fix(doctor): honor the requirement gate when checking links (task 4)
- `bcae6c3` test(dot): exempt config/.gitignore from the orphan guard (task 3)
- `71248b4` chore(exports): retire the dead mysql-client block and fix the PATH
  doc (task 5)
- `b088e98` fix(link): stop the requirement lookup from killing
  `dot link <name>` (task 6)

## Evidence

- Whole suite: 203 tests, 180 pass, 22 fail — `agents.bats` (8) and `git.bats`
  (14), identical to the baseline measured with this change stashed. Zero
  regressions, and the 16 failures in the touched files are gone: links 4 → 0,
  doctor 10 → 0, dot 2 → 0. The four touched suites are 97/97, one test more
  than before only because task 6 added its regression case.
- `make check` clean; `shellcheck` clean on `bin/dot`, `install/links.sh`,
  `install/manifest.sh`; `shfmt -d` still flags the pre-existing `$((i+1))`
  spacing at `bin/dot:439`, untouched by this work.
- Adversarial check of the new doctor semantics, in a throwaway $HOME with a
  stubbed PATH: a gated row whose requirement IS present but whose symlink is
  missing is still reported `broken:` (1 hit); with the requirement absent the
  row is silent (0 hits); a row with no requirement is still reported (1 hit).
- Independent verification was routed to the `gentle-ai-verify` role and failed
  on the agent side twice (0 tool calls, "assistant reported an error"), so the
  claims above were verified inline.
