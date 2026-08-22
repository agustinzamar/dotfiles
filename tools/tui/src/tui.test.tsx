// Ports internal/installer/tui_test.go plus the dot-tui spec scenarios.
// Pure helpers and the reducer are tested directly (mirroring Go's
// model.Update-level tests); frame contracts are asserted through
// ink-testing-library against raw ANSI strings (ADR-2).
import { afterEach, describe, expect, test } from "bun:test";
import { cleanup, render } from "ink-testing-library";
import {
  activeCategory,
  ansiDim,
  ansiGreen,
  ansiReset,
  ansiReverse,
  ansiYellow,
  App,
  categoryOrder,
  clampViewport,
  counts,
  firstIndexInCategory,
  initialState,
  mapInkKey,
  profileOf,
  reducer,
  reviewRows,
  selectCategory,
  stateMark,
  visibleIndices,
  type TuiState,
} from "./tui";
import { COMPONENTS, type Component } from "./manifest";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const fixture: Component[] = [
  {
    id: "one-a",
    label: "Alpha",
    category: "One",
    default: false,
    required: false,
  },
  {
    id: "one-b",
    label: "Bravo",
    category: "One",
    default: true,
    required: true,
  },
  {
    id: "two-c",
    label: "Charlie",
    category: "Two",
    default: false,
    required: false,
  },
];

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

// Raw escape sequences the fake stdin must receive for named keys.
const KEY_TAB = "\t";
const KEY_ENTER = "\r";
const KEY_ESC = "\x1b";
const KEY_DOWN = "\x1b[B";

// Ink's renderer normalizes the raw ANSI resets emitted by the view functions
// into attribute-specific close codes, so frame assertions match those:
// colors close with ESC[39m, bold/dim with ESC[22m (verified empirically).
const CLOSE_COLOR = "\x1b[39m";
const CLOSE_MODE = "\x1b[22m";

afterEach(() => {
  // Unmounts every live instance from prior tests.
  cleanup();
});

// ---------------------------------------------------------------------------
// Pure helper ports (task 4.1)
// ---------------------------------------------------------------------------

describe("categoryOrder", () => {
  test("preserves manifest first-seen order and dedupes", () => {
    expect(categoryOrder(fixture)).toEqual(["One", "Two"]);
    expect(categoryOrder(COMPONENTS)).toEqual([
      "Base",
      "Shell",
      "Git",
      "Terminal",
      "PHP",
      "Services",
      "AI",
      "Editors",
      "Desktop",
      "Communication",
      "Media",
    ]);
  });
});

describe("visibleIndices", () => {
  test("returns every index in manifest order when not searching", () => {
    const state = initialState();
    expect(visibleIndices(state, COMPONENTS)).toEqual(
      COMPONENTS.map((_, i) => i),
    );
    expect(visibleIndices(state, fixture)).toEqual([0, 1, 2]);
  });

  test("filters by label substring case-insensitively while searching", () => {
    const state: TuiState = {
      ...initialState(),
      searching: true,
      query: "ALPH",
    };
    expect(visibleIndices(state, fixture)).toEqual([0]);
  });

  test("filters by category substring while searching", () => {
    const state: TuiState = {
      ...initialState(),
      searching: true,
      query: "two",
    };
    expect(visibleIndices(state, fixture)).toEqual([2]);
  });

  test("empty query matches everything; unmatched query returns []", () => {
    const emptyQuery: TuiState = {
      ...initialState(),
      searching: true,
      query: "",
    };
    expect(visibleIndices(emptyQuery, fixture)).toEqual([0, 1, 2]);
    const noMatch: TuiState = {
      ...initialState(),
      searching: true,
      query: "zzz",
    };
    expect(visibleIndices(noMatch, fixture)).toEqual([]);
  });
});

describe("firstIndexInCategory", () => {
  test("returns the first index of the category", () => {
    expect(firstIndexInCategory(COMPONENTS, "Shell")).toBe(1);
    // communication-discord sits at index 15 in both the Go and TS manifests.
    expect(firstIndexInCategory(COMPONENTS, "Communication")).toBe(15);
    expect(firstIndexInCategory(fixture, "Two")).toBe(2);
  });

  test("falls back to 0 for an unknown category", () => {
    expect(firstIndexInCategory(fixture, "Nope")).toBe(0);
  });
});

