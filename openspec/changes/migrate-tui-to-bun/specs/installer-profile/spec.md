# Installer Profile Specification

## Purpose

Define how the installer persists a user's component selection as
`{ "components": { "<id>": <bool> } }`, including defaults, validation, atomic writes,
and migration of profiles written by older versions that used legacy aggregate IDs.
These contracts MUST hold so profiles saved by the previous Go implementation load
identically under the TypeScript implementation.

## Requirements

### Requirement: Default Profile Derivation

The default profile MUST enable every component whose manifest entry has
`default: true` or `required: true`, and disable every other component. The resulting
map SHALL contain an entry for all 31 component ids.

#### Scenario: Defaults match manifest

- GIVEN a fresh in-memory profile with no file on disk
- WHEN the default profile is built from the catalog
- THEN `base`, `shell`, `git`, and `terminal` are true (default and/or required)
- AND every other component id is present with value false

### Requirement: Load Missing File Returns Defaults

Loading a profile from a path where no file exists MUST succeed and return the default
profile; it MUST NOT be treated as an error.

#### Scenario: Missing profile file falls back to defaults

- GIVEN a path that does not exist on disk
- WHEN the profile is loaded from that path
- THEN the operation succeeds
- AND the returned profile equals the default profile derived from the manifest

### Requirement: Profile Validation On Save

Saving a profile MUST reject any unknown component id and any disabled required
component, failing without writing the file.

#### Scenario: Unknown ID rejected on save

- GIVEN a profile map containing an id not present in the catalog
- WHEN the profile is saved
- THEN the save fails with an error naming the unknown component
- AND no file is created at the target path

#### Scenario: Disabled required component rejected on save

- GIVEN a profile map where `base` is false
- WHEN the profile is saved
- THEN the save fails reporting that required component `base` is disabled

### Requirement: Load Normalization

After parsing a profile file, loading MUST: reject unknown component ids with an
error; fill any missing component ids with `false`; then force every required
component to `true`. A file whose JSON lacks a `components` object MUST be rejected.

#### Scenario: Unknown ID in file rejected on load

- GIVEN a profile file containing `"components": {"not-a-component": true}`
- WHEN the profile is loaded
- THEN loading fails with an error identifying `not-a-component`

#### Scenario: Missing IDs filled as false and required forced true

- GIVEN a valid profile file containing only `"components": {"ai": true}`
- WHEN the profile is loaded
- THEN `ai` is true, every absent id is filled as false
- AND `base`, `shell`, `git`, and `terminal` are true regardless of file contents
- AND no error is returned

#### Scenario: Malformed JSON rejected

- GIVEN a file containing invalid JSON, or valid JSON without a `components` object
- WHEN the profile is loaded
- THEN loading fails with an "invalid profile" style error

### Requirement: Atomic Save With Trailing Newline

Saving MUST serialize the profile as indented JSON, write it first to a temporary file
in the target directory, and then rename that temporary file onto the target path. The
written content MUST end with exactly one trailing newline. The save SHOULD create the
target directory when missing.

#### Scenario: Save round-trips through tmp-and-rename

- GIVEN a valid profile and a target path inside a writable directory
- WHEN the profile is saved and loaded back
- THEN the loaded profile matches the saved selection after normalization
- AND the file bytes end with a single `\n`
- AND no temporary files remain in the directory after the save completes

### Requirement: Legacy Aggregate Migration

Profiles may contain legacy aggregate keys `communication`, `desktop`, `media`,
and `databases`. When migrating: each enabled aggregate key MUST expand its exact child
id list to `true`; a disabled (`false`) aggregate key MUST NOT enable any children;
each processed aggregate key MUST be removed from the map. The exact child lists MUST be:

| Aggregate | Child IDs |
| --- | --- |
| `communication` | communication-discord, communication-telegram, communication-whatsapp, communication-slack |
| `desktop` | desktop-chrome, desktop-firefox, desktop-brave, communication-discord, communication-telegram, communication-whatsapp, communication-slack, desktop-raycast, desktop-finetune, desktop-typewhisper, desktop-rectangle, desktop-aerospace, desktop-linearmouse, desktop-localsend |
| `media` | media-tools, media-spotify, media-stremio, media-vlc, media-castor |
| `databases` | service-mysql, service-postgresql, service-redis, service-sqlite |

Migration of pure data (before normalization) MUST report whether any change occurred.

#### Scenario: Enabled aggregate expands to exact children

- GIVEN a profile with `"communication": true` and no other entries
- WHEN migration runs
- THEN exactly the four communication child ids become true
- AND the `communication` key is removed
- AND migration reports that a change occurred

#### Scenario: Desktop aggregate includes communication children

- GIVEN a profile with `"desktop": true`
- WHEN migration runs
- THEN both the ten desktop child ids and the four communication child ids are true
- AND the `desktop` key is removed

#### Scenario: Disabled aggregate enables nothing but still removed

- GIVEN a profile with `"databases": false`
- WHEN migration runs
- THEN none of `service-mysql`, `service-postgresql`, `service-redis`,
  `service-sqlite` is enabled by the aggregate
- AND the `databases` key is removed
- AND migration reports that a change occurred

### Requirement: Migration Idempotency

Running migration on an already-migrated profile (no aggregate keys present) MUST make
no changes and MUST report that no change occurred.

#### Scenario: Second migration run is a no-op

- GIVEN a profile that has already had its aggregate keys migrated away
- WHEN migration runs again
- THEN the component map is unchanged
- AND migration reports that no change occurred

### Requirement: Load Persists Migrated Data

When loading a profile required migration, the loader MUST write the migrated,
normalized profile back to the same path before returning. Loading an already-migrated
profile SHOULD NOT rewrite the file.

#### Scenario: Migrated profile is saved back on load

- GIVEN a profile file on disk containing a legacy aggregate key set to true
- WHEN the profile is loaded successfully
- THEN the file on disk no longer contains the aggregate key
- AND reloading the file yields an identical normalized profile

#### Scenario: Unmigrated profile file is left untouched

- GIVEN a profile file on disk with no legacy aggregate keys
- WHEN the profile is loaded successfully
- THEN the file modification time/content is unchanged by the load
