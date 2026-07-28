---
name: upgrade-inertia-v3
description: Systematically upgrade an Inertia.js application from v2 to v3, covering every breaking change (Axios/qs/lodash-es removal, `invalid`/`exception` event renames, router.cancelAll, removal of the `future` namespace and progress exports, LazyProp to Inertia::optional, config/inertia.php restructuring, ESM-only packages) across the Laravel adapter and the React, Vue, or Svelte client. Use this skill whenever the user mentions upgrading, migrating, or bumping Inertia to v3, asks what breaks in Inertia 3, asks whether a project can move to @inertiajs/react@3 / vue3@3 / svelte@3, wants an Inertia upgrade audit or viability assessment, or is reviewing a package.json pinning @inertiajs/* at ^2. Use it even for a quick "can this app go to Inertia 3?" question — the assessment steps here are what produce a trustworthy answer.
---

# Inertia v2 to v3 Upgrade Specialist

You are an expert Inertia upgrade specialist with deep knowledge of both Inertia v2 and v3. Your task is to systematically upgrade the application from Inertia v2 to v3 while ensuring all functionality remains intact. You understand the nuances of breaking changes and can identify affected code patterns with precision.

## Core Principle: Documentation-First Approach

Always consult current documentation whenever you need:

- Specific code examples for implementing Inertia v3 features
- Clarification on breaking changes or new syntax
- Verification of upgrade patterns before applying them
- Examples of correct usage for new directives or methods

Use whichever is available, in this order:

1. Laravel Boost MCP `search-docs` tool, if the project has Boost installed
2. `npx ctx7@latest library "inertiajs/inertia" "<question>"` then `npx ctx7@latest docs <libraryId> "<question>"`
3. <https://inertiajs.com/docs/v3/getting-started/upgrade-guide>

The official Inertia documentation is your primary source of truth. Consult it before making assumptions or implementing changes.

## Detect the Stack First

Almost every step below branches on which client adapter the project uses. Determine this before doing anything else:

- Read `package.json` for `@inertiajs/react`, `@inertiajs/vue3`, or `@inertiajs/svelte`
- Read `composer.json` for `inertiajs/inertia-laravel`
- Locate the pages directory (commonly `resources/js/Pages` or `resources/js/pages`; confirm against `resolve()` in the app bootstrap and `config/inertia.php`)
- Note the package manager (`npm` / `pnpm` / `yarn` / `bun`) from the lockfile and substitute it in every `npm install` below

Sections marked **(React)**, **(Vue)**, or **(Svelte)** apply only to that adapter — skip the others.

## Upgrade Process

### 1. Assess Current State

Before making any changes:

- Check `composer.json` for the current `inertiajs/inertia-laravel` version constraint
- Check `package.json` for the current `@inertiajs/*` adapter version
- Run `composer show inertiajs/inertia-laravel` to confirm the installed server version
- Identify all Inertia pages in the pages directory
- Review `config/inertia.php` for current configuration
- Review the Vite and SSR setup if the application server-renders Inertia pages

### 2. Create Safety Net

- Ensure you're working on a dedicated branch
- Run the existing test suite to establish a baseline
- Note any components with complex JavaScript interactions

### 3. Analyze Codebase for Breaking Changes

Search the codebase for patterns affected by v3 changes:

**High Priority Searches:**

- `router.on('invalid'` or `inertia:invalid` — rename to `httpException`
- `router.on('exception'` or `inertia:exception` — rename to `networkError`
- `router.cancel(` — renamed to `router.cancelAll()`
- `defaults: { future` or `future: {` — the `future` namespace has been removed
- `hideProgress(` or `revealProgress(` — use the `progress` object instead
- `Inertia::lazy(` or `LazyProp` — replace with `Inertia::optional()`
- `config/inertia.php` — configuration structure has changed

**Medium Priority Searches:**

- `qs` imports — install `qs` directly if the application uses it
- `lodash-es` imports — install `lodash-es` directly if the application uses it
- `axios` imports or interceptors — decide whether the app keeps Axios or relies on Inertia's built-in HTTP client
- `Inertia\Testing\Concerns\Has`, `Matching`, or `Debugging` — deprecated traits removed in v3
- `require(` in frontend code — Inertia packages are now ESM-only
- **(React)** `import { Deferred }` — React deferred partial reload behavior changed
- **(Svelte)** non-runes Svelte components — update to Svelte 5 runes syntax (`$props()`, `$state()`, `$effect()`, etc.)

**Low Priority Searches:**

- `vite build --ssr` or `inertia:start-ssr` in development scripts — dev SSR flow changed when using `@inertiajs/vite`
- `only`, `except`, `Deferred`, or `WhenVisible` with nested props — dot notation support improved
- `clearHistory` or `encryptHistory` — these page object keys are now omitted unless `true`

### 4. Apply Changes Systematically

For each category of changes:

1. **Search** for affected patterns using grep/search tools
2. **Consult documentation** to verify correct upgrade patterns and examples
3. **List** all files that need modification
4. **Apply** the fix consistently across all occurrences
5. **Verify** each change doesn't break functionality

### 5. Update Dependencies

After code changes are complete:

- `composer require inertiajs/inertia-laravel:^3.0`
- **(React)** `npm install @inertiajs/react@^3.0`
- **(Vue)** `npm install @inertiajs/vue3@^3.0`
- **(Svelte)** `npm install @inertiajs/svelte@^3.0`
- `npm install @inertiajs/vite@^3.0`
- `php artisan vendor:publish --provider="Inertia\\ServiceProvider" --force`
- `php artisan view:clear`

### 6. Test and Verify

- Run the full test suite
- Manually test critical user flows
- Check the browser console for JavaScript errors
- Verify error handling, deferred props, and form submission flows still behave correctly

## Execution Strategy

When upgrading, maximize efficiency by:

- **Batch similar changes** — group all config updates, then all routing updates, etc.
- **Use parallel agents** for independent file modifications
- **Prioritize high-impact changes** that could cause immediate failures
- **Test incrementally** — verify after each category of changes

## Important Notes

- Inertia v3 requires PHP 8.2+, Laravel 11+, and Node 20+
- **(React)** React must be upgraded to 19+
- **(Svelte)** Svelte must be upgraded to 5+ and components updated to Svelte 5 runes syntax
- Axios removal usually does not require code changes
- If the application imports `qs`, install it directly instead of rewriting query handling blindly
- After upgrading, republish the config file and clear cached views, because the `@inertia` Blade directive output changed

---

# Upgrading from v2 to v3

Inertia v3 introduces significant improvements including removal of legacy dependencies, streamlined configuration, and better developer experience. This guide covers all breaking changes and migration steps.

## Requirements

Before upgrading, ensure the environment meets these minimum requirements:

- PHP 8.2+
- Laravel 11+
- Node 20+
- **(React)** React 19+
- **(Svelte)** Svelte 5+ with Svelte 5 runes syntax (`$props()`, `$state()`, `$effect()`, etc.)

## Installation

Update the server-side adapter: `composer require inertiajs/inertia-laravel:^3.0`

Update the client-side adapter:

- **(React)** `npm install @inertiajs/react@^3.0`
- **(Vue)** `npm install @inertiajs/vue3@^3.0`
- **(Svelte)** `npm install @inertiajs/svelte@^3.0`

The optional Vite plugin simplifies page resolution and SSR configuration:

- `npm install @inertiajs/vite@^3.0`

After updating, republish the config and clear caches:

- `php artisan vendor:publish --provider="Inertia\\ServiceProvider" --force`
- `php artisan view:clear`

## High-impact changes

These changes are most likely to affect the application and should be reviewed carefully.

### Axios removed

Inertia v3 no longer ships with or requires Axios. For most applications this requires no changes. The built-in HTTP client still supports interceptors, and applications that use Axios directly may keep it by installing it themselves or by using the Axios adapter.

- `npm install axios`

### `qs` dependency removed

The `qs` package is no longer bundled with `@inertiajs/core`. Inertia still handles its own query strings internally, but install `qs` directly if the application imports it.

- `npm install qs`

### `lodash-es` dependency removed

The `lodash-es` package has been replaced with `es-toolkit` and is no longer included as a dependency of `@inertiajs/core`. Install `lodash-es` directly if the application imports it.

- `npm install lodash-es`

### Event renames

Two global events have been renamed for clarity:

```js
// Before (v2)
router.on('invalid', (event) => {})
router.on('exception', (event) => {})

// After (v3)
router.on('httpException', (event) => {})
router.on('networkError', (event) => {})
```

If document-level event listeners are used, update the event names accordingly (e.g. `document.addEventListener('inertia:httpException', ...)`).

These events can also be handled per-visit using the new `onHttpException` and `onNetworkError` callbacks:

```js
router.post('/users', data, {
    onHttpException: (response) => {
        return false
    },
    onNetworkError: (error) => {},
})
```

Returning `false` from `onHttpException`, or calling `event.preventDefault()` on the global `httpException` event, keeps Inertia from navigating away to its error page.

### `router.cancel()` renamed to `router.cancelAll()`

```js
// Before (v2)
router.cancel()

// After (v3)
router.cancelAll()
router.cancelAll({ async: false, prefetch: false })
```

### Future options removed

The `future` configuration namespace has been removed. The four v2 future options are now always enabled and can no longer be configured:

```js
// Before (v2)
createInertiaApp({
    defaults: {
        future: {
            preserveEqualProps: true,
            useDataInertiaHeadAttribute: true,
            useDialogForErrorModal: true,
            useScriptElementForInitialPage: true,
        },
    },
})

// After (v3)
createInertiaApp({
    // ...
})
```

Initial page data is now always passed through a `<script type="application/json">` element. The old `data-page` attribute approach is no longer supported.

### Progress exports removed

The named exports `hideProgress()` and `revealProgress()` have been removed. For programmatic control, use the adapter's exported `progress` object instead.

```js
// (React)
import { progress } from '@inertiajs/react'
// (Vue)
import { progress } from '@inertiajs/vue3'
// (Svelte)
import { progress } from '@inertiajs/svelte'

progress.hide()
progress.reveal()
```

### `LazyProp` removed

The deprecated `Inertia::lazy()` method and `LazyProp` class have been removed. Use `Inertia::optional()` instead:

```php
// Before (v2)
return Inertia::render('Users/Index', [
    'users' => Inertia::lazy(fn () => User::all()),
]);

// After (v3)
return Inertia::render('Users/Index', [
    'users' => Inertia::optional(fn () => User::all()),
]);
```

## Medium-impact changes

### Config restructuring

The `config/inertia.php` file structure has changed. After upgrading, republish it with `php artisan vendor:publish --provider="Inertia\\ServiceProvider" --force` and then re-apply any customizations on top of the new structure.

```php
// Before (v2) - config/inertia.php
'testing' => [
    'ensure_pages_exist' => true,
    'page_paths' => [resource_path('js/Pages')],
    'page_extensions' => ['js', 'jsx', 'svelte', 'ts', 'tsx', 'vue'],
],

// After (v3) - config/inertia.php
'pages' => [
    'ensure_pages_exist' => false,
    'paths' => [resource_path('js/Pages')],
    'extensions' => ['js', 'jsx', 'svelte', 'ts', 'tsx', 'vue'],
],

'testing' => [
    'ensure_pages_exist' => true,
],
```

### `Deferred` component behavior (React)

The React `<Deferred>` component no longer resets to its fallback during partial reloads. Existing content now stays visible while new data loads, which matches the Vue and Svelte behavior. A `reloading` slot prop is available to show loading state during those partial reloads.

### Form `processing` reset timing

The `useForm` helper now resets `processing` and `progress` inside `onFinish`, not immediately when a response arrives. If code depends on the exact timing of `form.processing`, re-test those flows after upgrading.

### Testing concerns removed

The deprecated `Inertia\Testing\Concerns\Has`, `Matching`, and `Debugging` traits have been removed. They were replaced long ago by `AssertableInertia`, so no action is required unless the application still references those traits directly.

## Other changes

### Blade components

Inertia now provides `<x-inertia::head>` and `<x-inertia::app>` Blade components as an alternative to the `@inertiaHead` and `@inertia` directives. The head component accepts fallback content via its slot that only renders when SSR is not active, solving the long-standing issue of duplicate `<title>` tags in SSR applications. The existing directives continue to work and require no changes.

### ES2022 build target

Inertia packages now target ES2022, up from ES2020 in v2. Use the `@vitejs/plugin-legacy` Vite plugin if the application needs to support older browsers.

### Optional Vite plugin

The new `@inertiajs/vite` plugin can simplify component resolution and SSR configuration. If adopting it, review the official examples before changing the `createInertiaApp()` bootstrap.

### SSR in development

When using `@inertiajs/vite`, SSR now works in development by simply running the normal Vite dev server. `vite build --ssr` and `php artisan inertia:start-ssr` are no longer needed during development.

### Middleware priority

The Inertia middleware is now automatically registered at the correct priority, so no manual middleware-priority customization is required.

### Nested prop types

Nested `Inertia::optional()`, `Inertia::defer()`, and `Inertia::merge()` values now resolve correctly inside closures and nested arrays. On the client side, `only`, `except`, `Deferred`, and `WhenVisible` support dot-notation paths for nested props.

```php
return Inertia::render('Dashboard', [
    'auth' => fn () => [
        'user' => Auth::user(),
        'notifications' => Inertia::defer(fn () => Auth::user()->unreadNotifications),
        'invoices' => Inertia::optional(fn () => Auth::user()->invoices),
    ],
]);
```

### ESM-only

All Inertia packages are now ESM-only. Replace any CommonJS `require()` imports with `import` statements.

### Page object changes

The `clearHistory` and `encryptHistory` keys are now omitted from the page object unless they are `true`. If raw page payloads are inspected in custom integrations or tests, update those expectations.

## Next steps: New features in v3

After completing the upgrade, the following new features are available. Do **not** refactor existing code to adopt these features as part of the upgrade. Just complete the breaking changes above. These are listed as next steps to explore separately.

- **Standalone HTTP requests (`useHttp`)** — make HTTP requests without triggering page visits. Supports reactive state, error handling, file upload progress, request cancellation, optimistic updates, and precognition.
- **Optimistic updates** — chain `router.optimistic()` before a visit to apply changes instantly on the client. Props revert automatically on failure. Works with router visits, `<Form>`, `useForm`, and `useHttp`.
- **Instant visits** — swap to the target page component immediately via `<Link href="/dashboard" component="Dashboard">` while the server request fires in the background.
- **Layout props (`setLayoutProps`)** — persistent layouts can declare defaults that pages override via `setLayoutProps()`. Supports named layouts, nested layouts, and static props.
- **Exception handling (`handleExceptionsUsing`)** — full control over error page rendering with access to shared data via `withSharedData()`.
- **Default layout** — set a default layout in `createInertiaApp()` instead of on every page.
- **Form component generics** — TypeScript generics for type-safe errors and slot props.
- **Enum support** — use PHP enums directly in `Inertia::render()` responses.
- **`preserveErrors` option** — preserve validation errors during partial reloads.
- **Deferred `reloading` prop** — show loading indicators during partial reloads across all adapters.

Consult the documentation for implementation details when ready to adopt any of these.

## Getting help

If issues come up during the upgrade:

- Check the [upgrade guide](https://inertiajs.com/docs/v3/getting-started/upgrade-guide) for the latest details
- Visit the [GitHub discussions](https://github.com/inertiajs/inertia/discussions) for community support

---

*Adapted from the Laravel Boost MCP prompt `UpgradeInertiav3/upgrade-inertia-v3.blade.php` (laravel/boost, main branch). Blade directives were resolved into plain Markdown; `@if($usesReact/$usesVue/$usesSvelte)` branches became **(React)** / **(Vue)** / **(Svelte)** markers, and the Boost `search-docs` tool reference was generalized to whichever docs tool is available.*
