# Installer Manifest Specification

## Purpose

Define the normative component catalog that the TypeScript installer MUST expose after
the Go removal. The catalog drives profile validation, planning, and the TUI; its exact
shape is the compatibility contract between saved profiles created by any prior version
and the new implementation.

## Requirements

### Requirement: Component Catalog Shape

The system SHALL expose exactly one component catalog where every component has an `id`,
`label`, `category`, `default`, and `required` field, and MAY have `dependencies`,
`links`, and `commands` lists. The catalog MUST contain exactly 31 components.

#### Scenario: Catalog size and required fields are stable

- GIVEN the component catalog module
- WHEN the catalog list is read
- THEN it contains exactly 31 entries
- AND every entry has a non-empty string `id`, a non-empty string `label`,
  a non-empty string `category`, and boolean `default` and `required` fields

### Requirement: Unique Component IDs

The system MUST guarantee that no two components share the same `id`.

#### Scenario: No duplicate IDs

- GIVEN the component catalog
- WHEN all `id` values are collected into a set
- THEN the set size equals the number of catalog entries (31)

### Requirement: Required Baseline Components

The components `base`, `shell`, `git`, and `terminal` MUST be marked `required: true`.
The components `base`, `shell`, `git`, and `terminal` SHOULD also be marked
`default: true`.

#### Scenario: Baseline components cannot be deselected downstream

- GIVEN the component catalog
- WHEN each of `base`, `shell`, `git`, and `terminal` is inspected
- THEN its `required` flag is true
- AND profile loading forces it enabled regardless of persisted state

### Requirement: No Legacy Aggregate IDs

The catalog MUST NOT contain any component with id `communication`, `desktop`,
`media`, or `databases`; those ids exist only as legacy migration inputs in saved
profiles.

#### Scenario: Aggregates absent from catalog

- GIVEN the component catalog
- WHEN the set of ids is examined for `communication`, `desktop`, `media`, `databases`
- THEN none of those ids is present

### Requirement: Git Tooling Commands

The `git` component MUST include `hunk` in both its link paths and its install commands,
so that selecting git installs and links the Hunk tool.

#### Scenario: Git component covers Hunk

- GIVEN the `git` component definition
- WHEN its `links` and `commands` are inspected
- THEN some link path equals `hunk`
- AND some command contains `brew install` and includes `hunk`

### Requirement: PHP Installs Through Herd

The `php` component MUST NOT invoke `brew install php`; it SHALL provision PHP through
Herd (`composer` + `Herd` cask) plus the PhpStorm cask instead.

#### Scenario: PHP component uses Herd

- GIVEN the `php` component definition
- WHEN its `commands` are inspected
- THEN no command installs the formula `php` directly
- AND at least one command installs `composer` together with `Herd`
- AND at least one command installs the `phpstorm` cask
