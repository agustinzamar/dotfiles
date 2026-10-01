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
- Shipped as `43267b8` (feat(zsh): gate the reeve and yazi exports at link
  time). The residual failures quoted above were later traced to `dot link
  --all` being unimplemented plus the two stale `claude` rows — not to the
  `claude` sources alone. Both are fixed in `d5ab2ad`; see
  `link-gate-coherence.md`.
- Independent verification went to the `gentle-ai-verify` role twice and failed
  on the agent side both times (0 tool calls, "assistant reported an error"), so
  the claims were verified inline instead: whole suite 202 tests / 180 pass / 22
  fail, the 22 byte-identical to the stashed baseline (`agents.bats` 8,
  `git.bats` 14), and the four touched suites 96/96.

