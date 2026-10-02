# Superfile as a Yazi alternative

## Goal
Add superfile as an optional terminal file-manager alternative to Yazi, with tracked configuration and install/link integration while leaving Yazi unchanged.

## Decisions and constraints
- Homebrew package ID is `superfile`; its executable is `spf`.
- Superfile's native macOS config directory is `~/Library/Application Support/superfile`. Link there rather than changing `XDG_CONFIG_HOME` globally.
- Keep superfile optional; do not add it to the manifest's default/prechecked package set. Keep Yazi as-is.
- Link configuration only on macOS and gate it on executable `spf`.
- Do not install or link into the user's home directory as part of this repository change.
- Do not run `spf --fix-hotkeys` or other config-mutating TUI commands against tracked sources; `--fix-hotkeys` may create a sibling backup and requires a TTY.
- The cd-on-quit wrapper uses the lastdir-file mechanism upstream ships for v1.6.0 (`cd_on_quit/cd_on_quit.sh`), not `--print-last-dir`.
- `[[ ]]` is not enforced mid-test by bats, so superfile assertions use `[ ]` and `grep`.
- TDD mode: off (no explicit project/session TDD setting found). Verification runner: `make test`; also `make check` and `make lint`.

## Tasks
- [x] **SA-1 — Map integration points and runtime paths.** Confirmed package/link/manifest conventions, macOS config location, executable name `spf`, and the installed version (Homebrew superfile 1.6.0).
- [x] **SA-2 — Add optional superfile configuration and integration.** Added the optional package, terminal/Filesystem manifest metadata, tracked config/hotkeys, macOS-only `spf`-gated links, a gated Zsh `spf` wrapper, and regression tests.
- [x] **SA-3 — Verify integration.** Independent verification plus parent correction; all authorized checks re-run green.

## Acceptance criteria
- `superfile` appears as an optional Filesystem package in the installer manifest. ✅
- Its configuration is tracked separately from `config/yazi/` and targets superfile's native macOS config directory. ✅
- `spf`-gated links are skipped when the executable is unavailable; Yazi's files and defaults remain unchanged. ✅
- Shell integration safely returns to superfile's last directory when `cd_on_quit` is enabled. ✅
- All applicable checks are recorded honestly. ✅

## Progress and evidence
- SA-1 completed from repository inspection, read-only mapping, and the installed superfile 1.6.0 source/tag.
- The first SA-2 worker was canceled after `spf --fix-hotkeys` failed without a TTY and created a zero-byte out-of-surface `hotkeys.toml.bak-3850037676`; the parent removed only that confirmed generated backup. No home-directory files were touched.
- A fresh worker completed SA-2 without invoking Superfile CLI/TUI actions, reporting `make test` 198/198, `make check`, and `make lint` green.
- Native risk assess returned `unassessable` (untracked candidate files), so the returned plan required an independent verifier.
- The independent verifier found two real defects:
  1. `config/zsh/exports/superfile.zsh` assigned zsh's read-only `status` parameter, so the wrapper would fail at runtime instead of cd-ing.
  2. The wrapper test only ran `zsh -n` and string greps, which cannot detect that runtime failure.
- Parent corrections:
  - Replaced the invented `--print-last-dir` wrapper with the mechanism upstream ships for v1.6.0: superfile writes a `cd '<dir>'` snippet to its lastdir file, and the wrapper sources then removes it. Confirmed from the v1.6.0 tag (`src/cmd/main.go`, `src/internal/model.go`, `cd_on_quit/cd_on_quit.sh`).
  - Removed `code_syntax_highlight` from `config.toml`: v1.6.0 keeps `code_previewer` in the root config and `code_syntax_highlight` in theme files.
  - Rewrote the wrapper tests as real runtime tests (stub `spf` writes the lastdir file; zsh sources the wrapper; assert the resulting `$PWD`), and converted superfile assertions to `[ ]`/`grep` because bats does not enforce mid-test `[[ ]]`.
- Evidence (all observed):
  - `make test` → 201/201, no failures.
  - `make check` → exit 0.
  - `make lint` → exit 0.
  - `python3 tomllib` → both Superfile TOML files parse.
  - `zsh -n config/zsh/exports/superfile.zsh` → syntax ok.
  - RED/GREEN proof: removing the lastdir sourcing fails the two cd tests; restoring it passes.
  - `config/superfile/hotkeys.toml` key set equals v1.6.0 upstream (46/46, no extras); `config.toml` has no unknown v1.6.0 keys.
  - No stray backups or temporary diagnostic files remain.
  - Work unit committed on `main` as `dcce373` (9 files, 291 insertions, 4 deletions); the working tree is clean.
- Known pre-existing limitation (not introduced here): bats does not enforce a failing `[[ ]]` that is not the final command, so older repo tests with mid-test `[[ ]]` assert less than they appear to.

## Next step
Nothing is pushed yet: `main` is ahead of `origin/main`. The temporary `feat/superfile-alternative` branch is now redundant and can be deleted.
