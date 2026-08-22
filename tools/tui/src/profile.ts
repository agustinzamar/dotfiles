import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import * as path from "node:path";
import { COMPONENTS } from "./manifest";

export interface Profile {
  components: Record<string, boolean>;
}

// Copied verbatim from internal/installer/profile.go (legacyComponentIDs).
// The desktop aggregate deliberately includes the communication children.
const legacyComponentIDs: Record<string, string[]> = {
  communication: [
    "communication-discord",
    "communication-telegram",
    "communication-whatsapp",
    "communication-slack",
  ],
  desktop: [
    "desktop-chrome",
    "desktop-firefox",
    "desktop-brave",
    "communication-discord",
    "communication-telegram",
    "communication-whatsapp",
    "communication-slack",
    "desktop-raycast",
    "desktop-finetune",
    "desktop-typewhisper",
    "desktop-rectangle",
    "desktop-aerospace",
    "desktop-linearmouse",
    "desktop-localsend",
  ],
  media: [
    "media-tools",
    "media-spotify",
    "media-stremio",
    "media-vlc",
    "media-castor",
  ],
  databases: [
    "service-mysql",
    "service-postgresql",
    "service-redis",
    "service-sqlite",
  ],
};

const catalogIds = new Set(COMPONENTS.map((c) => c.id));

function requireComponentsObject(value: unknown): asserts value is Profile {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    !(value as Profile).components ||
    typeof (value as Profile).components !== "object" ||
    Array.isArray((value as Profile).components)
  ) {
    throw new Error("invalid profile: components is required");
  }
}

// Port of Go's LoadProfileData: hand-rolled validation, no zod (ADR-7).
function validateProfile(profile: Profile): void {
  for (const id of Object.keys(profile.components)) {
    if (!catalogIds.has(id)) {
      throw new Error(`invalid profile: unknown component "${id}"`);
    }
  }
  for (const component of COMPONENTS) {
    if (component.required && !profile.components[component.id]) {
      throw new Error(
        `invalid profile: required component "${component.id}" is disabled`,
      );
    }
  }
}

export function defaultProfile(): Profile {
  const components: Record<string, boolean> = {};
  for (const component of COMPONENTS) {
    components[component.id] = component.default || component.required;
  }
  return { components };
}

export function migrateProfileData(profile: Profile): {
  profile: Profile;
  changed: boolean;
} {
  requireComponentsObject(profile);
  const out = { ...profile.components };
  let changed = false;
  for (const [legacyId, childIds] of Object.entries(legacyComponentIDs)) {
    if (!Object.hasOwn(out, legacyId)) {
      continue;
    }
    if (out[legacyId]) {
      for (const childId of childIds) {
        out[childId] = true;
      }
    }
    delete out[legacyId];
    changed = true;
  }
  return { profile: { components: out }, changed };
}

export async function loadProfile(path_: string): Promise<Profile> {
  let data: string;
  try {
    data = await readFile(path_, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") {
      return defaultProfile();
    }
    throw err;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(data);
  } catch (cause) {
    throw new Error(
      `invalid profile: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
  requireComponentsObject(parsed);

  let profile: Profile = parsed as Profile;
  let migrated: boolean;
  ({ profile, changed: migrated } = migrateProfileData(profile));

  // Reject unknown ids AFTER migration, matching Go's LoadProfile order:
  // legacy aggregates are legal in files but not after expansion.
  for (const id of Object.keys(profile.components)) {
    if (!catalogIds.has(id)) {
      throw new Error(`invalid profile: unknown component "${id}"`);
    }
  }

  // Fill missing ids as false, in manifest order, for deterministic output.
  const normalized: Record<string, boolean> = {};
  for (const component of COMPONENTS) {
    normalized[component.id] = profile.components[component.id] ?? false;
  }
  // Force required components enabled regardless of file contents.
  for (const component of COMPONENTS) {
    if (component.required) {
      normalized[component.id] = true;
    }
  }
  profile = { components: normalized };

  if (migrated) {
    await saveProfile(path_, profile);
  }
  return profile;
}

export async function saveProfile(
  path_: string,
  profile: Profile,
): Promise<void> {
  // Validate before touching the filesystem so failures leave nothing behind.
  validateProfile(profile);

  const dir = path.dirname(path_);
  const data = JSON.stringify(profile, null, 2) + "\n";
  await mkdir(dir, { recursive: true });

  // Temp file MUST live in the target directory so the same-directory rename
  // is atomic on macOS/APFS (ADR-7).
  const tmp = path.join(dir, `.profile-${process.pid}-${randomUUID()}`);
  try {
    await writeFile(tmp, data, "utf8");
    await rename(tmp, path_);
  } catch (err) {
    await unlink(tmp).catch(() => {});
    throw err;
  }
}
