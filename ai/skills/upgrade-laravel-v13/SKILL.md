---
name: upgrade-laravel-v13
description: Systematically upgrade a Laravel application from 12.x to 13.0, covering every documented breaking change (CSRF middleware rename to PreventRequestForgery, cache serializable_classes hardening, upsert uniqueBy validation, queue event property renames, container nullable defaults, pagination view names, and more). Use this skill whenever the user mentions upgrading, migrating, or bumping Laravel to 13, asks whether a project is ready for Laravel 13, asks what breaks in Laravel 13, wants a Laravel 13 upgrade audit or viability assessment, or is reviewing a composer.json that pins laravel/framework ^12. Use it even for a quick "can this app go to 13?" question — the assessment steps here are what produce a trustworthy answer.
---

# Laravel 12 to 13 Upgrade Specialist

You are an expert Laravel upgrade specialist with deep knowledge of both Laravel 12.x and 13.0. Your task is to systematically upgrade the application from Laravel 12 to 13 while ensuring all functionality remains intact. You understand the nuances of breaking changes and can identify affected code patterns with precision.

## Core Principle: Documentation-First Approach

Always consult current documentation whenever you need:

- Specific code examples for implementing Laravel 13 features
- Clarification on breaking changes or new behavior
- Verification of upgrade patterns before applying them
- Examples of correct usage for renamed classes or methods

Use whichever is available, in this order:

1. Laravel Boost MCP `search-docs` tool, if the project has Boost installed
2. `npx ctx7@latest library "laravel/framework" "<question>"` then `npx ctx7@latest docs <libraryId> "<question>"`
3. <https://laravel.com/docs/13.x/upgrade>

The official Laravel documentation is your primary source of truth. Consult it before making assumptions or implementing changes.

## Adapting Commands to the Project

Before running anything, detect the project's tooling and substitute accordingly:

- **Composer**: normally `composer`. If the project pins a PHP version (multiple `php8x` binaries on the box, a `platform.php` entry in `composer.json`), run it as `php8.x "$(command -v composer)" ...` so the right interpreter resolves the platform requirements.
- **Artisan**: `php artisan ...`, or `sail artisan ...` / `herd php artisan ...` when the project uses Sail or Herd.
- **Herd**: check with `herd --version`. It changes how the Laravel installer is updated (see below).

## Upgrade Process

### 1. Assess Current State

Before making any changes:

- Check `composer.json` for the current Laravel version constraint
- Run `composer show laravel/framework` to confirm the installed version
- Identify middleware references to `VerifyCsrfToken` or `ValidateCsrfToken`
- Review `config/cache.php` for serialization settings
- Review `config/session.php` for cookie name configuration

### 2. Create Safety Net

- Ensure you're working on a dedicated branch
- Run the existing test suite to establish a baseline
- Note any custom cache store implementations or queue driver implementations

### 3. Analyze Codebase for Breaking Changes

Search the codebase for patterns affected by v13 changes:

**High Priority Searches:**

- `VerifyCsrfToken` or `ValidateCsrfToken` — must rename to `PreventRequestForgery`
- `composer.json` — dependency version constraints to update
- `phpunit.xml` or Pest config — test framework version compatibility

**Medium Priority Searches:**

- `config/cache.php` — check for `serializable_classes` configuration
- Code that stores PHP objects in cache — may need explicit class allow-lists
- `upsert` calls with empty `uniqueBy` — now throws `InvalidArgumentException`

**Low Priority Searches:**

- `$event->exceptionOccurred` — renamed to `$event->exception` in `JobAttempted`
- `$event->connection` on `QueueBusy` — renamed to `$connectionName`
- `pagination::default` or `pagination::simple-default` — view names changed
- `Container::call` with nullable class defaults — behavior changed
- Manager `extend` callbacks using `$this` — binding changed
- Custom `Str` factories in tests — now reset between tests

### 4. Apply Changes Systematically

For each category of changes:

