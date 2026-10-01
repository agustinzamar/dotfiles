# Feature: tool-gated zsh export snippets

**Goal**: move the `reeve` and `yazi` exports out of `config/zsh/.zshrc` into
their own snippets, symlinked into `~/.config/zsh/exports/` only when the
corresponding tool is installed.

**Why now**: `.zshrc` hardcoded `/Users/agustin/.reeve/bin`, so the tracked file
was not portable, and both exports applied on any machine, installed or not.

**Context**: `install/links.sh` carries a `requirement` column: a row is skipped
unless that binary resolves on the host. It already gates `vscode|code`,
`hunk|hunk` and `lazygit|lazygit`. `system/.exports` is the repo's home for
always-sourced app env; these two cannot live there because the gate has to
happen at link time, not at source time.

**Sources**: `install/links.sh` (map + requirement gate), `install/manifest.sh`
(`area_for_package`, the drift guard's resolver), `test/box.bash` (sandbox PATH
carries no `reeve`/`yazi`, so the gate is a declared fixture).

## Tasks

- [x] 1. Extract both exports into `config/zsh/exports/{reeve,yazi}.zsh`.
- [x] 2. Wire two requirement-gated rows in `install/links.sh`.
- [x] 3. Add the `reeve` token to `area_for_package` in `install/manifest.sh`.
- [x] 4. Replace both blocks in `.zshrc` with a null-glob over the linked dir.
- [x] 5. Tests.

## Evidence

- `make check` clean; `zsh -n` clean on `.zshrc` and both snippets.
- `bats test/links.bats test/dot.bats test/manifest.bats`: 85 tests, 6 failures —
  the same 6 as the pre-change baseline (83 tests, stashed this change) and none
  of them new: four are the `dot link --all` sandbox rows blocked by the dangling
  `claude` sources, two are the dot.bats guards that the committed
  `config/.gitignore` turned red (`every source in the link map exists`,
  `every tracked config file is wired into an install path`). Both new tests pass:
  `export snippets are gated on their tool being installed` and
  `zshrc sources the link-gated export snippets with a null glob`.
- Not yet done: independent verification before commit; nothing committed.

