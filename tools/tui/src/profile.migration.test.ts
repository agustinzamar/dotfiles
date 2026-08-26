// Task 2.7 (RED first): legacy profile migration onto area ids (ADR-4).
// Go-era profiles store 31 component ids; the area-level profile stores only
// area ids (the unit components.sh gates on). Migration maps each legacy id (or
// aggregate) to the area ids it must enable, so old headless profiles keep
// reinstalling the same tools on the same links.
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

// Independent expectations, derived from the legacy semantics: the old
// communication/desktop/media/databases aggregates map to area ids.
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

describe("legacy profile migration onto area ids", () => {
  test("enabled communication expands to the desktop area", () => {
    const { profile, changed } = migrateProfileData({
      components: { communication: true },
    });
    expect(changed).toBe(true);
    expect(profile.components["desktop"]).toBe(true);
    expect(profile.components["communication-discord"]).toBeUndefined();
  });

  test("area-id aggregates (desktop, media) pass through unchanged", () => {
    // desktop/media are BOTH legacy aggregate names and valid area ids; a
    // migrated profile stores the area id, so re-migration must not re-expand
    // (the no-op invariant is what keeps every load stable).
    const { profile, changed } = migrateProfileData({
      components: { desktop: true, media: false },
    });
    expect(changed).toBe(false);
    expect(profile.components["desktop"]).toBe(true);
    expect(profile.components["media"]).toBe(false);
    expect(profile.components["desktop-aerospace"]).toBeUndefined();
    expect(profile.components["media-vlc"]).toBeUndefined();
  });

  test("enabled databases expands to the dev area", () => {
    const { profile, changed } = migrateProfileData({
      components: { databases: true },
    });
    expect(changed).toBe(true);
    expect(profile.components["dev"]).toBe(true);
  });

  test("legacy child ids map onto their area ids one by one", () => {
    const { profile, changed } = migrateProfileData({
      components: {
        "communication-discord": true,
        "media-vlc": true,
        "service-mysql": true,
        "desktop-aerospace": true,
        "ai-herdr": true,
      },
    });
    expect(changed).toBe(true);
    expect(profile.components["desktop"]).toBe(true);
    expect(profile.components["media"]).toBe(true);
    expect(profile.components["dev"]).toBe(true);
    expect(profile.components["desktop-aerospace"]).toBe(true);
    expect(profile.components["ai-herdr"]).toBe(true);
    for (const legacy of [
      "communication-discord",
      "media-vlc",
      "service-mysql",
    ]) {
      expect(profile.components[legacy]).toBeUndefined();
    }
  });

  test("disabled legacy id enables nothing but is still removed", () => {
    const { profile, changed } = migrateProfileData({
      components: { databases: false },
    });
    expect(changed).toBe(true);
    expect(profile.components["dev"]).toBeFalsy();
    expect(profile.components).not.toHaveProperty("databases");
  });

  test("identity ids (base, shell, git, terminal, vscode, ai) pass through", () => {
    const { profile, changed } = migrateProfileData({
      components: { base: true, vscode: true, ai: false },
    });
    expect(changed).toBe(false);
    expect(profile.components["base"]).toBe(true);
    expect(profile.components["vscode"]).toBe(true);
    expect(profile.components["ai"]).toBe(false);
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
    expect(loaded.components["base"]).toBe(true);
    expect(loaded.components["desktop"]).toBe(true);
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
