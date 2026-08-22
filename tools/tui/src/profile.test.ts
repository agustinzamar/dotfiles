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
import { COMPONENTS } from "./manifest";
import { defaultProfile, loadProfile, saveProfile } from "./profile";

// Independent source of truth: installer-profile spec "Required Baseline Components".
const BASELINE_IDS = ["base", "shell", "git", "terminal"];

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
  test("defaults match manifest", () => {
    const profile = defaultProfile();
    expect(Object.keys(profile.components)).toHaveLength(COMPONENTS.length);
    for (const c of COMPONENTS) {
      expect(profile.components[c.id]).toBe(c.default || c.required);
    }
    // Literal baseline assertion independent of the manifest loop above.
    for (const id of BASELINE_IDS) {
      expect(profile.components[id]).toBe(true);
    }
  });

  test("every component id is present in the default profile", () => {
    const profile = defaultProfile();
    for (const c of COMPONENTS) {
      expect(profile.components).toHaveProperty(c.id);
    }
  });
});

describe("loading profiles", () => {
  test("missing profile file falls back to defaults", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "nested", "deeper", "profile.json");
    const profile = await loadProfile(target);
    expect(profile).toEqual(defaultProfile());
    expect(Object.keys(profile.components)).toHaveLength(31);
  });

  test("unknown id in file is rejected on load", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await writeFile(
      target,
      JSON.stringify({ components: { "not-a-component": true } }),
    );
    expect(loadProfile(target)).rejects.toThrow(
      /unknown component "not-a-component"/,
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

  test("missing ids are filled false and required forced true", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    await writeFile(target, JSON.stringify({ components: { ai: true } }));
    const profile = await loadProfile(target);
    expect(profile.components["ai"]).toBe(true);
    for (const id of BASELINE_IDS) {
      expect(profile.components[id]).toBe(true);
    }
    for (const c of COMPONENTS) {
      if (BASELINE_IDS.includes(c.id) || c.id === "ai") continue;
      expect(profile.components[c.id]).toBe(false);
    }
    expect(Object.keys(profile.components)).toHaveLength(31);
  });
});

describe("profile validation on save", () => {
  test("unknown id rejected on save without writing the file", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "profile.json");
    const bad = { components: { nope: true } } as never;
    expect(saveProfile(target, bad)).rejects.toThrow(
      /unknown component "nope"/,
    );
    expect(readdir(dir)).resolves.toEqual([]);
  });

  test("disabled required component rejected on save", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "sub", "profile.json");
    const profile = defaultProfile();
    profile.components["base"] = false;
    expect(saveProfile(target, profile)).rejects.toThrow(
      /required component "base" is disabled/,
    );
    // Validation must fire before mkdir touches the filesystem.
    expect(readdir(dir)).resolves.toEqual([]);
  });
});

describe("atomic save with trailing newline", () => {
  test("save round-trips through tmp-and-rename", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "nested", "profile.json");
    const profile = defaultProfile();
    profile.components["ai"] = true;
    profile.components["media-vlc"] = true;
    profile.components["php"] = true;
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
    expect(bytes.trimEnd()).toBe(JSON.stringify(defaultProfile(), null, 2));
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
