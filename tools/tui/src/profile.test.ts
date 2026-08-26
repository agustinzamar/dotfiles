// Task 2.7 (RED first): profile semantics for the area-level contract (ADR-4).
// The profile stores .components[areaId] == true for active area ids only; link
// choices are never persisted. Missing files and absent fields fall back to
// component_default_selected (base|shell|git|terminal true), so stale or
// missing profiles never break `dot link` gating. Legacy Go-era component ids
// migrate onto their area ids so old headless profiles keep working.
import { afterAll, describe, expect, test } from "bun:test";
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { defaultProfile, loadProfile, saveProfile } from "./profile";

// Independent source of truth: install/components.sh component_default_selected.
const BASELINE_AREAS = ["base", "shell", "git", "terminal"];

const tempDirs: string[] = [];

async function makeTempDir(): Promise<string> {
  const dir = await mkdtemp(path.join(tmpdir(), "dot-tui-profile-test-"));
  tempDirs.push(dir);
  return dir;
}

afterAll(async () => {
  for (const dir of tempDirs) {
    await rm(dir, { recursive: true, force: true });
  }
});

describe("default profile derivation", () => {
  test("defaults mirror component_default_selected: baseline areas only", () => {
    const profile = defaultProfile();
    for (const id of BASELINE_AREAS) {
      expect(profile.components[id]).toBe(true);
    }
    expect(profile.components["vscode"]).toBe(false);
    expect(profile.components["ai"]).toBe(false);
    expect(profile.components["desktop"]).toBe(false);
  });
});

describe("loading profiles", () => {
  test("missing profile file falls back to defaults", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "nested", "deeper", "profile.json");
    const profile = await loadProfile(target);
    expect(profile).toEqual(defaultProfile());
  });

  test("area-level profile loads as-is", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await writeFile(
      target,
      JSON.stringify({ components: { vscode: true, ai: true } }),
    );
    const profile = await loadProfile(target);
    expect(profile.components["vscode"]).toBe(true);
    expect(profile.components["ai"]).toBe(true);
    // Absent fields fall back to component_default_selected, not false.
    for (const id of BASELINE_AREAS) {
      expect(profile.components[id]).toBe(true);
    }
    expect(profile.components["media"]).toBe(false);
  });

  test("legacy component ids migrate onto their area ids", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await writeFile(
      target,
      JSON.stringify({
        components: {
          "communication-discord": true,
          "media-vlc": true,
          "service-mysql": true,
          "desktop-aerospace": true,
          ai: true,
        },
      }),
    );
    const profile = await loadProfile(target);
    expect(profile.components["desktop"]).toBe(true); // communication child
    expect(profile.components["media"]).toBe(true);
    expect(profile.components["dev"]).toBe(true); // service-mysql
    expect(profile.components["desktop-aerospace"]).toBe(true);
    expect(profile.components["ai"]).toBe(true);
    // No legacy child ids survive migration.
    expect(profile.components["communication-discord"]).toBeUndefined();
    expect(profile.components["media-vlc"]).toBeUndefined();
  });

  test("unknown area id is rejected on load", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await writeFile(
      target,
      JSON.stringify({ components: { "not-an-area": true } }),
    );
    expect(loadProfile(target)).rejects.toThrow(
      /unknown component "not-an-area"/,
    );
  });

  test("malformed JSON is rejected", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await writeFile(target, "{not valid json");
    expect(loadProfile(target)).rejects.toThrow(/invalid profile/);
  });

  test("valid JSON without a components object is rejected", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await writeFile(target, JSON.stringify({ something_else: {} }));
    expect(loadProfile(target)).rejects.toThrow(
      "invalid profile: components is required",
    );
  });
});

describe("profile validation on save", () => {
  test("unknown area id rejected on save without writing the file", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    const bad = { components: { nope: true } } as never;
    expect(saveProfile(target, bad)).rejects.toThrow(
      /unknown component "nope"/,
    );
    expect(readdir(dir)).resolves.toEqual([]);
  });

  test("desktop-* subareas are valid area ids", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await saveProfile(target, {
      components: { "desktop-aerospace": true, "desktop-linearmouse": true },
    });
    const saved = JSON.parse(await readFile(target, "utf8")) as {
      components: Record<string, boolean>;
    };
    expect(saved.components["desktop-aerospace"]).toBe(true);
    expect(saved.components["desktop-linearmouse"]).toBe(true);
  });
});

describe("atomic save with trailing newline (unchanged behavior)", () => {
  test("save round-trips through tmp-and-rename", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "nested", "profile.json");
    const profile = defaultProfile();
    profile.components["ai"] = true;
    profile.components["media"] = true;
    await saveProfile(target, profile);
    const loaded = await loadProfile(target);
    expect(loaded).toEqual(profile);
  });

  test("saved bytes end with exactly one trailing newline", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await saveProfile(target, defaultProfile());
    const bytes = await readFile(target, "utf8");
    expect(bytes.endsWith("\n")).toBe(true);
    expect(bytes.endsWith("\n\n")).toBe(false);
  });

  test("no temporary files remain after save", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await saveProfile(target, defaultProfile());
    await saveProfile(target, defaultProfile());
    const entries = await readdir(path.dirname(target));
    expect(entries.filter((f) => f.startsWith(".profile-"))).toEqual([]);
    expect(entries).toEqual(["profile.json"]);
  });

  test("save creates a missing target directory", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "a", "b", "c", "profile.json");
    await saveProfile(target, defaultProfile());
    const loaded = await loadProfile(target);
    expect(loaded).toEqual(defaultProfile());
  });

  test("mkdir -p semantics: existing target directory is preserved", async () => {
    const dir = await makeTempDir();
    const sub = path.join(dir, "exists");
    await mkdir(sub);
    await writeFile(path.join(sub, "sentinel.txt"), "keep me");
    const target = path.join(sub, "profile.json");
    await saveProfile(target, defaultProfile());
    expect(await readFile(path.join(sub, "sentinel.txt"), "utf8")).toBe(
      "keep me",
    );
  });
});
