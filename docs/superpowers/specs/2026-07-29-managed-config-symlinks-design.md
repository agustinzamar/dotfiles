# Managed Config Symlink Adoption

## Goal

Keep Claude and OpenCode settings versioned in this repository without letting
`dot install` replace newer app-written settings with an older tracked copy.
External application repositories remain out of scope.

## Design

The link map will mark `config/claude/settings.json` and
`config/opencode/opencode.json` as app-managed. When an expected target is
already the correct symlink, linking remains a no-op.

When an app-managed target is instead a regular file and differs from the
tracked source, `link_file` will:

1. Back up the previous tracked source under the timestamped dotfiles backup.
2. Copy the live app file over the tracked source so Git exposes the change.
3. Move the live app file to the existing home-path backup location.
4. Recreate the symlink to the now-current tracked source.

Ordinary links retain the existing source-wins behavior. A foreign symlink is
also handled as before; only regular files marked app-managed are adopted.

## Safety and Errors

Both pre-adoption versions remain recoverable. Each filesystem operation keeps
the existing fail-fast behavior, so a failed copy or move stops before later
steps can hide the failure. Dry runs print every planned operation without
changing either file.

The installer does not restore OpenCode V1 backups, migrate incompatible
plugins, inspect secrets, or modify Muxy or any other external repository.

## Verification

A Bats regression test will start with different tracked and live settings,
invoke the app-managed link path, and assert that:

- the tracked source contains the live settings;
- the home target is a symlink to the tracked source;
- both the previous tracked source and live file have backups.

The existing link, dry-run, idempotency, and full Bats suites must still pass.
