# AI Assets Plan — one manifest, one picker

Status: proposed. Written 2026-08-29. Supersedes nothing; extends
`docs/ai-config-sync-plan.md` (implemented).

## Goal

Manage skills, plugins and agent configs the way a Brewfile manages packages:
one declarative manifest, one command, granular selection per item and per
agent. Everything AI-related lives under `ai/`. `gentle-ai` installs from the
same picker and then runs its own installer.

## What already exists

Most of the mechanism is built. This plan extends it; it does not replace it.

| Piece                                | State     | File                             |
| ------------------------------------ | --------- | -------------------------------- |
| Declarative skill manifest           | ✅ exists | `ai/skills.json`                 |
| Declarative plugin manifest          | ✅ exists | `ai/plugins.json`                |
| Per-agent install command per entry  | ✅ exists | `install/ai.sh`                  |
| Agent detection by executable        | ✅ exists | `AI_AGENTS` in `install/ai.sh`   |
| Headless install                     | ✅ exists | `dot ai [agent] [--skills]`      |
| Per-machine gate                     | ✅ exists | `components` key + `dot profile` |
| Generated instruction files          | ✅ exists | `filtered` mode, `install/links.sh` |
| Item-level picker                    | ❌ missing | this plan                        |
| `pi` as a declared agent             | ❌ missing | this plan                        |
| `gentle-ai` entry                    | ❌ missing | this plan                        |
| AI configs under `ai/`               | ❌ missing | still in `config/claude`, `config/codex` |

## Discard from the current working tree

| Item                                                    | Verdict | Reason                                                                                                                             |
| ------------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Untracked `config/codex/config.toml`                    | ❌ drop | 434 lines, most of it machine state: absolute `/Users/agustin` paths, per-project trust entries, hook trust hashes, marketplace cache revisions, local marketplace paths, installed-plugin state. Seeding a new machine with it is worse than seeding nothing. |
| Link row `codex\|config/codex/config.toml\|…`           | ❌ drop | Depends on the file above.                                                                                                          |
| `config/claude/settings.json` (already committed)       | ⚠️ trim | Same class of problem, smaller: `hooks` commands hold absolute `/Users/agustin/.claude/...` paths, and `autoMode.environment` names one private project. Keep the file, template the paths. |
| `ai/.pi/gentle-ai/persona.json` path                     | ⚠️ move | Hidden dir for no reason. Becomes `ai/pi/gentle-ai/persona.json`.                                                                     |
| `ai/AGENTS.md` section markers + Laravel removal        | ✅ keep | Works, tested.                                                                                                                       |
| `filtered` link mode (`links.sh`, `common.sh`, `bin/dot`) | ✅ keep | Good mechanism; the picker builds on it.                                                                                             |
| `components` gate in `ai_manifest_lines`                | ✅ keep | Stays the headless path when no picker runs.                                                                                         |
| New bats cases                                          | ✅ keep | —                                                                                                                                    |

## Decisions

### D1. One manifest per kind, not `ai/<agent>/<kind>/`

Rejected: `ai/{claude,opencode,pi,codex}/{plugins,skills}`.

The same upstream ships as a plugin in one CLI and a skill in another —
`superpowers` is a Claude plugin, a Codex plugin and an `npx skills` install on
OpenCode. A per-agent tree stores that one thing in three places and lets the
copies drift. The manifest already models it correctly: one entry, one
`install` map keyed by agent.

`ai/<agent>/` is for real files that belong to exactly one agent: its config,
its statusline script, its persona.

### D2. Entry schema gains `id`, `label`, `description`

The picker needs a stable key and human text. `name` stays accepted as an alias
for `id` so the migration is one commit, not a flag day.

```json
{
  "id": "ponytail",
  "label": "Ponytail",
  "description": "Lazy senior dev mode: forces the simplest solution that works.",
  "install": {
    "claude-code": "claude plugin install ponytail@ponytail --scope user",
    "codex": "codex plugin add ponytail@ponytail",
    "opencode": "opencode plugin @dietrichgebert/ponytail@4.9.0 --global"
  }
}
```

Skill entries keep `source` + `skills` and their default `npx skills` command;
`label`/`description` become optional, defaulting to the source string. An
entry present for only some agents is simply absent from the others' columns.

### D3. `pi` becomes a declared agent

`AI_AGENTS=(claude-code:claude codex:codex opencode:opencode pi:pi)`. One line.
Everything else — help text, error messages, manifest default — reads from it.

### D4. `gentle-ai` is a manifest entry with `interactive: true`

`ai_install` runs each command as `eval "$cmd" </dev/null`. `gentle-ai` opens
its own TUI and needs the terminal. The `interactive` flag does two things:
run without the stdin redirect, and sort the entry last so a long interactive
installer never blocks the batch.

```json
{
  "id": "gentle-ai",
  "label": "Gentle AI",
  "description": "SDD orchestration and receipt-driven review. Runs its own installer TUI.",
  "interactive": true,
  "install": { "claude-code": "…", "codex": "…", "opencode": "…", "pi": "…" }
}
```

### D5. The picker is a second TUI, not a change to the install TUI