describe("clampViewport", () => {
  test("content fitting the viewport pins start at 0", () => {
    expect(clampViewport(3, 10, 5)).toBe(0);
  });

  test("centers the cursor and clamps at the bottom edge", () => {
    expect(clampViewport(0, 4, 20)).toBe(0);
    expect(clampViewport(10, 4, 20)).toBe(8);
    expect(clampViewport(19, 4, 20)).toBe(16);
  });
});

describe("counts", () => {
  test("separates selected, installed, and pending (applied excluded, required not pending)", () => {
    const state: TuiState = {
      ...initialState(fixture),
      selected: { "one-a": true, "one-b": true, "two-c": false },
      applied: { "two-c": true },
    };
    // one-a: selected, not required -> selected+pending
    // one-b: selected, required -> selected only
    // two-c: applied -> installed only
    expect(counts(state, fixture)).toEqual({
      selected: 2,
      installed: 1,
      pending: 1,
    });
  });

  test("defaults report zero installed and zero pending", () => {
    expect(counts(initialState(COMPONENTS), COMPONENTS)).toEqual({
      selected: 4,
      installed: 0,
      pending: 0,
    });
  });
});

describe("reviewRows", () => {
  test("lists only selected-not-applied grouped under category headers", () => {
    const state: TuiState = {
      ...initialState(fixture),
      selected: { "one-a": true, "one-b": true, "two-c": true },
      applied: { "two-c": true },
    };
    // one-b is required-selected but not applied -> still listed (selection view
    // mirrors Go: reviewRows filters on selected && !applied only).
    expect(reviewRows(state, fixture)).toEqual([
      "[One]",
      "   Alpha",
      "   Bravo",
    ]);
  });

  test("emits each category header once", () => {
    const state: TuiState = {
      ...initialState(COMPONENTS),
      selected: Object.fromEntries(
        COMPONENTS.filter((c) => c.category === "Desktop").map((c) => [
          c.id,
          true,
        ]),
      ),
    };
    const rows = reviewRows(state, COMPONENTS);
    expect(rows[0]).toBe("[Desktop]");
    expect(rows.filter((row: string) => row === "[Desktop]")).toHaveLength(1);
    expect(rows).toHaveLength(11); // header + 10 desktop components
  });
});

describe("stateMark", () => {
  test("green check for applied, yellow x for selected, blank otherwise", () => {
    const state: TuiState = {
      ...initialState(fixture),
      selected: { "one-a": true },
      applied: { "two-c": true },
    };
    const byId = Object.fromEntries(fixture.map((c) => [c.id, c]));
    expect(stateMark(state, byId["two-c"]!)).toBe(`${ansiGreen}✓${ansiReset}`);
    expect(stateMark(state, byId["one-a"]!)).toBe(`${ansiYellow}x${ansiReset}`);
    expect(stateMark(state, byId["one-b"]!)).toBe(" ");
  });
});

// ---------------------------------------------------------------------------
// Reducer transitions (task 4.1)
// ---------------------------------------------------------------------------

describe("reducer: pane switching", () => {
  test("tab toggles panes in both directions", () => {
    let state = initialState();
    expect(state.pane).toBe("categories");
    state = reducer(state, key("tab"));
    expect(state.pane).toBe("components");
    state = reducer(state, key("tab"));
    expect(state.pane).toBe("categories");
  });

  test("left and right also toggle panes", () => {
    let state = reducer(initialState(), key("right"));
    expect(state.pane).toBe("components");
    state = reducer(state, key("left"));
    expect(state.pane).toBe("categories");
  });
});

describe("reducer: navigation", () => {
  test("component cursor clamps at both edges", () => {
    let state = reducer(initialState(), key("tab"));
    expect(state.cursor).toBe(0);
    state = reducer(state, key("up"));
    expect(state.cursor).toBe(0);
    for (let i = 0; i < 50; i++) state = reducer(state, key("down"));
    expect(state.cursor).toBe(COMPONENTS.length - 1);
    state = reducer(state, key("down"));
    expect(state.cursor).toBe(COMPONENTS.length - 1);
  });

  test("sidebar navigation moves the category cursor and jumps the component cursor to category start", () => {
    let state = initialState();
    state = reducer(state, key("down"));
    expect(state.catCursor).toBe(1);
    expect(activeCategory(state, COMPONENTS)).toBe("Shell");
    expect(state.cursor).toBe(firstIndexInCategory(COMPONENTS, "Shell"));
  });

  test("category cursor clamps at edges", () => {
    let state = initialState();
    state = reducer(state, key("up"));
    expect(state.catCursor).toBe(0);
    for (let i = 0; i < 20; i++) state = reducer(state, key("down"));
    expect(state.catCursor).toBe(categoryOrder(COMPONENTS).length - 1);
    state = reducer(state, key("down"));
    expect(state.catCursor).toBe(categoryOrder(COMPONENTS).length - 1);
  });

  test("resize records dimensions", () => {
    const state = reducer(initialState(), resize(80, 24));
    expect(state.width).toBe(80);
    expect(state.height).toBe(24);
  });
});

