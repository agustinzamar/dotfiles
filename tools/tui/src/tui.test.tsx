// Task 2.5 (RED first): selector rendering tests for the two-step flow
// (design §2). Step 1 renders locked essentials pinned at top with a 🔒 marker,
// topic-grouped per-tool rows with strictly per-row toggles (locked rows ignore
// the toggle key entirely), former-baseline rows pre-checked but removable, and
// special code/duti rows included. Step 2 renders the ADR-3-filtered link list
// (one row per multi-target name, all unchecked) plus the opt-in AI agents
// group. Quit anywhere before confirm submits nothing (main exits 10).
import { afterEach, describe, expect, test } from "bun:test";
import { cleanup, render } from "ink-testing-library";
import type { InstallContext } from "./context";
import { toolRowsGrouped } from "./manifest";
import {
  adaptStepOne,
  adaptStepTwo,
  App,
  defaultValuesFor,
  initialState,
  linkView,
  mapInkKey,
  quitRequested,
  reducer,
  toggleLink,
  toggleableRowsForStep,
  toolView,
  type TuiState,
} from "./tui";

// ---------------------------------------------------------------------------
// Fixtures — mirrors the real-tree shape (test/manifest.bats golden json).
// ---------------------------------------------------------------------------

const fixtureContext: InstallContext = {
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
      id: "git",
      topic: "core",
      kind: "brew",
      area: "git",
      locked: true,
      default: false,
    },
    {
      id: "tmux",
      topic: "core",
      kind: "brew",
      area: "terminal",
      locked: true,
      default: false,
    },
    {
      id: "zsh",
      topic: "core",
      kind: "brew",
      area: "shell",
      locked: true,
      default: false,
    },
    {
      id: "gh",
      topic: "core",
      kind: "brew",
      area: "git",
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
      id: "lazygit",
      topic: "git",
      kind: "brew",
      area: "git",
      locked: false,
      default: true,
    },
    {
      id: "hunk",
      topic: "git",
      kind: "brew",
      area: "git",
      locked: false,
      default: true,
    },
    {
      id: "yazi",
      topic: "file",
      kind: "brew",
      area: "terminal",
      locked: false,
      default: true,
    },
    {
      id: "code",
      topic: "code",
      category: "Editors",
      kind: "topic",
      area: "vscode",
      locked: false,
      default: false,
    },
    {
      id: "duti-defaults",
      topic: "duti",
      category: "System",
      kind: "topic",
      area: "terminal",
      locked: false,
      default: false,
    },
    {
      id: "dock",
      topic: "system",
      category: "System",
      kind: "topic",
      area: "system",
      locked: false,
      default: false,
    },
    {
      id: "macos",
      topic: "system",
      category: "System",
      kind: "topic",
      area: "system",
      locked: false,
      default: false,
    },
    {
      id: "opencode",
      topic: "ai",
      kind: "brew",
      area: "ai",
      locked: false,
      default: false,
    },
    // Category/label/installed extensions: an AI tool from a foreign tap
    // (label collapses to the bare name), a browser grouped under Browsers,
    // and an installed formula pre-checked via installed:true.
    {
      id: "stupside/tap/castor",
      label: "castor",
      topic: "media",
      category: "media",
      kind: "cask",
      area: "media",
      locked: false,
      default: false,
    },
    {
      id: "brave-browser",
      topic: "desktop",
      category: "Browsers",
      kind: "cask",
      area: "desktop",
      locked: false,
      default: false,
    },
    {
      id: "7zip",
      topic: "core",
      kind: "brew",
      area: "terminal",
      locked: false,
      default: false,
      installed: true,
    },
  ],
  links: [
    {
      name: "zsh",
      optional: false,
      component: "shell",
      requirement: "",
      rows: [{ source: "config/zsh/.zshrc", target: "~/.zshrc", mode: "" }],
    },
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
      name: "hunk",
      optional: false,
      component: "git",
      requirement: "hunk",
      rows: [{ source: "config/hunk/x", target: "~/.config/hunk/x", mode: "" }],
    },
    {
      name: "lazygit",
      optional: false,
      component: "git",
      requirement: "lazygit",
      rows: [
        { source: "config/lazygit/x", target: "~/.config/lazygit/x", mode: "" },
      ],
    },
    {
      name: "opencode",
      optional: false,
      component: "ai",
      requirement: "",
      rows: [
        {
          source: "config/opencode/x",
          target: "~/.config/opencode/x",
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
        { source: "ai/AGENTS.md", target: "~/.agents/AGENTS.md", mode: "" },
      ],
    },
  ],
};

