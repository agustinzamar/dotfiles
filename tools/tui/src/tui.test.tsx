// Phase 2 (tasks 2.1–2.5, RED first): component frame tests for the two-step
// flow on @inkjs/ui MultiSelect (design §2/§6). Step 1 renders an inert
// always-checked locked block ABOVE the component (ADR-1: locked rows are
// never options), toggleable rows as pre-checked-by-default options that CAN
// be unchecked. Step 2 lists ONLY the offered .main config links (ADR-4), all
// unchecked at mount; space toggles, enter submits the checked set; multi-target
// names are ONE row (value = name). Quit (q / ctrl+c) is App-owned on both
// steps and NEVER reaches onSubmit — main.ts maps that to exit 10 with zero
// writes (roundExitCode contract lives in main.test.ts, untouched).
// Frame technique mirrors apply.test.tsx: chalk.level=1 at module top,
// ink-testing-library, stripAnsi for words, color-close/label assertions
// (never a bare \x1b[0m), afterEach(cleanup), fixedSize tall.
import { afterEach, describe, expect, test } from "bun:test";
import chalk from "chalk";
import { cleanup, render } from "ink-testing-library";
import type { InstallContext } from "./context";
import { toolRowsGrouped } from "./manifest";
import {
  adaptStepOne,
  adaptStepTwo,
  App,
  defaultValuesFor,
  initialState,
  linkRowsForStep,
  quitRequested,
  stepTwoRows,
  toggleableRowsForStep,
  visibleOptionsFor,
  type TuiState,
} from "./tui";

// The test worker disables color detection, but the point of these frame tests
// is asserting ink's RENDERED style closes. Force chalk level 1 so @inkjs/ui/
// ink emit real codes — same technique as apply.test.tsx.
chalk.level = 1;

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

/** ADR-5 fixture: a context with no config links at all — step 2 must still
 *  mount with zero options and confirm on enter with checked = {}. */
const emptyLinksContext: InstallContext = {
  ...fixtureContext,
  links: [],
};

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type Instance = ReturnType<typeof render>;

const press = async (ui: Instance, data: string) => {
  ui.stdin.write(data);
  await delay(10);
};

const KEY_ENTER = "\r";
const KEY_DOWN = "\x1b[B";
const KEY_UP = "\x1b[A";
const KEY_CTRL_C = "\x03";

const TALL = { width: 100, height: 60 };

/** Visible-text helper: strips every ANSI escape so text assertions never
 *  depend on style codes (apply.test.tsx technique). */