describe("reducer: toggle rules", () => {
  const atCursor = (overrides: Partial<TuiState>): TuiState => ({
    ...initialState(),
    ...overrides,
  });

  test("space toggles an ordinary component", () => {
    const phpIndex = COMPONENTS.findIndex((c) => c.id === "php");
    let state = atCursor({ pane: "components", cursor: phpIndex });
    expect(state.selected["php"]).toBe(false);
    state = reducer(state, key("space"));
    expect(state.selected["php"]).toBe(true);
    state = reducer(state, key("space"));
    expect(state.selected["php"]).toBe(false);
  });

  test("space cannot deselect a required component", () => {
    let state = atCursor({ pane: "components", cursor: 0 }); // base, required
    state = reducer(state, key("space"));
    expect(state.selected["base"]).toBe(true);
  });

  test("space cannot toggle an applied component", () => {
    const discordIndex = COMPONENTS.findIndex(
      (c) => c.id === "communication-discord",
    );
    let state = atCursor({
      pane: "components",
      cursor: discordIndex,
      applied: { "communication-discord": true },
      selected: { "communication-discord": true },
    });
    state = reducer(state, key("space"));
    expect(state.selected["communication-discord"]).toBe(true);
  });

  test("selectCategory skips required components in mixed categories", () => {
    const cleared = selectCategory(
      fixture,
      { "one-a": true, "one-b": true },
      "One",
      false,
    );
    expect(cleared["one-a"]).toBe(false);
    expect(cleared["one-b"]).toBe(true); // required survives `n`
    const all = selectCategory(
      fixture,
      { "one-a": false, "one-b": true },
      "One",
      true,
    );
    expect(all["one-a"]).toBe(true);
    expect(all["one-b"]).toBe(true);
  });

  test("a selects every ordinary component of the active category", () => {
    let state = initialState();
    for (let i = 0; i < 9; i++) state = reducer(state, key("down")); // Communication
    state = reducer(state, key("a"));
    expect(state.selected["communication-discord"]).toBe(true);
    expect(state.selected["communication-slack"]).toBe(true);
  });

  test("n clears every ordinary component of the cursor component's category", () => {
    let state = reducer(initialState(), key("tab"));
    state = reducer(state, key("a")); // base category: only required base, unchanged
    state = {
      ...state,
      cursor: COMPONENTS.findIndex((c) => c.id === "media-vlc"),
    };
    state = reducer(state, key("n"));
    expect(state.selected["media-vlc"]).toBe(false);
    expect(state.selected["media-spotify"]).toBe(false);
  });
});

describe("reducer: search mode", () => {
  test("/ enters search mode, text appends and resets the cursor, backspace deletes", () => {
    let state = reducer(initialState(), key("tab"));
    for (let i = 0; i < 5; i++) state = reducer(state, key("down"));
    state = reducer(state, key("/"));
    expect(state.searching).toBe(true);
    state = reducer(state, key("text", "d"));
    state = reducer(state, key("text", "i"));
    expect(state.query).toBe("di");
    expect(state.cursor).toBe(0);
    state = reducer(state, key("backspace"));
    expect(state.query).toBe("d");
    state = reducer(state, key("esc"));
    expect(state.searching).toBe(false);
    expect(state.query).toBe("d"); // query retained after leaving search
  });

  test("enter exits search mode", () => {
    let state = reducer(initialState(), key("/"));
    state = reducer(state, key("enter"));
    expect(state.searching).toBe(false);
  });
});