const key = (name: string, text?: string) => ({
  type: "key" as const,
  key: name,
  text,
});
const resize = (width: number, height: number) => ({
  type: "resize" as const,
  width,
  height,
});

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type Instance = ReturnType<typeof render>;

const press = async (ui: Instance, data: string) => {
  ui.stdin.write(data);
  await delay(10);
};

const KEY_ENTER = "\r";
const KEY_DOWN = "\x1b[B";

const TALL = { width: 100, height: 60 };

// Flat step-1 row order: pseudo-steps first, then locked rows, then toggleable
// rows in context order (topic grouping is a view concern, not row order).
// Delegates to the real production row order (toolRowsGrouped) instead of a
// hand-rolled mirror: a hand-rolled copy silently drifted out of sync once
// before (reduceKey moved to the grouped order, this helper did not), so the
// source of truth is the function under test, never a duplicate of it.
export function rowIndex(id: string): number {
  return toolRowsGrouped(fixtureContext)
    .map((r) => r.id)
    .indexOf(id);
}

// ---------------------------------------------------------------------------
// Phase 1 adapters — pure value adapters + option shapers (design §3.2/§2.2)
// ---------------------------------------------------------------------------

describe("adaptStepOne", () => {
  test("locked packages and pseudo-steps map to true regardless of value", () => {
    for (const value of [[], ["ghostty"], ["gh", "fzf", "zsh-setup"]]) {
      const selected = adaptStepOne(value, fixtureContext);
      expect(selected["zsh-setup"]).toBe(true);
      expect(selected["git-signing"]).toBe(true);
      for (const id of ["zsh", "fzf", "git", "gh", "tmux"]) {
        expect(selected[id]).toBe(true);
      }
    }
  });

  test("toggleable rows follow value.includes(id), never context flags", () => {
    const selected = adaptStepOne(["ghostty", "opencode"], fixtureContext);
    expect(selected["ghostty"]).toBe(true);
    expect(selected["opencode"]).toBe(true);
    // Default/installed flags are a component pre-check concern; the adapter
    // must NOT reinsert rows the user un-checked (former defaults CAN be off).
    expect(selected["lazygit"]).toBe(false);
    expect(selected["7zip"]).toBe(false);
    expect(selected["brave-browser"]).toBe(false);
  });

  test("special installers are ordinary toggleable rows: absent -> false, present -> true", () => {
    const empty = adaptStepOne([], fixtureContext);
    for (const id of ["code", "duti-defaults", "dock", "macos"]) {
      expect(empty[id]).toBe(false);
    }
    const chosen = adaptStepOne(["dock", "code"], fixtureContext);
    expect(chosen["dock"]).toBe(true);
    expect(chosen["code"]).toBe(true);
    expect(chosen["duti-defaults"]).toBe(false);
    expect(chosen["macos"]).toBe(false);
  });
});

describe("adaptStepTwo", () => {
  test("one true key per element name", () => {
    expect(adaptStepTwo(["ghostty", "hunk"])).toEqual({
      ghostty: true,
      hunk: true,
    });
  });

  test("multi-target name is exactly ONE key (never per-target rows)", () => {
    const checked = adaptStepTwo(["ghostty"]);
    expect(checked).toEqual({ ghostty: true });
    expect(Object.keys(checked)).toHaveLength(1);
  });

  test("empty value -> empty checked map", () => {
    expect(adaptStepTwo([])).toEqual({});
  });
});

describe("toggleableRowsForStep", () => {
  test("never returns locked or pseudo rows (ADR-1: never component options)", () => {
    const ids = toggleableRowsForStep(fixtureContext).map((r) => r.id);
    for (const id of [
      "zsh-setup",
      "git-signing",
      "zsh",
      "fzf",
      "git",
      "gh",
      "tmux",
    ]) {
      expect(ids).not.toContain(id);
    }
  });

  test("is exactly toolRowsGrouped minus locked/pseudo rows, order preserved", () => {
    const rows = toggleableRowsForStep(fixtureContext);
    const ids = rows.map((r) => r.id);
    for (const id of [
      "ghostty",
      "lazygit",
      "hunk",
      "yazi",
      "code",
      "duti-defaults",
      "dock",
      "macos",
      "opencode",
      "stupside/tap/castor",
      "brave-browser",
      "7zip",
    ]) {
      expect(ids).toContain(id);
    }
    const groupedToggleable = toolRowsGrouped(fixtureContext)
      .filter((r) => !r.locked && !r.pseudo)
      .map((r) => r.id);
    expect(ids).toEqual(groupedToggleable);
  });
});

