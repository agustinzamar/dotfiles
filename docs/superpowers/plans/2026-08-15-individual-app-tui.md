# Individual App TUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users select individual apps, install and link them from one persistent TUI session, and keep profiles compatible with existing aggregate selections.

**Architecture:** Keep the manifest as the single source of component metadata. Replace aggregate optional components with individual components grouped by category. The TUI owns selection and apply-loop state; the existing Bash linker remains the implementation for config links and runs after the selected profile is saved.

**Tech Stack:** Go, Bubble Tea v2, JSON profiles, Bash, Homebrew, Bats.

**Spec:** `docs/superpowers/specs/2026-08-14-granular-installer-tui-design.md` plus the approved individual-app workflow in the current conversation.

## Global Constraints

- Categories are visual groups, not selectable installation units.
- `Space` toggles only the focused component.
- `a` selects all optional components in the current category.
- `n` clears optional components in the current category.
- `/` searches component labels and categories.
- `Enter` applies selected missing components and their links, then returns to selection.
- `q` exits without applying pending changes.
- Successful work is not repeated during the same TUI session.
- Deselecting an installed component never uninstalls it or removes its config link.
- Existing aggregate profile IDs migrate once to individual component IDs.
- `dot link` becomes repair-only for the current profile; `dot link --all` remains the explicit force-all command.

---

## Files

- Modify: `internal/installer/manifest.go` for individual stable component records.
- Modify: `internal/installer/profile.go` for profile migration and selected-component helpers.
- Modify: `internal/installer/plan.go` for installed-state detection, link planning, and apply status.
- Modify: `internal/installer/tui.go` for grouped navigation, search, category actions, and the apply loop.
- Modify: `cmd/dot-tui/main.go` for repeated apply execution and profile/link persistence.
- Modify: `install/links.sh` for corrected PHP ownership and repair-only default linking.
- Modify: `bin/dot` for repair-only `dot link` behavior and TUI dispatch compatibility.
- Modify: `README.md` for the individual-app workflow and command semantics.
- Modify: `test/dot.bats` for link behavior and profile-aware CLI regression coverage.
- Create: `internal/installer/profile_migration_test.go` for aggregate profile migration tests.
- Create: `internal/installer/tui_navigation_test.go` for individual selection and apply-loop tests.

## Interfaces

- `Component` gains package and app detection data used by `Plan` to avoid repeating successful work.
- `MigrateProfileData(Profile) (Profile, bool, error)` converts old aggregate IDs to current IDs and reports whether data changed.
- `Profile.Selected(category string, query string) []Component` returns visible components in manifest order.
- `Model.Update(tea.Msg) (tea.Model, tea.Cmd)` handles selection, search, category actions, Enter apply, and q quit.
- `Model.Profile() Profile` returns a copy of the current selection.
- `Model.MarkApplied(componentIDs []string)` records successful components for the current TUI session.
- `Plan(Profile, Environment, map[string]bool) ([]Task, []Skip, error)` excludes already-applied or already-satisfied components.
- `ExecuteWithProgress(context.Context, []Task, Runner, Progress) []Result` remains sequential and reports one task at a time.
- `SaveProfile(path string, profile Profile) error` writes the selected profile atomically after each successful apply cycle.

## Tasks

### Task 1: Split Optional Components

**Files:**
- Modify: `internal/installer/manifest.go`
- Test: `internal/installer/manifest_test.go`

**Interfaces:**
- Produces individual IDs such as `communication-discord`, `communication-slack`, `communication-whatsapp`, `communication-telegram`, `media-spotify`, `media-vlc`, and `media-stremio`.
- Produces individual desktop IDs for Chrome, Firefox, Brave, Discord, Telegram, WhatsApp, Slack, Raycast, Finetune, TypeWhisper, Rectangle, Aerospace, LinearMouse, and LocalSend.

- [ ] Add one manifest record per app with one Homebrew formula or cask command.
- [ ] Move each existing optional link to the individual owning component.
- [ ] Remove aggregate `communication`, `media`, and `desktop` records.
- [ ] Test that all IDs are unique and each split app has the expected category and command.
- [ ] Run `gofmt -w internal/installer/manifest.go internal/installer/manifest_test.go`.
- [ ] Run `go test ./internal/installer`.

### Task 2: Migrate Existing Profiles

**Files:**
- Modify: `internal/installer/profile.go`
- Create: `internal/installer/profile_migration_test.go`