function stripAnsi(frame: string): string {
  return frame.replace(/\x1b\[[0-9;]*m/g, "");
}

/** Exact locked-block line (`✔ <label>`, no padding, our own static glyph —
 *  never a figures glyph, so it is portable across TERM settings). */
function lockedLine(frame: string, label: string): string | null {
  return (
    stripAnsi(frame)
      .split("\n")
      .find((line) => line === `✔ ${label}`) ?? null
  );
}

/** Exact unfocused option line (`  <label> ✔` when checked, `  <label>` when
 *  not). Only unfocused rows are matchable portably: the focused row renders
 *  with figures' pointer glyph (❯ or ASCII fallback). */
function optionLine(frame: string, label: string): string | null {
  return (
    stripAnsi(frame)
      .split("\n")
      .find((line) => line === `  ${label}` || line === `  ${label} ✔`) ?? null
  );
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

describe("visibleOptionsFor", () => {
  test("fills the available height minus the reserved chrome, clamped to [3, 20]", () => {
    // Step 1 reserves header + locked block + hint + margin (2+4+1 = 7).
    expect(visibleOptionsFor(25, 1, 4)).toBe(18);
    // Step 2 reserves header + hint + margin (3).
    expect(visibleOptionsFor(20, 2, 0)).toBe(17);
  });

  test("small terminals clamp to a minimum of 3", () => {
    expect(visibleOptionsFor(4, 1, 5)).toBe(3);
    expect(visibleOptionsFor(3, 2, 0)).toBe(3);
  });

  test("huge terminals cap at 20 visible options", () => {
    expect(visibleOptionsFor(200, 2, 0)).toBe(20);
    expect(visibleOptionsFor(200, 1, 0)).toBe(20);
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
// initialState — trimmed shape { step, selected, checked, submitted }; locked
// and pseudo-step rows start checked, defaults pre-checked, rest off.
// ---------------------------------------------------------------------------

describe("initialState", () => {
  test("slims to { step, selected, checked, submitted } (cursor/viewport bookkeeping deleted)", () => {
    expect(Object.keys(initialState(fixtureContext)).sort()).toEqual([
      "checked",
      "selected",
      "step",
      "submitted",
    ]);
  });

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
// linkRowsForStep / stepTwoRows — surviving Phase-1 shaping functions keep
// their own coverage now that the string views (linkView/toggleLink) are gone.
// ---------------------------------------------------------------------------

describe("linkRowsForStep / stepTwoRows shaping", () => {
  const atStep2 = (state: TuiState): TuiState => ({ ...state, step: 2 });

  test("stepTwoRows is .main only: offered links for confirmed areas, never the agents group", () => {
    const state = atStep2(initialState(fixtureContext));
    const grouped = linkRowsForStep(fixtureContext, state);
    expect(grouped.main.map((l) => l.name)).toEqual([
      "zsh",
      "ghostty",
      "hunk",
      "lazygit",
    ]);
    // offeredLinks keeps the optional group (manifest untouched)…
    expect(grouped.agents.map((l) => l.name)).toEqual(["agents"]);
    // …while stepTwoRows prunes it for rendering (ADR-4).
    expect(stepTwoRows(fixtureContext, state).map((l) => l.name)).toEqual([
      "zsh",
      "ghostty",
      "hunk",
      "lazygit",
    ]);
  });

  test("ADR-4: open-code and unselected areas never reach step 2", () => {
    const names = stepTwoRows(
      fixtureContext,
      atStep2(initialState(fixtureContext)),
    ).map((l) => l.name);
    expect(names).not.toContain("opencode");
    expect(names).not.toContain("agents");
  });

  test("multi-target links remain ONE entry whose name is the toggle unit", () => {
    const rows = stepTwoRows(
      fixtureContext,
      atStep2(initialState(fixtureContext)),
    );
    const ghostty = rows.find((l) => l.name === "ghostty");
    expect(ghostty).toBeDefined();
    expect(ghostty!.rows).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
// Step 1 component frame — inert locked block above the MultiSelect (ADR-1),
// pre-checked defaults that CAN be unchecked, per-row space toggles.
// ---------------------------------------------------------------------------

describe("step-1 frame (MultiSelect + locked block)", () => {
  test("renders the header, the inert ✔ locked block, and the component options", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    const frame = ui.lastFrame() ?? "";
    const text = stripAnsi(frame);
    expect(text).toContain("step 1/2");
    expect(text).toContain(
      "↑/↓ navigate · space toggle · enter submit · q quit",
    );
    for (const label of [
      "Zinit/Zsh setup",
      "Git signing config",
      "fzf",
      "git",
      "tmux",
      "zsh",
      "gh",
    ]) {
      expect(lockedLine(frame, label)).toBe(`✔ ${label}`);
    }
    // Toggleable rows render as component options — no string-view markup.
    // (ghostty is the FOCUSED row at mount, so it is asserted via its blue
    // label in the next describe; optionLine only matches unfocused rows.)
    for (const label of ["7zip", "lazygit", "hunk", "yazi"]) {
      expect(optionLine(frame, label)).not.toBeNull();
    }
    expect(text).not.toContain("[x]");
    expect(text).not.toContain("[ ]");
    expect(text).not.toContain("[core]");
    expect(text).not.toContain("🔒");
    ui.unmount();
  });

  test("former defaults render pre-checked (green labels) and can be unchecked; locked rows are never options", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    const frame = ui.lastFrame() ?? "";
    // Focused default (ghostty) renders blue; unfocused defaults render green.
    expect(frame).toContain("\x1b[34mghostty\x1b[39m");
    for (const label of ["lazygit", "hunk", "yazi", "7zip"]) {
      expect(frame).toContain(`\x1b[32m${label}\x1b[39m`);
    }
    // Unchecked rows render plain — never green.
    for (const label of ["opencode", "code", "brave-browser"]) {
      expect(frame).not.toContain(`\x1b[32m${label}\x1b[39m`);
    }
    // Ghostty starts checked: its green tick is in the frame.
    expect(frame).toContain("\x1b[32m✔\x1b[39m");
    // Locked ids never appear in the option list (ADR-1): no option row for
    // fzf/zsh (the ✔ fzf line is the inert block, which is NOT an option).
    expect(optionLine(frame, "fzf")).toBeNull();
    expect(optionLine(frame, "zsh")).toBeNull();
    ui.unmount();
  });

  test("space toggles the focused option only; sibling rows stay byte-identical", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    await press(ui, KEY_DOWN); // 7zip
    await press(ui, KEY_DOWN); // lazygit (focused, blue)
    const a = ui.lastFrame() ?? "";
    expect(a).toContain("\x1b[34mlazygit\x1b[39m");
    await press(ui, " "); // lazygit OFF (still focused -> blue, tick gone)
    const b = ui.lastFrame() ?? "";
    expect(b).toContain("\x1b[34mlazygit\x1b[39m");
    expect(b).not.toContain("\x1b[32mlazygit\x1b[39m");
    await press(ui, KEY_DOWN); // hunk
    await press(ui, KEY_DOWN); // yazi focused; lazygit now unfocused+unselected
    const c = ui.lastFrame() ?? "";
    expect(c).not.toContain("\x1b[32mlazygit\x1b[39m");
    expect(c).not.toContain("\x1b[34mlazygit\x1b[39m");
    // Sibling rows' lines are byte-identical across the whole interaction
    // (the always-unfocused trio; the trio is focused in none of a/b/c).
    for (const frame of [a, b, c]) {
      expect(optionLine(frame, "ghostty")).toBe("  ghostty ✔");
      expect(optionLine(frame, "7zip")).toBe("  7zip ✔");
      expect(optionLine(frame, "hunk")).toBe("  hunk ✔");
    }
    expect(c).toContain("\x1b[34myazi\x1b[39m");
    expect(c).toContain("\x1b[32mhunk\x1b[39m");
    ui.unmount();
  });

  test("the locked block is inert: its lines stay byte-identical through toggles and navigation", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    const before = ui.lastFrame() ?? "";
    const labels = [
      "Zinit/Zsh setup",
      "Git signing config",
      "fzf",
      "git",
      "tmux",
      "zsh",
      "gh",
    ];
    for (const label of labels) {
      expect(lockedLine(before, label)).toBe(`✔ ${label}`);
    }
    // Space always acts on the component's focused OPTION (never a locked
    // row), so pressing it repeatedly and moving around must not disturb the
    // locked block: it never loses a check, never toggles.
    await press(ui, " "); // ghostty off (focused default)
    await press(ui, KEY_DOWN);
    await press(ui, " ");
    await press(ui, KEY_DOWN);
    await press(ui, KEY_DOWN);
    await press(ui, " ");
    await press(ui, KEY_UP);
    await press(ui, KEY_UP);
    const after = ui.lastFrame() ?? "";
    for (const label of labels) {
      expect(lockedLine(after, label)).toBe(`✔ ${label}`);
    }
    ui.unmount();
  });
});

// ---------------------------------------------------------------------------
// Step 2 component frame — ADR-4 pruned .main options, all unchecked at mount,
// space toggles, enter submits, multi-target = ONE row; quit frames for both
// steps keep onSubmit silent (exit-10 zero-writes, ADR-2).
// ---------------------------------------------------------------------------

const atStep2 = async (ui: Instance) => {
  await press(ui, KEY_ENTER); // submit step 1 -> mounts step 2
};

describe("step-2 frame (MultiSelect, ADR-4 pruned links)", () => {
  test("options are the offered .main links only: agents / open-code / unselected areas absent", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    await atStep2(ui);
    const frame = ui.lastFrame() ?? "";
    const text = stripAnsi(frame);
    expect(text).toContain("step 2/2");
    expect(text).toContain(
      "↑/↓ navigate · space toggle · enter apply · q quit",
    );
    for (const label of ["zsh", "ghostty (2 targets)", "hunk", "lazygit"]) {
      expect(text).toContain(label);
    }
    expect(text).not.toContain("opencode");
    expect(text).not.toContain("agents");
    expect(text).not.toContain("opt-in AI agents");
    ui.unmount();
  });

  test("every link row starts unchecked at mount; the focused row is the blue target", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    await atStep2(ui);
    const frame = ui.lastFrame() ?? "";
    // First option (zsh) is focused -> blue label, NO green anywhere: all rows
    // start unchecked (defaultValue = []).
    expect(frame).toContain("\x1b[34mzsh\x1b[39m");
    expect(frame).not.toContain("\x1b[32m");
    ui.unmount();
  });

  test("space toggles a link row; enter submits the checked set; multi-target name is ONE row", async () => {
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
    await atStep2(ui);
    await press(ui, KEY_DOWN); // ghostty focused
    await press(ui, " "); // ghostty checked
    await press(ui, KEY_DOWN); // hunk focused; ghostty unfocused+selected
    const frame = ui.lastFrame() ?? "";
    expect(frame).toContain("\x1b[32mghostty (2 targets)\x1b[39m");
    expect(frame).not.toContain("\x1b[32mhunk\x1b[39m");
    await press(ui, KEY_ENTER);
    await delay(30);
    expect(submitted).not.toBeNull();
    expect(submitted!.checked).toEqual({ ghostty: true });
    expect(submitted!.submitted).toBe(true);
    expect(submitted!.step).toBe(2);
    ui.unmount();
  });

  test("multi-target ghostty renders as ONE 'ghostty (2 targets)' row, value = name", async () => {
    const ui = render(<App context={fixtureContext} fixedSize={TALL} />);
    await delay(20);
    await atStep2(ui);
    const frame = ui.lastFrame() ?? "";
    expect(stripAnsi(frame).match(/ghostty \(2 targets\)/g)).toHaveLength(1);
    expect(stripAnsi(frame)).not.toContain("ghostty.conf");
    ui.unmount();
  });

  test("enter on an empty step-2 list still confirms with checked = {} (ADR-5)", async () => {
    let submitted: TuiState | null = null;
    const ui = render(
      <App
        context={emptyLinksContext}
        fixedSize={TALL}
        onSubmit={(s) => {
          submitted = s;
        }}
      />,
    );
    await delay(20);
    await atStep2(ui);
    // Zero options: no link rows render, only the header + hint lines.
    const frame = ui.lastFrame() ?? "";
    expect(stripAnsi(frame)).toContain("step 2/2");
    expect(optionLine(frame, "zsh")).toBeNull();
    await press(ui, KEY_ENTER);
    await delay(30);
    expect(submitted).not.toBeNull();
    expect(submitted!.checked).toEqual({});
    expect(submitted!.submitted).toBe(true);
    ui.unmount();
  });
});

describe("frame: quit before confirm submits nothing (exit-10 zero-writes)", () => {
  const renderWithSpy = () => {
    let submitted = false;
    const ui = render(
      <App
        context={fixtureContext}
        fixedSize={TALL}
        onSubmit={() => (submitted = true)}
      />,
    );
    return { ui, submitted: () => submitted };
  };

  test("q at step 1 quits without submitting", async () => {
    const { ui, submitted } = renderWithSpy();
    await delay(20);
    await press(ui, "q");
    await delay(30);
    expect(submitted()).toBe(false);
    ui.unmount();
  });

  test("q at step 2 (after step-1 submit, before confirm) quits without submitting", async () => {
    const { ui, submitted } = renderWithSpy();
    await delay(20);
    await atStep2(ui);
    await press(ui, "q");
    await delay(30);
    expect(submitted()).toBe(false);
    ui.unmount();
  });

  test("ctrl+c at step 1 quits without submitting", async () => {
    const { ui, submitted } = renderWithSpy();
    await delay(20);
    await press(ui, KEY_CTRL_C);
    await delay(30);
    expect(submitted()).toBe(false);
    ui.unmount();
  });

  test("ctrl+c at step 2 quits without submitting", async () => {
    const { ui, submitted } = renderWithSpy();
    await delay(20);
    await atStep2(ui);
    await press(ui, KEY_CTRL_C);
    await delay(30);
    expect(submitted()).toBe(false);
    ui.unmount();
  });
});

// ---------------------------------------------------------------------------
// TRIANGULATE (task 2.4) — full-flow submitted state: locked reinsertion,
// default/installed survive the adapter, quit paths leave no bridge to apply.
// ---------------------------------------------------------------------------

describe("two-step flow: adapted selection feeds the apply pipeline", () => {
  test("submitted state carries locked/pseudo ids true and the user's toggles", async () => {
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
    // Uncheck lazygit (a former default) at step 1.
    await press(ui, KEY_DOWN); // 7zip
    await press(ui, KEY_DOWN); // lazygit
    await press(ui, " "); // lazygit off
    await atStep2(ui);
    await press(ui, KEY_ENTER); // confirm step 2 (nothing checked)
    await delay(30);
    expect(submitted).not.toBeNull();
    const sel = submitted!.selected;
    for (const id of [
      "zsh-setup",
      "git-signing",
      "zsh",
      "fzf",
      "git",
      "gh",
      "tmux",
    ]) {
      expect(sel[id]).toBe(true);
    }
    expect(sel["ghostty"]).toBe(true); // pre-checked default kept
    expect(sel["7zip"]).toBe(true); // installed:true pre-checked
    expect(sel["lazygit"]).toBe(false); // user removed the former default
    expect(sel["opencode"]).toBe(false);
    expect(submitted!.checked).toEqual({});
    expect(submitted!.submitted).toBe(true);
    ui.unmount();
  });

  test("quit between step-1 submit and step-2 mount keeps onSubmit silent (exit 10, zero writes)", async () => {
    const { ui, submitted } = (() => {
      let submitted = false;
      const ui = render(
        <App
          context={fixtureContext}
          fixedSize={TALL}
          onSubmit={() => (submitted = true)}
        />,
      );
      return { ui, submitted: () => submitted };
    })();
    await delay(20);
    await atStep2(ui); // step 2 mounted (step-1 selection already adapted)
    await press(ui, "q");
    await delay(30);
    expect(submitted()).toBe(false);
    ui.unmount();
  });
});