describe("defaultValuesFor", () => {
  test("pre-checks default+installed TOGGLEABLE rows only (never locked/pseudo)", () => {
    const defaults = defaultValuesFor(fixtureContext);
    for (const id of ["ghostty", "lazygit", "hunk", "yazi", "7zip"]) {
      expect(defaults).toContain(id);
    }
    for (const id of ["opencode", "code", "dock", "macos", "brave-browser"]) {
      expect(defaults).not.toContain(id);
    }
    // Locked/pseudo rows are never option values, even though pseudo-steps
    // carry default:true in toolRows.
    expect(defaults).not.toContain("fzf");
    expect(defaults).not.toContain("zsh-setup");
  });

  test("initialSelected seam adds extras on top of defaults", () => {
    const defaults = defaultValuesFor(fixtureContext, {
      opencode: true,
      code: true,
    });
    expect(defaults).toContain("opencode");
    expect(defaults).toContain("code");
    expect(defaults).toContain("ghostty");
    // false entries in the seam do not add rows.
    const negative = defaultValuesFor(fixtureContext, { opencode: false });
    expect(negative).not.toContain("opencode");
  });
});

describe("quitRequested", () => {
  test("plain q and ctrl+c request a quit (ADR-2 App quit-only contract)", () => {
    expect(quitRequested("q", {})).toBe(true);
    expect(quitRequested("c", { ctrl: true })).toBe(true);
  });

  test("arrows, space, return, uppercase Q, ctrl+other and meta+q never quit", () => {
    expect(quitRequested("", { upArrow: true })).toBe(false);
    expect(quitRequested("", { downArrow: true })).toBe(false);
    expect(quitRequested(" ", {})).toBe(false);
    expect(quitRequested("", { return: true })).toBe(false);
    expect(quitRequested("Q", {})).toBe(false);
    expect(quitRequested("x", { ctrl: true })).toBe(false);
    expect(quitRequested("q", { meta: true })).toBe(false);
    expect(quitRequested("", { escape: true })).toBe(false);
  });
});

describe("adapter boundaries (TRIANGULATE)", () => {
  test("adaptStepOne([], context) keeps the essentials on: nothing selected = locked block only", () => {
    const selected = adaptStepOne([], fixtureContext);
    for (const id of [
      "zsh-setup",
      "git-signing",
      "zsh",
      "fzf",
      "git",
      "gh",
      "tmux",
    ]) {
      expect(selected[id]).toBe(true);
    }
    expect(selected["ghostty"]).toBe(false);
    // The map covers exactly the tool row set: no orphans, no tap rows.
    expect(Object.keys(selected).sort()).toEqual(
      toolRowsGrouped(fixtureContext)
        .map((r) => r.id)
        .sort(),
    );
  });

  test("adaptStepTwo round-trips: duplicate names collapse to one idempotent key", () => {
    expect(adaptStepTwo(["ghostty", "ghostty", "hunk"])).toEqual({
      ghostty: true,
      hunk: true,
    });
  });

  test("un-checked defaults stay off through the adapter (defaults CAN be removed)", () => {
    const allToggleable = toggleableRowsForStep(fixtureContext).map(
      (r) => r.id,
    );
    const minusGhostty = allToggleable.filter((id) => id !== "ghostty");
    const selected = adaptStepOne(minusGhostty, fixtureContext);
    expect(selected["ghostty"]).toBe(false);
    expect(selected["lazygit"]).toBe(true);
    expect(selected["fzf"]).toBe(true);
  });
});

afterEach(() => {
  cleanup();
});

// ---------------------------------------------------------------------------
// initialState — locked and pseudo-step rows start checked and stay non-togg
// ---------------------------------------------------------------------------