**Interfaces:**
- `MigrateProfileData(Profile) (Profile, bool, error)` maps `communication` to Discord, Slack, WhatsApp, and Telegram; `media` to Spotify, VLC, and Stremio; and `desktop` to all desktop app IDs.

- [ ] Write tests for each aggregate mapping and for idempotent migration.
- [ ] Make `LoadProfile` migrate old IDs before validation and save the migrated profile once.
- [ ] Preserve baseline selections and never enable optional components not represented by an old aggregate ID.
- [ ] Reject unknown IDs after migration.
- [ ] Run `go test ./internal/installer`.

### Task 3: Add Individual Selection UX

**Files:**
- Modify: `internal/installer/tui.go`
- Create: `internal/installer/tui_navigation_test.go`

**Interfaces:**
- Model state includes `category`, `query`, `applied map[string]bool`, and `submitted`.
- `Model.MarkApplied([]string)` marks only successful components and leaves failed components selected for retry.

- [ ] Test Space toggles one component without changing adjacent components.
- [ ] Test `a` selects all optional visible components in the active category.
- [ ] Test `n` clears all optional visible components in the active category.
- [ ] Test `/` enters search mode and filters labels and categories.
- [ ] Render category headers, selected counts, installed/applied state, and an empty-search message.
- [ ] Keep required baseline components selected and non-toggleable.
- [ ] Change Enter to submit the current selection without ending the process permanently.
- [ ] Update the footer to show `space toggle a all n none / search enter apply q quit`.
- [ ] Run `gofmt` and `go test ./...`.

### Task 4: Plan Only Missing Work

**Files:**
- Modify: `internal/installer/plan.go`
- Modify: `internal/installer/plan_test.go`

**Interfaces:**
- `Environment` exposes the installed Homebrew formulae and casks needed by individual components.
- `Plan(profile, environment, applied)` omits components already satisfied by the environment or marked applied in the current TUI session.

- [ ] Test that a selected installed app produces no install task.
- [ ] Test that an uninstalled selected app produces one task.
- [ ] Test that a failed component remains eligible for the next apply cycle.
- [ ] Add link operations after component installation for selected components with links.
- [ ] Keep dependency failure and cancellation behavior unchanged.
- [ ] Run `go test ./...` and `go vet ./...`.

### Task 5: Apply, Link, and Return to TUI

**Files:**
- Modify: `cmd/dot-tui/main.go`
- Modify: `internal/installer/profile.go`
- Modify: `install/links.sh`
- Modify: `bin/dot`

**Interfaces:**
- Interactive mode loops until q: `select -> Enter -> save profile -> install -> link -> show result -> select`.
- Explicit `-profile` mode remains one-shot and noninteractive.

- [ ] Save the selected profile before running links so Bash sees the current selection.
- [ ] Execute only missing selected components and mark successful components applied.
- [ ] Run profile-aware linking after installation and before returning to selection.
- [ ] Print one progress and one result line per component.
- [ ] Keep failed components selected and show their captured failure output.
- [ ] Keep successful components selected but mark them installed so the next Enter does not repeat them.
- [ ] Correct the PHP/Herd link owner from `laravel` to `php`.
- [ ] Make bare `dot link` repair selected links only; keep `dot link --all` as force-all.
- [ ] Run `bash -n bin/dot install/*.sh`, ShellCheck, and `bats test/dot.bats`.

### Task 6: Document the Workflow

**Files:**
- Modify: `README.md`
- Modify: `test/dot.bats`

**Interfaces:**
- Public docs describe `dot tui` as the normal install flow for baseline and individual optional apps.

- [ ] Document selecting Discord without Slack.
- [ ] Document that Enter installs and links, then returns to the TUI.
- [ ] Document that deselecting does not uninstall or unlink.
- [ ] Document `dot link` as repair-only and `dot link --all` as explicit force-all.
- [ ] Test the help and link behavior without adding a second command surface.
- [ ] Run the complete verification suite.

## Self-Review

- Every approved behavior maps to Tasks 1 through 6.
- No aggregate optional component remains after Task 1.
- Profile migration runs before unknown-ID validation in Task 2.
- TUI apply state and installed detection are separate, so deselection cannot uninstall or unlink.
- Links run only after the current profile is saved.
- The one-shot profile mode remains separate from the persistent interactive loop.
- No task uses placeholder instructions or undefined interfaces.

## Verification

Run after all tasks:

```bash
gofmt -w cmd/dot-tui/*.go internal/installer/*.go
go test ./...
go vet ./...
bash -n bin/dot install/*.sh
shellcheck -x bin/dot install/*.sh
bats test/dot.bats
git diff --check
```
