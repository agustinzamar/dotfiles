<!-- dot:section git-commits-and-pull-requests -->

## Git Commits and Pull Requests

Write all commit messages and PR bodies in ASD-STE100 Simplified Technical English. Use no emojis.

### Title format

Use `<TICKET-KEY>: <Short descriptive title>` for the PR title and the commit subject.

- The ticket key comes from the Jira issue, for example `PF-24`.
- The title says what the change does. Use max 10 words.
- Do not use a Conventional Commit prefix such as `feat:` or `fix:`.
- Example: `PF-24: Match animals by physical tag first on import`

### PR description template

```markdown
## Summary

<One or two sentences. State what the change does and why.>

## Changes

| File               | Change                       |
| ------------------ | ---------------------------- |
| `path/to/file.php` | <What changed in this file.> |

## Testing

| Check                   | Result    |
| ----------------------- | --------- |
| <Test command or suite> | <Result.> |

## Notes

<Optional. List known limits, follow-up work, or decisions the reviewer must know. Remove this section if it is empty.>
```

Keep the same section order. Remove a section only when it has no content.

<!-- /dot:section -->

<!-- dot:section subagent-model-selection -->

## Subagent Model Selection

Prefer a free model for every subagent delegation to reduce cost.

### How to find a free model

List available models and filter for free tiers:

```bash
opencode models | grep free
```

The `opencode` provider exposes free models. List them all with:

```bash
opencode models | grep opencode
```

If neither command works, consult the OpenCode provider documentation or the active provider list in your environment to identify free-tier models.

### Rules

- Use a free model for subagents unless the user asks for a specific paid provider.
- If no free model is available, use one from OpenCode Go.
- Do not use `anthropic` or `openai` providers unless the user explicitly asks for them.

<!-- /dot:section -->

<!-- dot:section communication-style -->

## Communication Style

- Write in **ASD-STE100 Simplified Technical English**: one idea per sentence, active voice, present tense, approved words only, max ~20 words per sentence. No idioms, no synonyms for the same concept — reuse the same word.
- Present information in **tables** whenever the content has 2+ items with shared attributes (options, files, tradeoffs, steps, results). Prose only when a table does not fit.
- Use **emojis** as visual anchors: ✅ done / ❌ failed / ⚠️ warning / 📁 file / 🔧 command / 💡 note. One per line at most. Do not decorate.
- Exception: code stays in normal technical English. Commits and PR bodies use ASD-STE100 English. All three use no emojis.

<!-- /dot:section -->