describe("initialState", () => {
  test("locked rows and pseudo-steps start selected; defaults pre-checked; rest off", () => {
    const state = initialState(fixtureContext);
    expect(state.step).toBe(1);
    expect(state.selected["zsh-setup"]).toBe(true);
    expect(state.selected["git-signing"]).toBe(true);
    expect(state.selected["fzf"]).toBe(true);
    expect(state.selected["git"]).toBe(true);
    expect(state.selected["tmux"]).toBe(true);
    // Former baseline rows pre-checked…
    expect(state.selected["ghostty"]).toBe(true);
    expect(state.selected["lazygit"]).toBe(true);
    // …ordinary rows start off.
    expect(state.selected["opencode"]).toBe(false);
    // Topic delegating rows (code/duti-defaults) are first-class step-1 rows
    // now: present and unchecked, never step-2 extras.
    expect(state.selected["code"]).toBe(false);
    expect(state.selected["duti-defaults"]).toBe(false);
    expect(state.checked).toEqual({});
  });
});

// ---------------------------------------------------------------------------
// Step 1 view — locked block, topic grouping, special rows
// ---------------------------------------------------------------------------

describe("toolView (step 1)", () => {
  test("locked essentials render pinned at top with a 🔒 marker", () => {
    const view = toolView(initialState(fixtureContext), fixtureContext);
    const lockedIdx = view.indexOf("🔒");
    const zshIdx = view.indexOf("Zinit/Zsh setup");
    const fzfIdx = view.indexOf("fzf");
    expect(lockedIdx).toBeGreaterThanOrEqual(0);
    // Pseudo-steps and locked rows come before the first topic group header.
    expect(view.indexOf("[core]")).toBeGreaterThan(zshIdx);
    expect(fzfIdx).toBeLessThan(view.indexOf("[core]"));
    // Locked rows are always checked.
    expect(view).toContain("[x] fzf");
  });

  test("topic groups render from categories; code/duti-defaults are step-1 rows under Editors/System", () => {
    // Tall viewport: initialState's 24-row default clips the bottom groups.
    const state = { ...initialState(fixtureContext), height: 200 };
    const view = toolView(state, fixtureContext);
    for (const group of [
      "[core]",
      "[git]",
      "[file]",
      "[ai]",
      "[media]",
      "[Browsers]",
      "[Editors]",
      "[System]",
    ]) {
      expect(view).toContain(group);
    }
    // The delegating installs appear in the main selector now.
    expect(view).toContain("[ ] code");
    expect(view).toContain("[ ] duti-defaults");
  });

  test("a category header never repeats, even when its rows are non-contiguous in context order (7zip is topic 'core', declared after Browsers)", () => {
    const view = toolView(initialState(fixtureContext), fixtureContext);
    const coreOccurrences = view.split("[core]").length - 1;
    expect(coreOccurrences).toBe(1);
  });

  test("default rows start checked; unselected rows show empty marks", () => {
    // Tall viewport: initialState's 24-row default clips the bottom groups.
    const state = { ...initialState(fixtureContext), height: 200 };
    const view = toolView(state, fixtureContext);
    expect(view).toContain("[x] ghostty");
    expect(view).toContain("[x] lazygit");
    expect(view).toContain("[ ] opencode");
  });

  test("installed:true rows are pre-checked even when default is false", () => {
    const state = initialState(fixtureContext);
    expect(state.selected["7zip"]).toBe(true);
    expect(state.selected["opencode"]).toBe(false);
  });

  test("category headers group rows and tap-qualified rows render their label", () => {
    const state = { ...initialState(fixtureContext), height: 200 };
    const view = toolView(state, fixtureContext);
    expect(view).toContain("[Browsers]");
    // The tap-qualified cask renders its simple label, never the qualified id.
    expect(view).toContain("[ ] castor");
    expect(view).not.toContain("stupside/tap/castor");
    expect(view).toContain("[ ] brave-browser");
  });
});