`docs/ai-config-sync-plan.md` deferred this. The reasons it gave were about
retrofitting the install TUI's package-shaped schema. A separate picker does
not touch that schema, so they no longer apply.

Command surface:

| Command                | Behavior                                        |
| ---------------------- | ----------------------------------------------- |
| `dot ai`               | Opens the picker (requires a TTY)               |
| `dot ai --all`         | Current behavior: everything, every agent found  |
| `dot ai <agent>`       | Unchanged                                       |
| `dot ai --profile P`   | Headless, replays a saved selection             |
| `dot ai --dry-run`     | Unchanged, composes with all of the above       |

Flow:

1. Detect agents by probing each `AI_AGENTS` executable. Absent agents are
   shown greyed out and cannot be selected.
2. Pick items — skills and plugins in one list, tagged by kind, showing which
   agents each one supports.
3. Pick agents — only from the detected set, pre-checked.
4. Confirm: render the resolved `item [agent] → command` list before running.
5. Run, then write the selection to `~/.config/dot/ai-profile.json`.

**Decided: Ink with `@inkjs/ui`.** `tools/tui` already depends on `ink`,
`react`, and `@inkjs/ui`, so the picker adds no new dependency and no new build
step. Every step maps to a component that already exists:

| Step         | Component                          |
| ------------ | ---------------------------------- |
| Pick items   | `MultiSelect` from `@inkjs/ui`     |
| Pick agents  | `MultiSelect` from `@inkjs/ui`     |
| Confirm      | `ConfirmInput` from `@inkjs/ui`    |
| Run progress | `Spinner` and `StatusMessage`      |

New entry point `tools/tui/src/ai.tsx`, tested with `ink-testing-library` like
`src/tui.tsx`. Do not write custom selection widgets.

### D6. AI configs move under `ai/`

| From                                | To                              | Tracked content                                    |
| ----------------------------------- | ------------------------------- | -------------------------------------------------- |
| `config/claude/settings.json`       | `ai/claude/settings.json`       | Portable settings only; `$HOME` paths templated     |
| `config/claude/statusline-command.sh` | `ai/claude/statusline-command.sh` | Unchanged                                        |
| `config/codex/config.toml` (untracked) | `ai/codex/config.example.toml` | Portable subset only; never the live file          |
| `ai/.pi/gentle-ai/persona.json`     | `ai/pi/gentle-ai/persona.json`  | Unchanged                                          |
| —                                   | `ai/opencode/opencode.json`     | New, portable subset                               |

`config/` keeps everything that is not an AI agent.

### D7. Agent configs are seeded, not asserted

`app-writable` already means "a live file on purpose, never a symlink". Keep
that mode for every agent config: the CLI owns the file after the first seed.
Absolute paths are expanded from `$HOME` at seed time, so a tracked template
has no machine baked into it.

## Work items

| #   | Item                                                                     | Files                                             |
| --- | ------------------------------------------------------------------------ | ------------------------------------------------- |
| 1   | Drop `config/codex/config.toml` and its link row                         | `install/links.sh`                                |
| 2   | Move `config/claude/*` → `ai/claude/*`, `ai/.pi` → `ai/pi`, update rows   | `install/links.sh`, `test/dot.bats`               |
| 3   | Template `$HOME` out of `ai/claude/settings.json` hooks                  | `ai/claude/settings.json`, `install/common.sh`    |
| 4   | Add `ai/codex/config.example.toml` with the portable subset only          | new file                                          |
| 5   | Add `id`/`label`/`description`/`interactive` to both manifests           | `ai/skills.json`, `ai/plugins.json`, `install/ai.sh` |
| 6   | Add `pi` to `AI_AGENTS`                                                  | `install/ai.sh`                                   |
| 7   | Add the `gentle-ai` entry and honor `interactive`                        | `ai/plugins.json`, `install/ai.sh`                |
| 8   | Add the picker; move today's behavior behind `--all`                     | `install/ai.sh`, `bin/dot`                        |
| 9   | Write and replay `~/.config/dot/ai-profile.json`                         | `install/ai.sh`                                   |
| 10  | Bats coverage for schema, `interactive`, profile replay                  | `test/manifest.bats`                              |

Order matters only for 1–2 before 8: the picker should not offer a config that
is about to move.

## Verification

| Check                                                | Expected                                            |
| ---------------------------------------------------- | --------------------------------------------------- |
| `dot ai --all --dry-run`                             | Prints every command, runs none                     |
| `dot ai --dry-run` with a selection                  | Prints only the selected `item [agent]` pairs       |
| `dot ai` with `pi` absent                            | `pi` unselectable, no error                         |
| `dot ai` selecting only `gentle-ai`                  | Runs last, keeps the TTY, opens its own installer   |
| `dot doctor`                                         | No broken links after the `ai/` move                |
| `make test`                                          | Green except the two known pre-existing failures    |
| Fresh machine, no `ai-profile.json`                  | Picker opens with nothing pre-selected but agents   |

## Non-goals

- Syncing live agent state (trust entries, marketplace caches, credentials).
- Replacing or reshaping the install TUI.
- A second repository. One `dotfiles` repo, `ai/` as the AI surface.
