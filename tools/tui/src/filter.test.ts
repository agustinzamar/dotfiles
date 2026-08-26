// Task 2.3 (RED first): table-driven tests for the ADR-3 link-filter rule.
// A link is offered iff  requirement != "" -> the package row with id ==
// requirement is confirmed; OR requirement == "" -> the link's component area
// is active (area in context.locked, or >=1 confirmed row has that area).
// Locked package rows are always installed through a separate channel and do
// NOT count as confirmed selections here, so the locked block alone offers only
// locked-block untagged links (installer-tui spec scenario). Optional links
// (agents) are always offered, independent of selections.
import { describe, expect, test } from "bun:test";
import type { ContextLink, InstallContext, LinkRow } from "./context";
import { offeredLinks } from "./manifest";

const row = (source: string, target: string, mode = ""): LinkRow => ({
  source,
  target,
  mode,
});

const link = (
  partial: Partial<ContextLink> & { name: string },
): ContextLink => ({
  optional: false,
  component: "",
  requirement: "",
  rows: [row(`config/${partial.name}/x`, `~/.${partial.name}/x`)],
  ...partial,
});

const pkg = (
  id: string,
  area: string,
  opts: { locked?: boolean; default?: boolean; topic?: string } = {},
): InstallContext["packages"][number] => ({
  id,
  topic: opts.topic ?? "core",
  kind: "brew",
  area,
  locked: opts.locked ?? false,
  default: opts.default ?? false,
});

// Fixture mirrors the real-tree shape: locked rows fzf/git/tmux plus toggleable
// rows across several areas, requirement-gated links, and an optional group.
function fixtureContext(): InstallContext {
  return {
    version: 1,
    locked: ["base", "shell"],
    packages: [
      pkg("fzf", "shell", { locked: true }),
      pkg("git", "git", { locked: true }),
      pkg("tmux", "terminal", { locked: true }),
      pkg("ghostty", "terminal", { default: true }),
      pkg("hunk", "git", { default: true }),
      pkg("lazygit", "git", { default: true }),
      pkg("opencode", "ai"),
      pkg("code", "vscode", { topic: "code" }),
    ],
    links: [
      // Locked-block untagged links (component shell is a locked area).
      link({ name: "zsh", component: "shell" }),
      link({ name: "p10k", component: "shell" }),
      // Area-gated links, no requirement.
      link({
        name: "ghostty",
        component: "terminal",
        rows: [row("a", "b"), row("a", "c")],
      }),
      link({ name: "tmux", component: "terminal" }),
      link({ name: "opencode", component: "ai" }),
      // Requirement-gated links.
      link({ name: "hunk", component: "git", requirement: "hunk" }),
      link({ name: "lazygit", component: "git", requirement: "lazygit" }),
      link({ name: "vscode", component: "vscode", requirement: "code" }),
      // Requirement names a LOCKED row (git): never hits, locked rows are not
      // confirmed selections (documented ADR-3 deviation, spec-aligned).
      link({ name: "git-ignore", component: "git", requirement: "git" }),
      // Optional group: independent of selections.
      link({
        name: "agents",
        optional: true,
        component: "ai",
        rows: [row("a", "b"), row("a", "c")],
      }),
      link({ name: "claude", optional: true, component: "ai" }),
    ],
  };
}

const names = (links: ContextLink[]): string[] => links.map((l) => l.name);

describe("ADR-3 filter rule (table-driven)", () => {
  test("requirement hit: link offered when its requirement row is confirmed", () => {
    const cases: Array<{ selected: string[]; expected: string[] }> = [
      { selected: ["hunk"], expected: ["zsh", "p10k", "hunk"] },
      { selected: ["lazygit"], expected: ["zsh", "p10k", "lazygit"] },
      { selected: ["code"], expected: ["zsh", "p10k", "vscode"] },
      // Multiple requirement hits and area hits combine; the locked-block
      // links stay co-offered.
      {
        selected: ["hunk", "ghostty"],
        expected: ["zsh", "p10k", "ghostty", "tmux", "hunk"],
      },
    ];
    for (const c of cases) {
      const { main } = offeredLinks(fixtureContext(), new Set(c.selected));
      expect(names(main)).toEqual(c.expected);
    }
  });

  test("requirement miss: link excluded when its requirement row is not confirmed", () => {
    const cases: Array<{ selected: string[]; excluded: string[] }> = [
      // ghostty selected: hunk/lazygit/vscode requirements all unconfirmed.
      { selected: ["ghostty"], excluded: ["hunk", "lazygit", "vscode"] },
      // code selected: hunk and lazygit still miss.
      { selected: ["code"], excluded: ["hunk", "lazygit"] },
      // vscode excluded even though a vscode-area row was selected (the area
      // rule never applies to requirement-gated links).
      { selected: ["code"], excluded: ["git-ignore"] },
    ];
    for (const c of cases) {
      const { main } = offeredLinks(fixtureContext(), new Set(c.selected));
      for (const name of c.excluded) {
        expect(names(main)).not.toContain(name);
      }
    }
  });

  test("locked-area activity: locked-block untagged links offered with NO selections", () => {
    const { main } = offeredLinks(fixtureContext(), new Set());
    expect(names(main)).toEqual(["zsh", "p10k"]);
  });

  test("inactive area: links excluded when their area is untapped", () => {
    const cases: Array<{ selected: string[]; excluded: string[] }> = [
      // No ai/vscode activity at all.
      { selected: ["hunk"], excluded: ["opencode", "vscode", "tmux"] },
      // ai active only via an ai row.
      { selected: ["opencode"], excluded: ["vscode", "tmux"] },
    ];
    for (const c of cases) {
      const { main } = offeredLinks(fixtureContext(), new Set(c.selected));
      for (const name of c.excluded) {
        expect(names(main)).not.toContain(name);
      }
    }
  });

  test("empty selection: only locked-block untagged links are offered", () => {
    const { main } = offeredLinks(fixtureContext(), new Set());
    expect(names(main)).toEqual(["zsh", "p10k"]);
    // Locked rows alone never light up their areas (tmux -> terminal off).
    expect(names(main)).not.toContain("ghostty");
    expect(names(main)).not.toContain("tmux");
    expect(names(main)).not.toContain("git-ignore");
  });

  test("locked rows never count as confirmed selections for either rule", () => {
    // A selection containing ONLY locked rows is indistinguishable from empty.
    const lockedOnly = offeredLinks(
      fixtureContext(),
      new Set(["fzf", "git", "tmux"]),
    );
    const empty = offeredLinks(fixtureContext(), new Set());
    expect(names(lockedOnly.main)).toEqual(names(empty.main));
  });

  test("optional agents group is always present, unchecked, independent of selections", () => {
    for (const selected of [
      new Set<string>(),
      new Set(["ghostty"]),
      new Set(["code"]),
    ]) {
      const { agents } = offeredLinks(fixtureContext(), selected);
      expect(names(agents)).toEqual(["agents", "claude"]);
    }
  });

  test("offered links keep their full row list (multi-target rows intact)", () => {
    const { main } = offeredLinks(fixtureContext(), new Set(["ghostty"]));
    const ghostty = main.find((l) => l.name === "ghostty");
    expect(ghostty).toBeDefined();
    expect(ghostty!.rows).toHaveLength(2);
  });
});