describe("reducer: review flow", () => {
  test("enter on a non-empty visible set opens the review screen", () => {
    let state = initialState();
    state = reducer(state, key("enter"));
    expect(state.review).toBe(true);
    expect(state.reviewTop).toBe(0);
  });

  test("enter on an empty visible set does not open review", () => {
    let state: TuiState = { ...initialState(), searching: true, query: "zzz" };
    state = reducer(state, key("enter"));
    expect(state.review).toBe(false);
  });

  test("enter or y submits; esc cancels without submitting", () => {
    let state = reducer(initialState(), key("enter")); // open review
    state = reducer(state, key("esc"));
    expect(state.review).toBe(false);
    expect(state.submitted).toBe(false);

    state = reducer(state, key("enter"));
    state = reducer(state, key("y"));
    expect(state.submitted).toBe(true);
    expect(state.review).toBe(false);

    // Go port: TestModelEnterShowsReviewThenSubmits (enter path)
    let second = reducer(initialState(), key("enter"));
    second = reducer(second, key("enter"));
    expect(second.submitted).toBe(true);
  });

  test("up/down scroll reviewTop with a floor at zero", () => {
    let state = reducer(initialState(), key("enter"));
    state = reducer(state, key("down"));
    state = reducer(state, key("down"));
    expect(state.reviewTop).toBe(2);
    state = reducer(state, key("up"));
    expect(state.reviewTop).toBe(1);
    state = reducer(state, key("up"));
    state = reducer(state, key("up"));
    expect(state.reviewTop).toBe(0);
    state = reducer(state, key("up"));
    expect(state.reviewTop).toBe(0);
  });

  test("profileOf copies the selection map", () => {
    let state = reducer(initialState(), key("tab"));
    state = reducer(state, key("space"));
    const profile = profileOf(state);
    expect(profile.components).toEqual(state.selected);
    expect(profile.components).not.toBe(state.selected);
  });
});

describe("mapInkKey", () => {
  test("maps Ink input pairs onto the Go key.String() vocabulary", () => {
    const k = (name: string) => ({ name }) as never;
    expect(mapInkKey("", { upArrow: true })).toEqual({ key: "up" });
    expect(mapInkKey("", { downArrow: true })).toEqual({ key: "down" });
    expect(mapInkKey("", { leftArrow: true })).toEqual({ key: "left" });
    expect(mapInkKey("", { rightArrow: true })).toEqual({ key: "right" });
    expect(mapInkKey("", { return: true })).toEqual({ key: "enter" });
    expect(mapInkKey("", { escape: true })).toEqual({ key: "esc" });
    expect(mapInkKey("", { tab: true })).toEqual({ key: "tab" });
    expect(mapInkKey("", { backspace: true })).toEqual({ key: "backspace" });
    expect(mapInkKey("", { delete: true })).toEqual({ key: "backspace" });
    expect(mapInkKey(" ", {})).toEqual({ key: "space" });
    expect(mapInkKey("c", { ctrl: true })).toEqual({ key: "ctrl+c" });
    expect(mapInkKey("q", k("q"))).toEqual({ key: "q" });
    expect(mapInkKey("/", k("/"))).toEqual({ key: "text", text: "/" });
    expect(mapInkKey("d", k("d"))).toEqual({ key: "text", text: "d" });
  });
});

// ---------------------------------------------------------------------------
// Frame tests via ink-testing-library (tasks 4.2–4.3)
// ---------------------------------------------------------------------------

const TALL = { width: 80, height: 60 };

describe("frame: two-pane selection layout", () => {
  test("initial screen: categories in manifest order, defaults marked x, no green check", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    const frame = ui.lastFrame() ?? "";

    // Header, hint, status, footer.
    expect(frame).toContain(`${"dot installer"}`);
    expect(frame).toContain("(tab pane  / search)");
    expect(frame).toContain(`${ansiGreen}✓ installed 0${CLOSE_COLOR}`);
    expect(frame).toContain(
      "space toggle  a all  n none  enter review  q quit",
    );

    // Sidebar shows every category in manifest order, first one active.
    let position = -1;
    for (const category of categoryOrder(COMPONENTS)) {
      const at = frame.indexOf(` ${category}`);
      expect(at).toBeGreaterThan(position);
      position = at;
    }
    expect(frame).toContain("> Base");

    // Default/required components carry the yellow x; nothing is applied yet.
    expect(frame).toContain(`${ansiYellow}x${CLOSE_COLOR}`);
    expect(frame).not.toContain(`${ansiGreen}✓${CLOSE_COLOR}`);

    ui.unmount();
  });

  test("sidebar highlights the active pane and cursor row with reverse video", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    const frame = ui.lastFrame() ?? "";
    expect(frame).toContain(`${ansiReverse}> Base`);
    ui.unmount();
  });

  test("applied components show a green check on their row", async () => {
    const ui = render(
      <App
        fixedSize={TALL}
        initialApplied={{ "communication-discord": true }}
      />,
    );
    await delay(20);
    expect(ui.lastFrame()).toContain(`${ansiGreen}✓${CLOSE_COLOR} Discord`);
    ui.unmount();
  });
});

