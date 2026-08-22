import { describe, expect, test } from "bun:test";
import { COMPONENTS } from "./manifest";

const AGGREGATE_IDS = ["communication", "desktop", "media", "databases"];
const BASELINE_IDS = ["base", "shell", "git", "terminal"];

describe("component catalog", () => {
  test("has exactly 31 entries", () => {
    expect(COMPONENTS).toHaveLength(31);
  });

  test("every entry has required fields", () => {
    for (const c of COMPONENTS) {
      expect(typeof c.id).toBe("string");
      expect(c.id.length).toBeGreaterThan(0);
      expect(typeof c.label).toBe("string");
      expect(c.label.length).toBeGreaterThan(0);
      expect(typeof c.category).toBe("string");
      expect(c.category.length).toBeGreaterThan(0);
      expect(typeof c.default).toBe("boolean");
      expect(typeof c.required).toBe("boolean");
    }
  });

  test("ids are unique", () => {
    const seen = new Set<string>();
    for (const c of COMPONENTS) {
      expect(seen.has(c.id)).toBe(false);
      seen.add(c.id);
    }
    expect(seen.size).toBe(COMPONENTS.length);
  });

  test("baseline components are present and required", () => {
    const byId = new Map(COMPONENTS.map((c) => [c.id, c]));
    for (const id of BASELINE_IDS) {
      const c = byId.get(id);
      expect(c).toBeDefined();
      expect(c!.required).toBe(true);
    }
    for (const id of BASELINE_IDS) {
      expect(byId.get(id)!.default).toBe(true);
    }
  });

  test("legacy aggregate ids are absent", () => {
    const ids = new Set(COMPONENTS.map((c) => c.id));
    for (const id of AGGREGATE_IDS) {
      expect(ids.has(id)).toBe(false);
    }
  });

  test("individual replacements exist", () => {
    const ids = new Set(COMPONENTS.map((c) => c.id));
    for (const id of [
      "communication-discord",
      "communication-slack",
      "media-spotify",
      "media-vlc",
      "desktop-chrome",
      "service-mysql",
      "service-postgresql",
      "service-redis",
      "service-sqlite",
      "ai-herdr",
    ]) {
      expect(ids.has(id)).toBe(true);
    }
  });

  test("git covers hunk in links and commands", () => {
    const git = COMPONENTS.find((c) => c.id === "git");
    expect(git).toBeDefined();
    expect(git!.links).toContain("hunk");
    expect(
      git!.commands!.some(
        (cmd) => cmd.includes("brew install") && cmd.includes("hunk"),
      ),
    ).toBe(true);
  });

  test("split tool ids stay combined into git/php components", () => {
    const ids = new Set(COMPONENTS.map((c) => c.id));
    for (const id of ["hunk", "laravel", "phpstorm"]) {
      expect(ids.has(id)).toBe(false);
    }
  });

  test("php installs through herd, never brew install php", () => {
    const php = COMPONENTS.find((c) => c.id === "php");
    expect(php).toBeDefined();
    for (const cmd of php!.commands ?? []) {
      expect(cmd).not.toBe("brew install php");
      expect(cmd).not.toBe("brew install php composer");
    }
    expect(
      php!.commands!.some(
        (cmd) => cmd.includes("composer") && cmd.includes("Herd"),
      ),
    ).toBe(true);
    expect(php!.commands!.some((cmd) => cmd.includes("--cask phpstorm"))).toBe(
      true,
    );
  });

  test("base keeps xcode-select but has no Go toolchain reference", () => {
    const base = COMPONENTS.find((c) => c.id === "base");
    expect(base).toBeDefined();
    expect(base!.commands).toContain("xcode-select --install");
    expect(base!.commands!.some((cmd) => cmd.includes("go"))).toBe(false);
  });
});
