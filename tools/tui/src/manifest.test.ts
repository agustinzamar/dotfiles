// Planner-metadata tests over the context contract (ADR-2/4).
//
// The Go-era embedded catalog (COMPONENTS, 31 entries) is RETIRED: the Bash
// emitter install/manifest.sh is the single package source of truth, and this
// module only shapes rows. The ADR-3 link-filter rule is covered by
// filter.test.ts; context loading by context.test.ts.

import { describe, expect, test } from "bun:test";
import type { InstallContext } from "./context";
import {
  LOCKED_PSEUDO_STEPS,
  activeProfileAreas,
  selectedPackages,
  toolGroups,
  toolRows,
} from "./manifest";

const fixture: InstallContext = {
  version: 1,
  locked: ["base", "shell"],
  packages: [
    { id: "fzf", topic: "core", kind: "brew", area: "shell", locked: true, default: false },
    { id: "tmux", topic: "core", kind: "brew", area: "terminal", locked: true, default: false },
    { id: "ghostty", topic: "core", kind: "cask", area: "terminal", locked: false, default: true },
    { id: "lazygit", topic: "core", kind: "brew", area: "git", locked: false, default: true },
    { id: "opencode", topic: "dev", kind: "brew", area: "ai", locked: false, default: false },
    { id: "code", topic: "code", kind: "topic", area: "vscode", locked: false, default: false },
    { id: "duti-defaults", topic: "duti", kind: "topic", area: "terminal", locked: false, default: false },
  ],
  links: [],
};

describe("LOCKED_PSEUDO_STEPS", () => {
  test("both steps are locked, informational, and map to sub_zsh/sub_git", () => {
    expect(LOCKED_PSEUDO_STEPS).toHaveLength(2);
    expect(LOCKED_PSEUDO_STEPS.map((s) => s.command)).toEqual(["dot zsh", "dot git"]);
    for (const step of LOCKED_PSEUDO_STEPS) {
      expect(typeof step.label).toBe("string");
      expect(step.label.length).toBeGreaterThan(0);
    }
  });
});

describe("toolRows", () => {
  test("pseudo-steps come first, then locked packages pinned under 'locked'", () => {
    const rows = toolRows(fixture);
    expect(rows[0]!.id).toBe("zsh-setup");
    expect(rows[0]!.area).toBe("shell");
    expect(rows[0]!.pseudo).toBe(true);
    expect(rows[1]!.id).toBe("git-signing");
    // fzf is locked: pinned under category 'locked' immediately after
    // pseudo-steps (its topic stays 'core').
    const fzf = rows.find((r) => r.id === "fzf")!;
    expect(fzf.category).toBe("locked");
    expect(fzf.topic).toBe("core");
    expect(fzf.locked).toBe(true);
    expect(fzf.pseudo).toBe(false);
  });

  test("locked/default flags carry from the context package rows", () => {
    const rows = toolRows(fixture);
    const ghostty = rows.find((r) => r.id === "ghostty")!;
    expect(ghostty.locked).toBe(false);
    expect(ghostty.default).toBe(true);
    const opencode = rows.find((r) => r.id === "opencode")!;
    expect(opencode.default).toBe(false);
  });

  test("special code/duti delegating rows are NOT step-1 rows", () => {
    const ids = toolRows(fixture).map((r) => r.id);
    expect(ids).not.toContain("code");
    expect(ids).not.toContain("duti-defaults");
  });
});

describe("toolGroups", () => {
  test("groups appear in first-seen category order with locked rows first", () => {
    const groups = toolGroups(fixture);
    expect(groups.map((g) => g.topic)).toEqual([
      "locked",
      "core",
      "dev",
    ]);
    expect(groups[0]!.rows.map((r) => r.id)).toEqual(["zsh-setup", "git-signing", "fzf", "tmux"]);
  });
});

describe("selectedPackages", () => {
  test("returns confirmed rows in context order, locked rows only when selected", () => {
    const picked = selectedPackages(
      fixture,
      new Set(["ghostty", "code", "tmux"]),
    );
    expect(picked.map((p) => p.id)).toEqual(["tmux", "ghostty", "code"]);
  });
});

describe("activeProfileAreas", () => {
  test("locked areas union the areas of confirmed rows", () => {
    const areas = activeProfileAreas(fixture, new Set(["ghostty", "opencode"]));
    // base+shell from locked; shell again from zsh-setup; terminal from ghostty;
    // ai from opencode.
    expect(new Set(areas)).toEqual(
      new Set(["base", "shell", "git", "terminal", "ai"]),
    );
  });

  test("locked areas only when nothing is selected", () => {
    const areas = activeProfileAreas(fixture, new Set());
    // base from locked; shell from locked + zsh-setup step; git from git-signing.
    // Locked package rows (fzf, tmux) are not "selected", so terminal stays out.
    expect(new Set(areas)).toEqual(new Set(["base", "shell", "git"]));
  });
});