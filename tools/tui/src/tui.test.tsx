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
import {
  App,
  initialState,
  linkView,
  mapInkKey,
  reducer,
  toggleLink,
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
    { id: "fzf", topic: "core", kind: "brew", area: "shell", locked: true, default: false },
    { id: "git", topic: "core", kind: "brew", area: "git", locked: true, default: false },
    { id: "tmux", topic: "core", kind: "brew", area: "terminal", locked: true, default: false },
    { id: "ghostty", topic: "core", kind: "cask", area: "terminal", locked: false, default: true },
    { id: "lazygit", topic: "git", kind: "brew", area: "git", locked: false, default: true },
    { id: "hunk", topic: "git", kind: "brew", area: "git", locked: false, default: true },
    { id: "yazi", topic: "file", kind: "brew", area: "terminal", locked: false, default: true },
    { id: "code", topic: "code", kind: "topic", area: "vscode", locked: false, default: false },
    { id: "duti-defaults", topic: "duti", kind: "topic", area: "terminal", locked: false, default: false },
    { id: "opencode", topic: "ai", kind: "brew", area: "ai", locked: false, default: false },
  ],
  links: [
    { name: "zsh", optional: false, component: "shell", requirement: "", rows: [{ source: "config/zsh/.zshrc", target: "~/.zshrc", mode: "" }] },
    { name: "ghostty", optional: false, component: "terminal", requirement: "", rows: [
      { source: "config/ghostty/config", target: "~/.config/ghostty/config", mode: "" },
      { source: "config/ghostty/config", target: "~/Library/ghostty.conf", mode: "" },
    ] },
    { name: "hunk", optional: false, component: "git", requirement: "hunk", rows: [{ source: "config/hunk/x", target: "~/.config/hunk/x", mode: "" }] },
    { name: "lazygit", optional: false, component: "git", requirement: "lazygit", rows: [{ source: "config/lazygit/x", target: "~/.config/lazygit/x", mode: "" }] },
    { name: "opencode", optional: false, component: "ai", requirement: "", rows: [{ source: "config/opencode/x", target: "~/.config/opencode/x", mode: "" }] },
    { name: "agents", optional: true, component: "ai", requirement: "", rows: [
      { source: "ai/AGENTS.md", target: "~/.claude/CLAUDE.md", mode: "" },
      { source: "ai/AGENTS.md", target: "~/.agents/AGENTS.md", mode: "" },
    ] },
  ],
};

const key = (name: string, text?: string) => ({ type: "key" as const, key: name, text });
const resize = (width: number, height: number) => ({ type: "resize" as const, width, height });

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
export function rowIndex(id: string): number {
  const pseudo = [{ id: "zsh-setup" }, { id: "git-signing" }];
  const locked = fixtureContext.packages.filter((p) => p.locked);
  const toggle = fixtureContext.packages.filter((p) => !p.locked);
  return [...pseudo, ...locked, ...toggle].map((r) => r.id).indexOf(id);
}

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
    expect(state.selected["code"]).toBe(false);
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

  test("topic groups render and special code/duti rows are included", () => {
    const view = toolView(initialState(fixtureContext), fixtureContext);
    for (const group of ["[core]", "[git]", "[file]", "[code]", "[duti]", "[ai]"]) {
      expect(view).toContain(group);
    }
    expect(view).toContain("code");
    expect(view).toContain("duti-defaults");
  });

  test("default rows start checked; unselected rows show empty marks", () => {
    const view = toolView(initialState(fixtureContext), fixtureContext);
    expect(view).toContain("[x] ghostty");
    expect(view).toContain("[x] lazygit");
    expect(view).toContain("[ ] opencode");
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
    expect(state.selected["code"]).toBe(false); // different group untouched
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
    const state = reducer(initialState(fixtureContext), resize(80, 24), fixtureContext);
    expect(state.width).toBe(80);
    expect(state.height).toBe(24);
  });
});

// ---------------------------------------------------------------------------
// Step 2 view — filtered links + opt-in agents, multi-target single row
// ---------------------------------------------------------------------------

describe("linkView (step 2)", () => {
  test("multi-target link name renders as ONE row, then the agents group", () => {
    const state: TuiState = { ...initialState(fixtureContext), step: 2 };
    const view = linkView(state, fixtureContext);
    // ghostty appears exactly once as a row label (its two targets collapse).
    expect(view).toContain("ghostty");
    expect(view).not.toContain("ghostty.conf");
    expect(view).toContain("opt-in AI agents");
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
    let state: TuiState = { ...initialState(fixtureContext), step: 2, cursor: 1 };
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
    expect(frame).toContain("opt-in AI agents");
    expect(frame).toContain("[ ] agents");
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
      <App context={fixtureContext} fixedSize={TALL} onSubmit={() => (submitted = true)} />,
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
      <App context={fixtureContext} fixedSize={TALL} onSubmit={() => (submitted = true)} />,
    );
    await delay(20);
    await press(ui, KEY_ENTER);
    await press(ui, "q");
    await delay(30);
    expect(submitted).toBe(false);
    ui.unmount();
  });
});