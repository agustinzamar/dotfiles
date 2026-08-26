# Make the installer TUI the default `dot install` experience

One decision drives this change: `dot install` should be an interactive, tool-by-tool
experience instead of a fixed baseline script, and the separate `dot tui` entry point
goes away. The TUI gets three concrete upgrades negotiated with the owner — every
package gets its own toggleable line (no more group selectors), Base/Shell essentials
become a visible locked block, and a second step offers exactly the config links that
belong to whatever was selected.

## Quick path

1. Review **Proposed solution** for the two-selector flow (tools → config links).
2. Check **Impact on fresh-machine bootstrap** — this is the riskiest surface.
3. Check **Resolved decisions** — all proposal questions are answered.

## Problem statement

Today `bin/dot` exposes two install paths that don't compose well:

- A bare `dot install` runs `sub_bootstrap` + `sub_baseline` + `sub_link`
  (`bin/dot`, `sub_install`, case `"" | bootstrap`) — a hardcoded package list in
  `sub_baseline` plus Zsh/Git setup. There is no choice involved.
- `dot tui` (`sub_tui`) shells out to `go run "$DOTFILES_DIR/cmd/dot-tui"` — but the
  Go tree (`cmd/`, `internal/installer`) no longer exists on `main` (tag
  `pre-go-removal`; `.gitignore` now reserves `tools/tui/` for "bun build output,
  no source yet"). Both `sub_tui` and `run_profile_install` reference a binary that
  isn't there, so both commands are broken today.

Where a TUI did exist, it grouped tools into single toggleable lines ("AI tools",
"Terminal tools", "Git, SSH signing, Hunk and GitHub tools"), forcing all-or-nothing
choices per group. Config linking was never part of the flow: `dot link` links every
map entry whose component is selected (or everything with `--all`), decided entirely
outside any selector.

The cost: a fresh-machine install either takes everything in `sub_baseline` or needs
hand-editing a `profile.json`; picking individual tools requires a broken command;
and linking configs is a separate, easy-to-forget step.

## Goals

- Bare `dot install` opens the TUI by default. Non-interactive paths survive for
  bootstrap/CI/scripts: `dot install --all` (full phases) and
  `dot install --profile <name>` (saved profile).
- Tool selector granularity: **every brew/cask entry is its own toggleable line**.
  No group toggles anywhere. Base/Shell essentials form a locked block — always
  installed, always visible, not toggleable.
- New **config-link step**: after tool selection, a second selector lists ONLY the
  config links that belong to the selected tools (data from `install/links.sh`,
  including its `component` column). Nothing links unless explicitly checked.
- Hard-remove `dot tui`: drop `sub_tui`, its help lines, and its `TOP_COMMANDS`
  entry. No deprecation shim (personal repo).

## Non-goals

- No changes to the topic Brewfiles themselves (`install/topics/*` content stays).
- No change to standalone `dot link` / `dot link <name>` behavior outside the TUI.
- `dot ai` and the opt-in AI agent links (`optional_links` in `links.sh`) keep their
  current deliberate, manual model — they do not join the link selector unless the
  Open Questions answer says otherwise.
- No profile format migration tooling beyond what the TUI writes.

## Proposed solution

**Flow.** Bare `dot install` resolves to a TUI launch instead of
`bootstrap + baseline + link`. Two sequential selectors:

1. **Tools.** Every entry from the package manifests renders as an individual row,
   sourced from the same data `install/topics/*` already declares (one name per
   line — the manifests are already flat data, see `read_package_file`). Rows are
   grouped visually by topic for scanning, but toggles are strictly per-row.
   The Base/Shell essentials block (see below) renders at top, marked locked, never
   toggleable. `install/topics/code` (VS Code extensions) and `topics/duti` keep
   their special installers and appear as their own selectable rows.
2. **Config links.** A second selector built by joining `all_links` rows against the
   selected components: a link row appears iff its `component` tag matches a selected
   tool (or it has no component tag and belongs to the locked block). Multi-target
   names (`ghostty` → 2 targets) toggle together under one label, matching how
   `link_named` treats names. Default: unchecked. Nothing links unless checked.
   A final opt-in group offers the AI agent links (`optional_links`), unchecked
   by default. Confirmed link choices apply immediately; they are NOT persisted
   to `profile.json` — the profile keeps tool selections only, and future bare
   `dot link` runs stay free-form.

**Locked essentials.** A minimal locked block, slimmer than today's
`sub_baseline`: only a true bootstrap core (shell + git + Homebrew-adjacent
basics such as `zsh fzf git gh tmux` plus Zinit/Zsh setup and Git signing
config). Everything else that `sub_baseline` used to force — `lazygit`,
`hunk`, `yazi`, `neovim`, Ghostty, etc. — becomes an individually toggleable
row, pre-checked to preserve current-baseline behavior.

**State.** Selections persist to the existing `DOT_PROFILE`
(`~/.config/dot/profile.json`) using the shape `install/components.sh` already reads
(`.components[id] == true` via jq), extended with a `links` section for checked link
names. `component_selected()` keeps working unchanged for `dot link` gating, so a
TUI run and later `dot update` re-links stay consistent.

**Removals.** Delete `sub_tui`, its `TOP_COMMANDS` entry, and the two `tui` help
lines in `sub_help`. Re-point `run_profile_install` at whatever launcher serves the
TUI runtime (see Open Questions). Update `README.md`, and align
`openspec/config.yaml`, whose stack description (Go 1.26 / bubbletea /
`internal/installer` / `cmd/dot-tui` / `make go-test`) no longer matches `main`.
`Makefile`'s `check`/`go-test` targets also invoke `go vet ./...` over a tree with no
Go packages and need re-pointing at the actual TUI runtime checks.

## Impact on fresh-machine bootstrap

- `remote-install.sh` ends with `exec "$TARGET/bin/dot" install "$@"` and `make`
  defaults to `dot install` — both become interactive by default. On a truly fresh
  Mac only Xcode CLT/git/curl exist; **no TUI runtime (bun/go) is installed yet**, so
  the TUI cannot simply launch where today's pure-Bash baseline works.
- Mitigation (proposed): bare `dot install` first ensures the TUI runtime exists
  (brew-installing it if missing, after Homebrew bootstrap), then launches. The
  documented headless path for CI/scripted machines becomes
  `dot install --all` or `dot install --profile <name>`; `remote-install.sh` gains
  pass-through of those flags (it already forwards `"$@"`).
- Non-TTY stdin (piped curl | bash without flags): MUST fail loudly with a pointer
  to `--all` / `--profile`, never hang or silently skip.
- `dot doctor`, `dot link`, `dot unlink` behavior is untouched; the profile-aware
  component gating in `_walk_links` continues to work with TUI-written profiles.

## Rollback plan

Risk level: medium-high (default entry point changes). Mitigations:

- All shell-side changes land in a small number of commits touching `bin/dot`,
  `remote-install.sh`, docs. A single `git revert` restores the old dispatcher:
  bare `install` → `bootstrap+baseline+link`, `tui` command back on `TOP_COMMANDS`.
- The TUI itself lives in an isolated directory (`tools/tui/`, already gitignored
  for build output); deleting it does not affect the Bash CLI.
- Profile writes are additive JSON at `$DOT_PROFILE`; rollback leaves stale files
  harmless because `component_selected` falls back to defaults when fields are absent.
- Bootstrap safety net: until the runtime-bootstrap step is verified on a clean VM,
  `remote-install.sh` can be pinned to `--all` behavior by reverting just that file.

## Resolved decisions (owner-answered)

1. **Base branch (was blocking).** Merge `migrate-tui-to-bun` into `main` first
   (its SDD change is verified; user-owned interactive smoke test still pending),
   then this change builds on the merged result. The Bun/TS TUI under `tools/tui/`
   is the runtime; `openspec/config.yaml` and `Makefile` are aligned to it.
2. **Locked block.** Minimal lock: shell + git core only; `lazygit`, `hunk`,
   `yazi`, `neovim`, Ghostty and the rest of the old baseline become per-tool
   rows (pre-checked).
3. **Link persistence.** Apply immediately, do not persist link choices to
   `profile.json`; tool selections persist as today.
4. **Opt-in AI links.** Offered as a final unchecked opt-in group in the link
   step (no longer manual-only).
5. **Abort semantics.** Quitting mid-flow installs and links nothing.

## Checklist

- [ ] Bare `dot install` launches the TUI; `--all` and `--profile` remain headless
- [ ] Every brew/cask entry is an individually toggleable row; no group toggles
- [ ] Base/Shell essentials visible, locked, always installed
- [ ] Link step lists only links belonging to selected tools; nothing links unless checked
- [ ] `dot tui`, `sub_tui`, help lines removed; completion (parses `dot help`) stays correct
- [ ] Fresh-machine path verified: `remote-install.sh` reaches either TUI or a loud headless error
- [ ] `openspec/config.yaml` + `Makefile` targets match the real runtime