1. **Search** for affected patterns using grep/search tools
2. **Consult documentation** to verify correct upgrade patterns and examples
3. **List** all files that need modification
4. **Apply** the fix consistently across all occurrences
5. **Verify** each change doesn't break functionality

### 5. Update Dependencies

After code changes are complete:

```bash
composer require laravel/framework:^13.0 --with-all-dependencies
```

### 6. Test and Verify

- Run the full test suite
- Verify CSRF protection still works correctly
- Check cache read/write operations
- Test any queue listeners that reference event properties

## Execution Strategy

When upgrading, maximize efficiency by:

- **Batch similar changes** — group all CSRF middleware renames, then all config updates, etc.
- **Use parallel agents** for independent file modifications
- **Prioritize high-impact changes** that could cause immediate failures
- **Test incrementally** — verify after each category of changes

---

# Upgrading from Laravel 12.x to 13.0

> [!NOTE]
> Every possible breaking change is documented below. Since some of these are in obscure parts of the framework, only a portion may actually affect the application.

## Updating Dependencies

**Likelihood Of Impact: High**

Update the following dependencies in the application's `composer.json`:

```json
{
    "require": {
        "laravel/framework": "^13.0"
    },
    "require-dev": {
        "laravel/tinker": "^3.0",
        "phpunit/phpunit": "^12.0",
        "pestphp/pest": "^4.0"
    }
}
```

Run the update:

```bash
composer update
```

## Updating the Laravel Installer

If the Laravel installer CLI tool is used, update it for Laravel 13.x compatibility:

- With Herd: `herd laravel:update`
- Otherwise: `composer global update laravel/installer`

## Cache

### Cache Prefixes and Session Cookie Names

**Likelihood Of Impact: Low**

Laravel's default cache and Redis key prefixes now use hyphenated suffixes. In addition, the default session cookie name now uses `Str::snake(...)` for the application name.

In most applications this change will not apply, because application-level configuration files already define these values. This primarily affects applications that rely on framework-level fallback configuration when the corresponding application config values are not present.

If the application relies on these generated defaults, cache keys and session cookie names may change after upgrading:

```php
// Laravel <= 12.x
Str::slug((string) env('APP_NAME', 'laravel'), '_').'_cache_';
Str::slug((string) env('APP_NAME', 'laravel'), '_').'_database_';
Str::slug((string) env('APP_NAME', 'laravel'), '_').'_session';

// Laravel >= 13.x
Str::slug((string) env('APP_NAME', 'laravel')).'-cache-';
Str::slug((string) env('APP_NAME', 'laravel')).'-database-';
Str::snake((string) env('APP_NAME', 'laravel')).'_session';
```

> [!IMPORTANT]
> To retain previous behavior, explicitly configure `CACHE_PREFIX`, `REDIS_PREFIX`, and `SESSION_COOKIE` in the environment.

### `Store` and `Repository` Contracts: `touch`

**Likelihood Of Impact: Very Low**

The cache contracts now include a `touch` method for extending item TTLs. Custom cache store implementations should add this method:

```php
// Illuminate\Contracts\Cache\Store
public function touch($key, $seconds);
```

### Cache `serializable_classes` Configuration

**Likelihood Of Impact: Medium**

The default application `cache` configuration now includes a `serializable_classes` option set to `false`. This hardens cache unserialization behavior to help prevent PHP deserialization gadget chain attacks if the application's `APP_KEY` is leaked. If the application intentionally stores PHP objects in cache, explicitly list the classes that may be unserialized:

```php
'serializable_classes' => [
    App\Data\CachedDashboardStats::class,
    App\Support\CachedPricingSnapshot::class,
],
```

If the application previously relied on unserializing arbitrary cached objects, migrate that usage to explicit class allow-lists or to non-object cache payloads (such as arrays).

## Container

### `Container::call` and Nullable Class Defaults

**Likelihood Of Impact: Low**

`Container::call` now respects nullable class parameter defaults when no binding exists, matching the constructor injection behavior introduced in Laravel 12:

```php
$container->call(function (?Carbon $date = null) {
    return $date;
});

// Laravel <= 12.x: Carbon instance
// Laravel >= 13.x: null
```

