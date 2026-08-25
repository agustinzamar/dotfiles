import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import {
  defaultProfile,
  loadProfile,
  migrateProfileData,
  type Profile,
} from "./profile";

// Expected child lists come straight from the installer-profile spec
// "Legacy Aggregate Migration" table — an independent source of truth, not a
// copy of the implementation's table.
const COMMUNICATION_CHILDREN = [
  "communication-discord",
  "communication-telegram",
  "communication-whatsapp",
  "communication-slack",
];
const DESKTOP_CHILDREN = [
  "desktop-chrome",
  "desktop-firefox",
  "desktop-brave",
  ...COMMUNICATION_CHILDREN,
  "desktop-raycast",
  "desktop-finetune",
  "desktop-typewhisper",
  "desktop-rectangle",
  "desktop-aerospace",
  "desktop-linearmouse",
  "desktop-localsend",
];
const MEDIA_CHILDREN = [
  "media-tools",
  "media-spotify",
  "media-stremio",
  "media-vlc",
  "media-castor",
];
const DATABASES_CHILDREN = [
  "service-mysql",
  "service-postgresql",
  "service-redis",
  "service-sqlite",
];

const tempDirs: string[] = [];

async function makeTempDir(): Promise<string> {
  const dir = await mkdtemp(
    path.join(tmpdir(), "dot-tui-profile-migration-test-"),
  );
  tempDirs.push(dir);
  return dir;
}

afterAll(async () => {
  for (const dir of tempDirs) {
    await rm(dir, { recursive: true, force: true });
  }
});

function enabledChildren(profile: Profile, children: string[]): string[] {
  return children.filter((id) => profile.components[id] === true);
}

describe("legacy aggregate migration", () => {
  test("enabled communication expands to exactly its four children", () => {
    const { profile, changed } = migrateProfileData({
      components: { communication: true },
    });
    expect(changed).toBe(true);
    expect(enabledChildren(profile, COMMUNICATION_CHILDREN)).toEqual(
      COMMUNICATION_CHILDREN,
    );
    // Nothing else was enabled and the aggregate key is gone.
    const enabled = Object.keys(profile.components).filter(
      (id) => profile.components[id],
    );
    expect(enabled).toEqual(COMMUNICATION_CHILDREN);
  });

  test("enabled desktop expands to desktop plus communication children", () => {
    const { profile, changed } = migrateProfileData({
      components: { desktop: true },
    });
    expect(changed).toBe(true);
    expect(enabledChildren(profile, DESKTOP_CHILDREN)).toEqual(
      DESKTOP_CHILDREN,
    );
    const enabled = Object.keys(profile.components).filter(
      (id) => profile.components[id],
    );
    expect(enabled.sort()).toEqual([...DESKTOP_CHILDREN].sort());
  });

  test("enabled media expands to its five children", () => {
    const { profile, changed } = migrateProfileData({
      components: { media: true },
    });
    expect(changed).toBe(true);
    expect(enabledChildren(profile, MEDIA_CHILDREN)).toEqual(MEDIA_CHILDREN);
  });

  test("enabled databases expands to its four services", () => {
    const { profile, changed } = migrateProfileData({
      components: { databases: true },
    });
    expect(changed).toBe(true);
    expect(enabledChildren(profile, DATABASES_CHILDREN)).toEqual(
      DATABASES_CHILDREN,
    );
  });

  test("disabled aggregate enables nothing but is still removed", () => {
    const { profile, changed } = migrateProfileData({
      components: { databases: false },
    });
    expect(changed).toBe(true);
    for (const id of DATABASES_CHILDREN) {
      expect(profile.components[id]).toBeFalsy();
    }
    expect(profile.components).not.toHaveProperty("databases");
  });

  test("all four aggregates together mirror the Go fixture", () => {
    const { profile, changed } = migrateProfileData({
      components: {
        base: true,
        communication: true,
        desktop: false,
        media: true,
        databases: true,
      },
    });
    expect(changed).toBe(true);
    for (const id of [
      ...COMMUNICATION_CHILDREN,
      ...MEDIA_CHILDREN,
      ...DATABASES_CHILDREN,
    ]) {
      expect(profile.components[id]).toBe(true);
    }
    // False desktop must NOT have enabled any of its children.
    for (const id of DESKTOP_CHILDREN) {
      if (!COMMUNICATION_CHILDREN.includes(id)) {
        expect(profile.components[id]).toBeFalsy();
      }
    }
    for (const legacy of ["communication", "desktop", "media", "databases"]) {
      expect(profile.components).not.toHaveProperty(legacy);
    }
  });

  test("second migration run is a no-op reporting no change", () => {
    const first = migrateProfileData({ components: { communication: true } });
    expect(first.changed).toBe(true);
    const second = migrateProfileData(first.profile);
    expect(second.changed).toBe(false);
    expect(second.profile).toEqual(first.profile);
  });

  test("migration rejects data without a components object", () => {
    expect(() => migrateProfileData({} as unknown as Profile)).toThrow(
      "invalid profile: components is required",
    );
  });
});

describe("load persists migrated data", () => {
  test("migrated profile is saved back on load", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await writeFile(
      target,
      JSON.stringify({ components: { base: true, communication: true } }),
    );
    const loaded = await loadProfile(target);
    expect(loaded.components["communication-discord"]).toBe(true);
    const saved = JSON.parse(await readFile(target, "utf8")) as Profile;
    expect(saved.components).not.toHaveProperty("communication");
    const reloaded = await loadProfile(target);
    expect(reloaded).toEqual(loaded);
  });

  test("already-migrated profile file is left untouched", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    const original =
      JSON.stringify({ components: { ai: true } }, null, 2) + "\n";
    await writeFile(target, original);
    await loadProfile(target);
    expect(await readFile(target, "utf8")).toBe(original);
  });

  test("missing file load does not create one", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "absent.json");
    const loaded = await loadProfile(target);
    expect(loaded).toEqual(defaultProfile());
    expect(readdir(dir)).resolves.toEqual([]);
  });
});
