// Area-level profile writer/loader (ADR-4). The profile stores
// .components[areaId] == true for active area ids only — the same unit
// install/components.sh gates on via component_selected(). Link choices are
// never persisted. Missing files and absent fields fall back to
// component_default_selected (base|shell|git|terminal true), so stale or
// missing profiles never break `dot link` gating. Legacy Go-era component ids
// migrate onto their area ids so old headless profiles keep working.
import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import * as path from "node:path";

export interface Profile {
  components: Record<string, boolean>;
}

// Area ids install/components.sh and install/links.sh already use (mirrors
// install/manifest.sh area_for_package's fixed ids plus desktop-* subareas).
const FIXED_AREAS = [
  "base",
  "shell",
  "git",
  "terminal",
  "vscode",
  "ai",
  "ai-herdr",
  "claude",
  "dev",
  "media",
  "desktop",
];

// component_default_selected in install/components.sh.
const DEFAULT_AREAS = new Set(["base", "shell", "git", "terminal"]);

function isAreaId(id: string): boolean {
  return FIXED_AREAS.includes(id) || id.startsWith("desktop-");
}

// Legacy Go-era component id (or aggregate) -> area ids to enable. Derived
// from the old catalog: communication/desktop children were desktop casks,
// media children were media casks, databases services were dev formulas, and
// the desktop aggregate also carried the subarea configs. Ids that are already
// valid area ids (base, shell, git, terminal, vscode, ai, ai-herdr,
// desktop-aerospace, desktop-linearmouse) are NOT listed: they pass through
// unchanged so migration stays a no-op on already-migrated profiles.
const LEGACY_COMPONENT_AREAS: Record<string, readonly string[]> = {
  php: ["dev"],
  "service-mysql": ["dev"],
  "service-postgresql": ["dev"],
  "service-redis": ["dev"],
  "service-sqlite": ["dev"],
  "communication-discord": ["desktop"],
  "communication-telegram": ["desktop"],
  "communication-whatsapp": ["desktop"],
  "communication-slack": ["desktop"],
  "desktop-chrome": ["desktop"],
  "desktop-firefox": ["desktop"],
  "desktop-brave": ["desktop"],
  "desktop-raycast": ["desktop"],
  "desktop-finetune": ["desktop"],
  "desktop-typewhisper": ["desktop"],
  "desktop-rectangle": ["desktop"],
  "desktop-localsend": ["desktop"],
  "media-tools": ["media"],
  "media-spotify": ["media"],
  "media-stremio": ["media"],
  "media-vlc": ["media"],
  "media-castor": ["media"],
  communication: ["desktop"],
  desktop: ["desktop", "desktop-aerospace", "desktop-linearmouse"],
  media: ["media"],
  databases: ["dev"],
};

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

function validateProfile(profile: Profile): void {
  for (const id of Object.keys(profile.components)) {
    if (!isAreaId(id)) {
      throw new Error(`invalid profile: unknown component "${id}"`);
    }
  }
}

export function defaultProfile(): Profile {
  const components: Record<string, boolean> = {};
  for (const id of FIXED_AREAS) {
    components[id] = DEFAULT_AREAS.has(id);
  }
  return { components };
}

/** Maps a legacy Go-era profile onto area ids. Area ids pass through; a second
 *  run on an already-migrated profile reports no change. */
export function migrateProfileData(profile: Profile): {
  profile: Profile;
  changed: boolean;
} {
  requireComponentsObject(profile);
  const out: Record<string, boolean> = {};
  let changed = false;
  for (const [id, enabled] of Object.entries(profile.components)) {
    if (isAreaId(id)) {
      // Already a valid area id: pass through unchanged so a second run on
      // a migrated profile is a no-op (desktop/media are both area ids AND
      // legacy aggregate names).
      out[id] = enabled;
      continue;
    }
    const areas = LEGACY_COMPONENT_AREAS[id];
    if (areas) {
      if (enabled) {
        for (const area of areas) {
          if (out[area] !== true) {
            out[area] = true;
            changed = true;
          }
        }
      } else {
        changed = true; // the legacy key itself never survives
      }
    } else {
      out[id] = enabled;
    }
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

  // Reject unknown ids AFTER migration, matching the legacy LoadProfile order.
  for (const id of Object.keys(profile.components)) {
    if (!isAreaId(id)) {
      throw new Error(`invalid profile: unknown component "${id}"`);
    }
  }

  // Fill missing fields with component_default_selected (absent fields MAY fall
  // back to defaults; stale profiles must not break other commands).
  const normalized: Record<string, boolean> = {};
  for (const id of FIXED_AREAS) {
    normalized[id] = profile.components[id] ?? DEFAULT_AREAS.has(id);
  }
  for (const id of Object.keys(profile.components)) {
    if (!FIXED_AREAS.includes(id)) {
      normalized[id] = profile.components[id];
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
  // is atomic on macOS/APFS.
  const tmp = path.join(dir, `.profile-${process.pid}-${randomUUID()}`);
  try {
    await writeFile(tmp, data, "utf8");
    await rename(tmp, path_);
  } catch (err) {
    await unlink(tmp).catch(() => {});
    throw err;
  }
}