describe("reducer toggling (step 1)", () => {
  const at = (partial: Partial<TuiState>): TuiState => ({
    ...initialState(fixtureContext),
    ...partial,
  });

  test("locked rows ignore the toggle key entirely", () => {
    // fzf sits at row index 2 (two pseudo-steps, then fzf, git, tmux).
    let state = at({ step: 1, cursor: 2 });
    state = reducer(state, key("space"), fixtureContext);
    expect(state.selected["fzf"]).toBe(true);
    // Pseudo-steps are locked too.
    state = at({ step: 1, cursor: 0 });
    state = reducer(state, key("space"), fixtureContext);
    expect(state.selected["zsh-setup"]).toBe(true);
  });

  test("sibling rows in one topic group toggle independently", () => {
    let state = at({ step: 1, cursor: rowIndex("lazygit") });
    state = reducer(state, key("space"), fixtureContext); // lazygit off
    expect(state.selected["lazygit"]).toBe(false);
    expect(state.selected["hunk"]).toBe(true); // sibling untouched
    state = at({ step: 1, cursor: rowIndex("opencode") });
    state = reducer(state, key("space"), fixtureContext); // opencode on
    expect(state.selected["opencode"]).toBe(true);
    expect(state.selected["brave-browser"]).toBe(false); // different group untouched
  });

  test("former-baseline rows start checked and CAN be unchecked", () => {
    let state = at({ step: 1, cursor: rowIndex("ghostty") });
    state = reducer(state, key("space"), fixtureContext);
    expect(state.selected["ghostty"]).toBe(false);
  });

  test("up/down navigation clamps at both edges", () => {
    let state = at({ step: 1, cursor: 0 });
    state = reducer(state, key("up"), fixtureContext);
    expect(state.cursor).toBe(0);
    state = reducer(state, key("down"), fixtureContext);
    expect(state.cursor).toBe(1);
  });

  test("enter moves to step 2; space there is inert for tools", () => {
    let state = at({ step: 1, cursor: 0 });
    state = reducer(state, key("enter"), fixtureContext);
    expect(state.step).toBe(2);
    expect(state.cursor).toBe(0);
  });

  test("resize records dimensions", () => {
    const state = reducer(
      initialState(fixtureContext),
      resize(80, 24),
      fixtureContext,
    );
    expect(state.width).toBe(80);
    expect(state.height).toBe(24);
  });
});

// ---------------------------------------------------------------------------
// Step 2 view — filtered links + opt-in agents, multi-target single row
// ---------------------------------------------------------------------------

describe("linkView (step 2)", () => {
  test("multi-target link name renders as ONE row; no opt-in agents group", () => {
    const state: TuiState = { ...initialState(fixtureContext), step: 2 };
    const view = linkView(state, fixtureContext);
    // ghostty appears exactly once as a row label (its two targets collapse).
    expect(view).toContain("ghostty");
    expect(view).not.toContain("ghostty.conf");
    // The opt-in agents group was removed; step 2 is pure config links.
    expect(view).not.toContain("opt-in AI agents");
    expect(view).not.toContain("[ ] agents");
    // Multi-target label names its target count.
    expect(view).toContain("ghostty (2 targets)");
  });

  test("offered links and agents all start unchecked", () => {
    const state: TuiState = { ...initialState(fixtureContext), step: 2 };
    const view = linkView(state, fixtureContext);
    expect(view).not.toContain("[x]");
  });
});