If method-call injection logic depended on the previous behavior, update it.

## Contracts

### `Dispatcher` Contract: `dispatchAfterResponse`

**Likelihood Of Impact: Very Low**

The `Illuminate\Contracts\Bus\Dispatcher` contract now includes `dispatchAfterResponse($command, $handler = null)`. Custom dispatcher implementations must add this method.

### `ResponseFactory` Contract: `eventStream`

**Likelihood Of Impact: Very Low**

The `Illuminate\Contracts\Routing\ResponseFactory` contract now includes an `eventStream` signature. Custom implementations must add this method.

### `MustVerifyEmail` Contract: `markEmailAsUnverified`

**Likelihood Of Impact: Very Low**

The `Illuminate\Contracts\Auth\MustVerifyEmail` contract now includes `markEmailAsUnverified()`. Custom implementations must add this method to remain compatible.

## Database

### Database `upsert` With MySQL or MariaDB

**Likelihood Of Impact: Medium**

Laravel now validates that the caller provides a non-empty value for `uniqueBy`, and throws an `InvalidArgumentException` instead of generating invalid SQL.

Although the MariaDB and MySQL drivers ignore the `uniqueBy` value and always use the table's primary and unique indexes to detect existing records, the validation still applies. An `InvalidArgumentException` is thrown if `uniqueBy` is empty.

### MySQL `DELETE` Queries With `JOIN`, `ORDER BY`, and `LIMIT`

**Likelihood Of Impact: Low**

Laravel now compiles full `DELETE ... JOIN` queries including `ORDER BY` and `LIMIT` for the MySQL grammar.

In previous versions, `ORDER BY` / `LIMIT` clauses could be silently ignored on joined deletes. In Laravel 13 these clauses are included in the generated SQL. As a result, database engines that do not support this syntax (such as standard MySQL / MariaDB variants) may now throw a `QueryException` instead of executing an unbounded delete.

## Eloquent

### Model Booting and Nested Instantiation

**Likelihood Of Impact: Very Low**

Creating a new model instance while that model is still booting is now disallowed and throws a `LogicException`. This affects code that instantiates models from inside model `boot` methods or trait `boot*` methods:

```php
protected static function boot()
{
    parent::boot();

    // No longer allowed during booting...
    (new static())->getTable();
}
```

Move this logic outside the boot cycle to avoid nested booting.

### Polymorphic Pivot Table Name Generation

**Likelihood Of Impact: Low**

When table names are inferred for polymorphic pivot models using custom pivot model classes, Laravel now generates pluralized names.

If the application depended on the previous singular inferred names for morph pivot tables and used custom pivot classes, explicitly define the table name on the pivot model.

### Collection Model Serialization Restores Eager-Loaded Relations

**Likelihood Of Impact: Low**

When Eloquent model collections are serialized and restored (such as in queued jobs), eager-loaded relations are now restored for the collection's models.

If code depended on relations not being present after deserialization, adjust that logic.

## HTTP Client

### `Response::throw` and `throwIf` Signatures

**Likelihood Of Impact: Very Low**

The HTTP client response methods now declare their callback parameters in the method signatures:

```php
public function throw($callback = null);
public function throwIf($condition, $callback = null);
```

If these methods are overridden in custom response classes, ensure the signatures are compatible.

## Notifications

### Default Password Reset Subject

**Likelihood Of Impact: Very Low**

Laravel's default password reset mail subject has changed:

```text
// Laravel <= 12.x
Reset Password Notification

// Laravel >= 13.x
Reset your password
```

If tests, assertions, or translation overrides depend on the previous default string, update them.

### Queued Notifications and Missing Models

**Likelihood Of Impact: Very Low**

Queued notifications now respect the `#[DeleteWhenMissingModels]` attribute and `$deleteWhenMissingModels` property defined on the notification class.

In previous versions, missing models could still cause queued notification jobs to fail in cases where deletion was expected.

## Queue

### `JobAttempted` Event Exception Payload

**Likelihood Of Impact: Low**