describe("frame: toggle rules", () => {
  test("space toggles an ordinary component on and off", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    for (let i = 0; i < 4; i++) await press(ui, KEY_DOWN); // PHP category
    await press(ui, KEY_TAB);
    const off = ui.lastFrame() ?? "";
    expect(off).not.toContain(`${ansiYellow}x${CLOSE_COLOR} Composer`);

    await press(ui, " ");
    expect(ui.lastFrame()).toContain(
      `${ansiYellow}x${CLOSE_COLOR} Composer, Herd and PHPStorm`,
    );

    await press(ui, " ");
    expect(ui.lastFrame()).not.toContain(
      `${ansiYellow}x${CLOSE_COLOR} Composer`,
    );
    ui.unmount();
  });

  test("space is a no-op for a required component", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    await press(ui, KEY_TAB); // cursor lands on base (required)
    const before = ui.lastFrame() ?? "";
    await press(ui, " ");
    expect(ui.lastFrame()).toBe(before);
    ui.unmount();
  });

  test("space is a no-op for an applied component", async () => {
    const ui = render(
      <App
        fixedSize={TALL}
        initialApplied={{ "communication-discord": true }}
      />,
    );
    await delay(20);
    for (let i = 0; i < 9; i++) await press(ui, KEY_DOWN); // Communication
    await press(ui, KEY_TAB); // cursor jumps to discord
    const before = ui.lastFrame() ?? "";
    expect(before).toContain(`${ansiGreen}✓${CLOSE_COLOR} Discord`);
    await press(ui, " ");
    expect(ui.lastFrame()).toBe(before);
    ui.unmount();
  });

  test("a selects the active category, n clears it, required components survive both", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    for (let i = 0; i < 9; i++) await press(ui, KEY_DOWN); // Communication
    await press(ui, "a");
    let frame = ui.lastFrame() ?? "";
    expect(frame).toContain(`${ansiYellow}x${CLOSE_COLOR} Discord`);
    expect(frame).toContain(`${ansiYellow}x${CLOSE_COLOR} Slack`);

    await press(ui, "n");
    frame = ui.lastFrame() ?? "";
    expect(frame).not.toContain(`${ansiYellow}x${CLOSE_COLOR} Discord`);
    expect(frame).not.toContain(`${ansiYellow}x${CLOSE_COLOR} Slack`);
    ui.unmount();
  });

  test("n on the required Base category leaves base selected", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    const before = ui.lastFrame() ?? "";
    expect(before).toContain(`${ansiYellow}x${CLOSE_COLOR} Base tools`);
    await press(ui, "n");
    await press(ui, "a");
    expect(ui.lastFrame()).toBe(before);
    ui.unmount();
  });
});

describe("frame: search filtering", () => {
  test("query filters case-insensitively by label; clearing restores the full list", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    await press(ui, "/");
    for (const ch of "discord") await press(ui, ch);

    let frame = ui.lastFrame() ?? "";
    expect(frame).toContain("search: discord_");
    expect(frame).toContain("Discord");
    expect(frame).not.toContain("Slack");

    await press(ui, KEY_ESC);
    frame = ui.lastFrame() ?? "";
    expect(frame).toContain("Discord");
    expect(frame).toContain("Slack");
    expect(frame).toContain("(tab pane  / search)");
    ui.unmount();
  });

  test("uppercase query still matches (case-insensitive)", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    await press(ui, "/");
    for (const ch of "VLC") await press(ui, ch);
    expect(ui.lastFrame()).toContain("VLC");
    ui.unmount();
  });

  test("backspace deletes the last query character", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    await press(ui, "/");
    for (const ch of "slack") await press(ui, ch);
    expect(ui.lastFrame()).toContain("search: slack_");
    await press(ui, "\x7f"); // backspace
    expect(ui.lastFrame()).toContain("search: slac_");
    ui.unmount();
  });

  test("no matches shows the query; modification keys are inert; enter does not open review", async () => {
    const ui = render(<App fixedSize={TALL} />);
    await delay(20);
    await press(ui, "/");
    for (const ch of "zzz") await press(ui, ch);
    const frame = ui.lastFrame() ?? "";
    expect(frame).toContain(`${ansiDim}No matches for zzz${CLOSE_MODE}`);

    await press(ui, " ");
    await press(ui, "a");
    await press(ui, "n");
    expect(ui.lastFrame()).toBe(frame);

    await press(ui, KEY_ENTER);
    // Go semantics: enter exits search mode (query retained) and, because the
    // visible set was empty at press time, never opened the review screen.
    const afterEnter = ui.lastFrame() ?? "";
    expect(afterEnter).toContain("(tab pane  / search)");
    expect(afterEnter).not.toContain("Review plan");
    expect(afterEnter).toContain("Slack"); // full list restored
    ui.unmount();
  });
});

