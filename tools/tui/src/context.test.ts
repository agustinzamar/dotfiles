// Task 2.1 (RED first): pins the context-file contract for --context <path>.
// The context JSON v1 is emitted by install/manifest.sh (ADR-2) and consumed
// exclusively through loadContext — one hand-rolled loader, matching the
// profile.ts style (explicit require* guards, no zod).
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { loadContext, type InstallContext } from "./context";

const tempDirs: string[] = [];

async function makeTempDir(): Promise<string> {
  const dir = await mkdtemp(path.join(tmpdir(), "dot-tui-context-test-"));
  tempDirs.push(dir);
  return dir;
}

async function writeContext(data: unknown): Promise<string> {
  const dir = await makeTempDir();
  const target = path.join(dir, "context.json");
  await writeFile(target, JSON.stringify(data));
  return target;
}

// The exact golden shape install/manifest.sh emits (test/manifest.bats).
const validContext: InstallContext = {
  version: 1,
  locked: ["base", "shell"],
  packages: [
    {
      id: "fzf",
      topic: "core",
      kind: "brew",
      area: "shell",
      locked: true,
      default: false,
    },
    {
      id: "ghostty",
      topic: "core",
      kind: "cask",
      area: "terminal",
      locked: false,
      default: true,
    },
    {
      id: 'we"ird\\name',
      topic: "core",
      kind: "brew",
      area: "terminal",
      locked: false,
      default: false,
    },
  ],
  links: [
    {
      name: "ghostty",
      optional: false,
      component: "terminal",
      requirement: "",
      rows: [
        {
          source: "config/ghostty/config",
          target: "~/.config/ghostty/config",
          mode: "",
        },
        {
          source: "config/ghostty/config",
          target: "~/Library/ghostty.conf",
          mode: "",
        },
      ],
    },
    {
      name: "agents",
      optional: true,
      component: "ai",
      requirement: "",
      rows: [
        { source: "ai/AGENTS.md", target: "~/.claude/CLAUDE.md", mode: "" },
      ],
    },
  ],
};

afterAll(async () => {
  for (const dir of tempDirs) {
    await rm(dir, { recursive: true, force: true });
  }
});

describe("loading a valid context file", () => {
  test("a v1 context file loads with typed packages and links", async () => {
    const target = await writeContext(validContext);
    const context = await loadContext(target);

    expect(context.version).toBe(1);
    expect(context.locked).toEqual(["base", "shell"]);
    expect(context.packages).toHaveLength(3);
    expect(context.packages[0]).toEqual({
      id: "fzf",
      topic: "core",
      kind: "brew",
      area: "shell",
      locked: true,
      default: false,
      installed: false,
    });
    // Multi-target rows survive the round-trip untouched.
    expect(context.links[0]!.name).toBe("ghostty");
    expect(context.links[0]!.rows).toHaveLength(2);
    expect(context.links[1]!.optional).toBe(true);
    // Escaped ids must come back as the raw data, not the JSON form.
    expect(context.packages[2]!.id).toBe('we"ird\\name');
  });

  test("empty packages and links arrays are valid (no topics dir yet)", async () => {
    const target = await writeContext({
      version: 1,
      locked: ["base", "shell"],
      packages: [],
      links: [],
    });
    const context = await loadContext(target);
    expect(context.packages).toEqual([]);
    expect(context.links).toEqual([]);
  });
});

describe("rejecting the wrong or missing version", () => {
  test("a missing version field is rejected", async () => {
    const target = await writeContext({
      locked: ["base"],
      packages: [],
      links: [],
    });
    expect(loadContext(target)).rejects.toThrow(/invalid context: version/);
  });

  test("a future version (2) is rejected instead of misread", async () => {
    const target = await writeContext({ ...validContext, version: 2 });
    expect(loadContext(target)).rejects.toThrow(/invalid context: version/);
  });

  test("a string version is rejected", async () => {
    const target = await writeContext({ ...validContext, version: "1" });
    expect(loadContext(target)).rejects.toThrow(/invalid context: version/);
  });
});

describe("rejecting malformed package rows", () => {
  test("packages that are not an array are rejected", async () => {
    const target = await writeContext({ ...validContext, packages: {} });
    expect(loadContext(target)).rejects.toThrow(
      /invalid context: packages must be an array/,
    );
  });

  test("a package row without an id is rejected", async () => {
    const target = await writeContext({
      ...validContext,
      packages: [
        {
          topic: "core",
          kind: "brew",
          area: "shell",
          locked: false,
          default: false,
        },
      ],
    });
    expect(loadContext(target)).rejects.toThrow(
      /invalid context: malformed packages row/,
    );
  });

  test("a package row with a non-string area is rejected", async () => {
    const target = await writeContext({
      ...validContext,
      packages: [
        {
          id: "x",
          topic: "core",
          kind: "brew",
          area: 7,
          locked: false,
          default: false,
        },
      ],
    });
    expect(loadContext(target)).rejects.toThrow(
      /invalid context: malformed packages row/,
    );
  });
});

describe("rejecting malformed link rows", () => {
  test("links that are not an array are rejected", async () => {
    const target = await writeContext({ ...validContext, links: "all" });
    expect(loadContext(target)).rejects.toThrow(
      /invalid context: links must be an array/,
    );
  });

  test("a link row without a name is rejected", async () => {
    const target = await writeContext({
      ...validContext,
      links: [
        { optional: false, component: "terminal", requirement: "", rows: [] },
      ],
    });
    expect(loadContext(target)).rejects.toThrow(
      /invalid context: malformed links row/,
    );
  });

  test("a link row whose rows are not an array is rejected", async () => {
    const target = await writeContext({
      ...validContext,
      links: [
        {
          name: "ghostty",
          optional: false,
          component: "terminal",
          requirement: "",
          rows: {},
        },
      ],
    });
    expect(loadContext(target)).rejects.toThrow(
      /invalid context: malformed links row/,
    );
  });

  test("a row without a source is rejected", async () => {
    const target = await writeContext({
      ...validContext,
      links: [
        {
          name: "ghostty",
          optional: false,
          component: "terminal",
          requirement: "",
          rows: [{ target: "~/.config/ghostty/config", mode: "" }],
        },
      ],
    });
    expect(loadContext(target)).rejects.toThrow(
      /invalid context: malformed links row/,
    );
  });
});

describe("rejecting an unreadable or malformed file", () => {
  test("a missing file is rejected loudly with its path", async () => {
    const missing = path.join(await makeTempDir(), "does-not-exist.json");
    expect(loadContext(missing)).rejects.toThrow(/does-not-exist\.json/);
  });

  test("malformed JSON is rejected", async () => {
    const dir = await makeTempDir();
    const target = path.join(dir, "context.json");
    await writeFile(target, "{not valid json");
    expect(loadContext(target)).rejects.toThrow(/invalid context/);
  });

  test("locked must be an array of strings when present", async () => {
    const target = await writeContext({ ...validContext, locked: "base" });
    expect(loadContext(target)).rejects.toThrow(/invalid context: locked/);
  });
});
