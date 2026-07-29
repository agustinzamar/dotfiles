# Git-Managed App-Writable Configs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve newer Claude and OpenCode settings in Git when either application replaces its managed symlink with a regular file.

**Architecture:** Add an optional `app-writable` mode to the existing declarative link map. `link_file` will adopt a differing regular target into the tracked source, retaining backups of both previous versions, before restoring the symlink; every other link keeps its current source-wins behavior.

**Tech Stack:** Bash, Bats, Git

## Global Constraints

- Modify only the dotfiles repo (this clone).
- Git remains the canonical owner of both settings files.
- Mark only `config/claude/settings.json` and `config/opencode/opencode.json` as app-writable.
- Do not add Claude managed settings.
- Do not add or track OpenCode `cli.json`.
- Preserve the existing dry-run and fail-fast behavior.
- Add no dependency or background process.

---

### Task 1: Adopt App-Written Settings Before Relinking

**Files:**
- Modify: `install/links.sh:28-58`
- Modify: `install/common.sh:33-57`
- Test: `test/dot.bats:410`

**Interfaces:**
- Consumes: existing `all_links`, `_walk_links`, `link_file`, `run`, `BACKUP_DIR`, and `backup_path`
- Produces: optional third link-map field `app-writable`; `link_file <source> <target> [mode]`

- [ ] **Step 1: Write the failing regression test**

Add this test after `"a replaced file is backed up under its own path"`:

```bash
@test "app-writable config adopts a regular live file before relinking" {
  local home repo source target
  home="$(mktemp -d)"
  repo="$(mktemp -d)"
  source="$repo/config/claude/settings.json"
  target="$home/.claude/settings.json"
  mkdir -p "$(dirname "$source")" "$(dirname "$target")"
  printf '%s\n' '{"tracked":true}' >"$source"
  printf '%s\n' '{"live":true}' >"$target"

  DOTFILES_DIR="$repo" HOME="$home" DRY_RUN=false \
    bash -c '. "$1"; link_file config/claude/settings.json "$HOME/.claude/settings.json" app-writable' \
    _ "$DOTFILES_DIR/install/common.sh"

  [ "$(cat "$source")" = '{"live":true}' ]
  [ "$(readlink "$target")" = "$source" ]
  [ "$(cat "$home"/.dotfiles-backup/*/.claude/settings.json)" = '{"live":true}' ]
  [ "$(cat "$home"/.dotfiles-backup/*/.dotfiles-source/config/claude/settings.json)" = '{"tracked":true}' ]
}
```

- [ ] **Step 2: Run the new test and confirm the missing behavior**

Run:

```bash
bats --filter 'app-writable config adopts' test/dot.bats
```

Expected: FAIL at the tracked-source assertion because the current `link_file` ignores the mode and leaves `{"tracked":true}` in the source.

- [ ] **Step 3: Pass the optional mode through the link map**

Change the Claude and OpenCode entries in `all_links`:

```bash
config/claude/settings.json|$HOME/.claude/settings.json|app-writable
config/opencode/opencode.json|$HOME/.config/opencode/opencode.json|app-writable
```

Update `_walk_links` so existing two-field entries still receive an empty mode:

```bash
_walk_links() {
  local source target mode
  while IFS='|' read -r source target mode; do
    [[ -n "$source" ]] || continue
    "$2" "$source" "$target" "$mode"
  done < <("$1")
}
```

- [ ] **Step 4: Adopt a differing regular target before the existing backup and link flow**

Update `link_file` in `install/common.sh`:

```bash
# link_file <repo-relative-source> <absolute-target> [mode]
link_file() {
  local source="$DOTFILES_DIR/$1" target=$2 mode=${3:-} current backup source_backup
  if [[ ! -e "$source" && ! -L "$source" ]]; then
    # Generated configs (see install/git.sh) do not exist during a dry run,
    # so only treat a missing source as fatal when actually installing.
    if "$DRY_RUN"; then
      echo "note: source not present yet: $source" >&2
    else
      echo "missing source: $source" >&2
      return 1
    fi
  fi

  current=$(readlink "$target" 2>/dev/null || true)
  [[ "$current" == "$source" ]] && return 0

  if [[ "$mode" == app-writable && -f "$target" && ! -L "$target" ]] &&
    ! cmp -s "$source" "$target"; then
    source_backup="$BACKUP_DIR/.dotfiles-source/$1"
    run mkdir -p "$(dirname "$source_backup")"
    run cp "$source" "$source_backup"
    run cp "$target" "$source"
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    backup=$(backup_path "$target")
    run mkdir -p "$(dirname "$backup")"
    run mv "$target" "$backup"
  fi
  run mkdir -p "$(dirname "$target")"
  run ln -s "$source" "$target"
}
```

- [ ] **Step 5: Run the focused link tests**

Run:

```bash
bats --filter 'app-writable|link|replaced file' test/dot.bats
```

Expected: all selected tests PASS.

- [ ] **Step 6: Run the complete verification**

Run:

```bash
make check
make lint
bats test
git diff --check
```

Expected: every command exits `0`; Bats reports no failed tests; `git diff --check` prints nothing.

- [ ] **Step 7: Review the real settings adoption with a dry run**

Run:

```bash
./bin/dot install link --dry-run
```

Expected: Claude prints copies for the previous tracked source and current live settings, followed by the existing backup and symlink commands. OpenCode prints nothing because its current target is already the correct symlink.

- [ ] **Step 8: Commit only the implementation**

Run:

```bash
git add install/common.sh install/links.sh test/dot.bats
git commit -m "fix: preserve app-written managed settings"
```