The `Illuminate\Queue\Events\JobAttempted` event now exposes the exception object (or `null`) via `$exception`, replacing the previous boolean `$exceptionOccurred` property:

```php
// Laravel <= 12.x
$event->exceptionOccurred;

// Laravel >= 13.x
$event->exception;
```

Update listeners for this event accordingly.

### `QueueBusy` Event Property Rename

**Likelihood Of Impact: Low**

The `Illuminate\Queue\Events\QueueBusy` event property `$connection` has been renamed to `$connectionName` for consistency with other queue events.

### `Queue` Contract Method Additions

**Likelihood Of Impact: Very Low**

The `Illuminate\Contracts\Queue\Queue` contract now includes queue size inspection methods that were previously only declared in docblocks. Custom queue driver implementations must add:

- `pendingSize`
- `delayedSize`
- `reservedSize`
- `creationTimeOfOldestPendingJob`

## Routing

### Domain Route Registration Precedence

**Likelihood Of Impact: Low**

Routes with an explicit domain are now prioritized before non-domain routes in route matching.

This allows catch-all subdomain routes to behave consistently even when non-domain routes are registered earlier. If the application relied on the previous registration precedence between domain and non-domain routes, review route matching behavior.

## Scheduling

### `withScheduling` Registration Timing

**Likelihood Of Impact: Very Low**

Schedules registered via `ApplicationBuilder::withScheduling()` are now deferred until `Schedule` is resolved. If the application relied on immediate schedule registration timing during bootstrap, adjust that logic.

## Security

### Request Forgery Protection

**Likelihood Of Impact: High**

Laravel's CSRF middleware has been renamed from `VerifyCsrfToken` to `PreventRequestForgery`, and now includes request-origin verification using the `Sec-Fetch-Site` header.

`VerifyCsrfToken` and `ValidateCsrfToken` remain as deprecated aliases, but direct references should be updated to `PreventRequestForgery`, especially when excluding middleware in tests or route definitions:

```php
use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Foundation\Http\Middleware\VerifyCsrfToken;

// Laravel <= 12.x
->withoutMiddleware([VerifyCsrfToken::class]);

// Laravel >= 13.x
->withoutMiddleware([PreventRequestForgery::class]);
```

The middleware configuration API now also provides `preventRequestForgery(...)`.

## Support

### Manager `extend` Callback Binding

**Likelihood Of Impact: Low**

Custom driver closures registered via manager `extend` methods are now bound to the manager instance.

If another bound object (such as a service provider instance) was previously relied on as `$this` inside these callbacks, move those values into closure captures using `use (...)`.

### `Str` Factories Reset Between Tests

**Likelihood Of Impact: Low**

Laravel now resets custom `Str` factories during test teardown.

If tests depended on custom UUID / ULID / random string factories persisting between test methods, set them in each relevant test or setup hook.

### `Js::from` Uses Unescaped Unicode By Default

**Likelihood Of Impact: Very Low**

`Illuminate\Support\Js::from` now uses `JSON_UNESCAPED_UNICODE` by default. If tests or frontend output comparisons depended on escaped Unicode sequences (for example `è`), update those expectations.

## Views

### Pagination Bootstrap View Names

**Likelihood Of Impact: Low**

The internal pagination view names for Bootstrap 3 defaults are now explicit:

```text
// Laravel <= 12.x
pagination::default
pagination::simple-default

// Laravel >= 13.x
pagination::bootstrap-3
pagination::simple-bootstrap-3
```

## Getting help

If issues come up during the upgrade:

- Check the [upgrade guide](https://laravel.com/docs/13.x/upgrade) for the latest details
- Review the [GitHub comparison](https://github.com/laravel/laravel/compare/12.x...13.x) for skeleton changes

---

*Adapted from the Laravel Boost MCP prompt `UpgradeLaravelv13/upgrade-laravel-v13.blade.php` (laravel/boost, main branch). Blade directives were resolved into plain Markdown; the Boost `search-docs` tool reference was generalized to whichever docs tool is available.*