describe("toggleLink (step 2)", () => {
  test("toggling a multi-target name flips the whole entry once", () => {
    const before: TuiState = { ...initialState(fixtureContext), step: 2 };
    const after = toggleLink(before, "ghostty");
    expect(after.checked["ghostty"]).toBe(true);
    const twice = toggleLink(after, "ghostty");
    expect(twice.checked["ghostty"]).toBe(false);
  });

  test("toggling one link never touches the others", () => {
    let state: TuiState = { ...initialState(fixtureContext), step: 2 };
    state = toggleLink(state, "zsh");
    expect(state.checked).toEqual({ zsh: true });
  });

  test("step-2 space routes through toggleLink on the cursor row", () => {
    // Step-2 row order: main list first (zsh, ghostty, hunk, lazygit), then
    // agents (agents). Cursor 1 = ghostty.
    let state: TuiState = {
      ...initialState(fixtureContext),
      step: 2,
      cursor: 1,
    };
    state = reducer(state, key("space"), fixtureContext);
    expect(state.checked["ghostty"]).toBe(true);
    expect(state.checked).not.toHaveProperty("zsh");
  });

  test("enter submits (applies) from step 2", () => {
    let state: TuiState = { ...initialState(fixtureContext), step: 2 };
    state = reducer(state, key("enter"), fixtureContext);
    expect(state.submitted).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// mapInkKey (unchanged vocabulary)
// ---------------------------------------------------------------------------

describe("mapInkKey", () => {
  test("maps Ink input pairs onto the key vocabulary", () => {
    expect(mapInkKey("", { upArrow: true })).toEqual({ key: "up" });
    expect(mapInkKey("", { downArrow: true })).toEqual({ key: "down" });
    expect(mapInkKey("", { return: true })).toEqual({ key: "enter" });
    expect(mapInkKey(" ", {})).toEqual({ key: "space" });
    expect(mapInkKey("q", {})).toEqual({ key: "q" });
    expect(mapInkKey("c", { ctrl: true })).toEqual({ key: "ctrl+c" });
  });
});

// ---------------------------------------------------------------------------
// Frame tests via ink-testing-library (tasks 2.5–2.6)
// ---------------------------------------------------------------------------

describe("frame: two-step flow", () => {
  test("step 1 renders the locked 🔒 block and topic groups", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    const frame = ui.lastFrame() ?? "";
    expect(frame).toContain("step 1/2");
    expect(frame).toContain("🔒");
    expect(frame).toContain("Zinit/Zsh setup");
    expect(frame).toContain("[x] fzf");
    expect(frame).toContain("[x] ghostty");
    expect(frame).toContain("[ ] opencode");
    expect(frame).toContain("space toggle  enter next  q quit");
    ui.unmount();
  });

  test("space on a locked row leaves the frame byte-identical (no toggle)", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    await press(ui, " "); // cursor starts on Zinit/Zsh setup (locked)
    expect(ui.lastFrame()).toContain("[x] Zinit/Zsh setup");
    await press(ui, KEY_DOWN); // git signing (locked)
    await press(ui, KEY_DOWN); // fzf (locked)
    const before = ui.lastFrame() ?? "";
    await press(ui, " ");
    expect(ui.lastFrame() ?? "").not.toContain("[ ] fzf");
    expect(ui.lastFrame()).toBe(before);
    ui.unmount();
  });

  test("enter advances to step 2 with every link row unchecked", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    await press(ui, KEY_ENTER);
    const frame = ui.lastFrame() ?? "";
    expect(frame).toContain("step 2/2");
    for (const name of ["zsh", "ghostty", "hunk", "lazygit"]) {
      expect(frame).toContain(name);
    }
    expect(frame).toContain("[ ] zsh");
    expect(frame).not.toContain("[ ] opencode"); // ai area inactive
    // Step 2 is pure config links now: no opt-in agents, no extras.
    expect(frame).not.toContain("opt-in AI agents");
    expect(frame).not.toContain("extra installs");
    expect(frame).toContain("space toggle  enter apply  q quit");
    // Multi-target renders once.
    expect((frame.match(/ghostty/g) ?? []).length).toBeGreaterThanOrEqual(1);
    expect(frame).not.toContain("ghostty.conf");
    ui.unmount();
  });

  test("a checked multi-target link submits both targets as one name", async () => {
    let submitted: TuiState | null = null;
    const ui = render(
      <App
        context={fixtureContext}
        fixedSize={TALL}
        onSubmit={(s) => {
          submitted = s;
        }}
      />,
    );
    await delay(20);
    await press(ui, KEY_ENTER); // step 2
    await press(ui, KEY_DOWN); // cursor -> ghostty
    await press(ui, " ");
    await press(ui, KEY_ENTER);
    await delay(30);
    expect(submitted).not.toBeNull();
    expect(submitted!.checked["ghostty"]).toBe(true);
    ui.unmount();
  });

  test("q quits from step 1 without submitting", async () => {
    let submitted = false;
    const ui = render(
      <App
        context={fixtureContext}
        fixedSize={TALL}
        onSubmit={() => (submitted = true)}
      />,
    );
    await delay(20);
    await press(ui, "q");
    await delay(30);
    expect(submitted).toBe(false);
    ui.unmount();
  });

  test("q quits from step 2 without submitting", async () => {
    let submitted = false;
    const ui = render(
      <App
        context={fixtureContext}
        fixedSize={TALL}
        onSubmit={() => (submitted = true)}
      />,
    );
    await delay(20);
    await press(ui, KEY_ENTER);
    await press(ui, "q");
    await delay(30);
    expect(submitted).toBe(false);
    ui.unmount();
  });
});