describe("frame: review flow", () => {
  test("review lists only selected-not-applied grouped by category with counts", async () => {
    const ui = render(
      <App
        fixedSize={TALL}
        initialApplied={{ "communication-slack": true }}
        initialSelected={{
          "communication-discord": true,
          "communication-slack": true,
        }}
      />,
    );
    await delay(20);
    await press(ui, KEY_ENTER);

    const frame = ui.lastFrame() ?? "";
    expect(frame).toContain("Review plan");
    expect(frame).toContain("[Communication]");
    expect(frame).toContain("Discord");
    expect(frame).not.toContain("Slack"); // applied -> excluded
    expect(frame).toContain(`${ansiGreen}✓ installed 1${CLOSE_COLOR}`);
    expect(frame).toContain(`${ansiYellow}to install 1${CLOSE_COLOR}`);
    expect(frame).toContain("enter apply  esc back  q quit");
    // Required defaults are selected-not-applied, so [Base] is present; truly
    // unselected categories are absent (Go reviewRows semantics).
    expect(frame).toContain("[Base]");
    expect(frame).not.toContain("[PHP]");

    await press(ui, KEY_ESC);
    expect(ui.lastFrame()).toContain("dot installer"); // back to selection
    ui.unmount();
  });

  test("empty review reports nothing to install", async () => {
    const ui = render(
      <App
        fixedSize={TALL}
        initialApplied={{ base: true, shell: true, git: true, terminal: true }}
      />,
    );
    await delay(20);
    await press(ui, KEY_ENTER);
    const frame = ui.lastFrame() ?? "";
    expect(frame).toContain(
      "Nothing to install — everything is already applied.",
    );
    expect(frame).not.toContain("[Base]");
    ui.unmount();
  });
});

describe("frame: viewport keeps footer visible", () => {
  test("small terminal keeps footer last and shows clipped-row indicators (Go port)", async () => {
    const ui = render(<App fixedSize={{ width: 80, height: 8 }} />);
    await delay(20);
    const frame = ui.lastFrame() ?? "";
    expect(frame).toContain("space toggle");
    expect(frame).toContain("more");
    expect(
      frame
        .trimEnd()
        .endsWith(
          `space toggle  a all  n none  enter review  q quit${CLOSE_MODE}`,
        ),
    ).toBe(true);
    ui.unmount();
  });

  test("long list scrolls to keep the cursor row visible", async () => {
    const ui = render(<App fixedSize={{ width: 80, height: 8 }} />);
    await delay(20);
    await press(ui, KEY_TAB);
    for (let i = 0; i < 24; i++) await press(ui, KEY_DOWN);

    const frame = ui.lastFrame() ?? "";
    // indices[24] is the 25th manifest entry: desktop-linearmouse.
    expect(frame).toContain(">   LinearMouse");
    expect(frame).toContain("↑ more");
    expect(
      frame
        .trimEnd()
        .endsWith(
          `space toggle  a all  n none  enter review  q quit${CLOSE_MODE}`,
        ),
    ).toBe(true);
    ui.unmount();
  });

  test("review scrolls with indicators and keeps its footer last", async () => {
    const ui = render(<App fixedSize={{ width: 80, height: 8 }} />);
    await delay(20);
    for (let i = 0; i < 8; i++) await press(ui, KEY_DOWN); // Desktop
    await press(ui, "a");
    await press(ui, KEY_ENTER);

    const top = ui.lastFrame() ?? "";
    expect(top).toContain("↓ more");
    expect(top).not.toContain("↑ more");
    expect(
      top.trimEnd().endsWith(`enter apply  esc back  q quit${CLOSE_MODE}`),
    ).toBe(true);

    await press(ui, KEY_DOWN);
    await press(ui, KEY_DOWN);
    const scrolled = ui.lastFrame() ?? "";
    expect(scrolled).toContain("↑ more");
    expect(scrolled).toContain("↓ more");
    expect(
      scrolled.trimEnd().endsWith(`enter apply  esc back  q quit${CLOSE_MODE}`),
    ).toBe(true);
    ui.unmount();
  });
});
