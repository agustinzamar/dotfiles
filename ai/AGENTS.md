<!-- context7 -->
Use Context7 MCP to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service — even well-known ones like React, Next.js, Prisma, Express, Tailwind, Django, or Spring Boot. This includes API syntax, configuration, version migration, library-specific debugging, setup instructions, and CLI tool usage. Use even when you think you know the answer — your training data may not reflect recent changes. Prefer this over web search for library docs.

Do not use for: refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

## Steps

1. Always start with `resolve-library-id` using the library name and what to look up in the library's documentation, unless the user provides an exact library ID in `/org/project` format
2. Pick the best match (ID format: `/org/project`) by: exact name match, description relevance, code snippet count, source reputation (High/Medium preferred), and benchmark score (higher is better). If results don't look right, try alternate names or queries (e.g., "next.js" not "nextjs", or rephrase the question). Use version-specific IDs when the user mentions a version
3. `query-docs` with the selected library ID and what to look up in the library's documentation (not single words), scoped to a single concept. If the question spans multiple distinct concepts (e.g. routing and auth and caching), make a separate `query-docs` call per concept with the same library ID, unless the question is about how the concepts interact — combined queries dilute ranking and return shallow results for each topic
4. Answer using the fetched docs
<!-- context7 -->

## Personal rules

Read `~/.agents/rules/*.md` before you start work in any repository. The folder links to `~/dotfiles/ai/rules`.

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

<!-- laravel-boost-begin -->
## Laravel Boost Enforcement

On every new session in a Laravel project, run the following checks and suggestions:

### 1. Detect Laravel project

This is a Laravel project if any of these are true:
- `artisan` file exists at project root
- `composer.json` contains `laravel/framework` in `require` or `require-dev`

### 2. Check if Laravel Boost is installed

Boost is considered installed if any of these are true:
- `laravel/boost` appears in `composer.json` under `require-dev`
- `config/boost.php` file exists
- `vendor/laravel/boost` directory exists
- `Laravel\Boost\BoostServiceProvider` is registered in `composer.json` under `extra.laravel.providers`

### 3. If Boost is NOT installed

- Suggest installing `laravel/boost` in dev mode:
  ```bash
  composer require laravel/boost --dev
  ```
- Then run the installer in non-interactive mode (Boost uses defaults when input is piped or `--no-interaction` is passed):
  ```bash
  php artisan boost:install --no-interaction
  ```
- After installation, verify the Boost features are configured and add the composer `post-update-cmd` script for automatic updates (see step 5).

### 4. If Boost IS installed but last update was more than a week ago

- Check last update time via:
  ```bash
  git log -1 --format="%ct" -- .ai/
  ```
  Or check the modification time of files in `.ai/agents/` or `config/boost.php`.
- If the last update timestamp is older than 7 days, suggest:
  ```bash
  php artisan boost:update --discover
  ```
  > Note: `boost:update` discovers new content by default. Passing `--no-discover` disables discovery. Since discovery is the default, `--discover` can be omitted if desired, but include it as specified.

### 5. Ensure automatic updates via composer scripts

Ensure `composer.json` contains a `post-update-cmd` script that runs `boost:update`:

```json
{
  "scripts": {
    "post-update-cmd": [
      "@php artisan boost:update --ansi"
    ]
  }
}
```

- If the script entry is missing, add it.
- If the script entry exists but does not include `@php artisan boost:update --ansi`, update it to include this line.
- If running `boost:update --ansi` interactively prompts, use `--no-interaction` flag instead.

### Summary flow for the agent

1. On session start in a Laravel project, check if Boost is installed.
2. If not installed → suggest installation and offer to run the two install commands.
3. If installed but stale (>7 days) → suggest `php artisan boost:update --discover`.
4. Always ensure the `post-update-cmd` composer script includes `@php artisan boost:update --ansi`.
<!-- laravel-boost-end -->

## Communication Style

- Write in **ASD-STE100 Simplified Technical English**: one idea per sentence, active voice, present tense, approved words only, max ~20 words per sentence. No idioms, no synonyms for the same concept — reuse the same word.
- Present information in **tables** whenever the content has 2+ items with shared attributes (options, files, tradeoffs, steps, results). Prose only when a table does not fit.
- Use **emojis** as visual anchors: ✅ done / ❌ failed / ⚠️ warning / 📁 file / 🔧 command / 💡 note. One per line at most. Do not decorate.
- Exception: code stays in normal technical English. Commits and PR bodies use ASD-STE100 English. All three use no emojis.

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

| File | Change |
| --- | --- |
| `path/to/file.php` | <What changed in this file.> |

## Testing

| Check | Result |
| --- | --- |
| <Test command or suite> | <Result.> |

## Notes

<Optional. List known limits, follow-up work, or decisions the reviewer must know. Remove this section if it is empty.>
```

Keep the same section order. Remove a section only when it has no content.
