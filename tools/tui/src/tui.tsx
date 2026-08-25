// Ink port of internal/installer/tui.go (ADR-2): one useReducer mirrors the Go
// Model struct field-for-field, pure view functions emit the same raw ANSI
// strings the Go View() produced, rendered through <Text>.
import { Text, useApp, useInput, useStdout } from "ink";
import { useEffect, useReducer, useRef } from "react";
import { COMPONENTS, type Component } from "./manifest";
import type { Profile } from "./profile";

export const ansiReset = "\x1b[0m";
export const ansiBold = "\x1b[1m";
export const ansiDim = "\x1b[2m";
export const ansiGreen = "\x1b[32m";
export const ansiCyan = "\x1b[36m";
export const ansiYellow = "\x1b[33m";
export const ansiReverse = "\x1b[7m";

export type Pane = "categories" | "components";

/** Field-for-field mirror of the Go Model struct (width/height included). */
export interface TuiState {
  pane: Pane;
  catCursor: number;
  cursor: number;
  selected: Record<string, boolean>;
  applied: Record<string, boolean>;
  query: string;
  searching: boolean;
  review: boolean;
  reviewTop: number;
  submitted: boolean;
  width: number;
  height: number;
}

export type Action =
  | { type: "resize"; width: number; height: number }
  | { type: "key"; key: string; text?: string };

export function categoryOrder(components: Component[]): string[] {
  const seen = new Set<string>();
  const order: string[] = [];
  for (const component of components) {
    if (!seen.has(component.category)) {
      seen.add(component.category);
      order.push(component.category);
    }
  }
  return order;
}

/** Ports NewModel(): defaults selected, empty applied set. */
export function initialState(
  components: Component[] = COMPONENTS,
  applied: Record<string, boolean> = {},
): TuiState {
  const selected: Record<string, boolean> = {};
  for (const component of components) {
    selected[component.id] = component.default || component.required;
  }
  return {
    pane: "categories",
    catCursor: 0,
    cursor: 0,
    selected,
    applied: { ...applied },
    query: "",
    searching: false,
    review: false,
    reviewTop: 0,
    submitted: false,
    width: 0,
    height: 0,
  };
}

export function activeCategory(
  state: TuiState,
  components: Component[],
): string {
  const categories = categoryOrder(components);
  if (categories.length === 0) return "";
  const catCursor = Math.min(
    Math.max(state.catCursor, 0),
    categories.length - 1,
  );
  return categories[catCursor] ?? "";
}

/** Component indices visible in the right pane: every match while searching,
 *  otherwise the full grouped list. */
export function visibleIndices(
  state: TuiState,
  components: Component[],
): number[] {
  const query = state.query.toLowerCase();
  const indices: number[] = [];
  for (let index = 0; index < components.length; index++) {
    const component = components[index]!;
    if (state.searching) {
      if (
        query === "" ||
        component.label.toLowerCase().includes(query) ||
        component.category.toLowerCase().includes(query)
      ) {
        indices.push(index);
      }
      continue;
    }
    indices.push(index);
  }
  return indices;
}

/** Index of the first component in the category, or 0 when absent. */
export function firstIndexInCategory(
  components: Component[],
  category: string,
): number {
  for (let i = 0; i < components.length; i++) {
    if (components[i]!.category === category) return i;
  }
  return 0;
}

export function clampViewport(
  cursor: number,
  viewport: number,
  total: number,
): number {
  if (total <= viewport) return 0;
  let start = cursor - Math.floor(viewport / 2);
  if (start < 0) start = 0;
  if (start + viewport > total) start = total - viewport;
  return start;
}

export function counts(
  state: TuiState,
  components: Component[],
): { selected: number; installed: number; pending: number } {
  let selected = 0;
  let installed = 0;
  let pending = 0;
  for (const component of components) {
    if (state.applied[component.id]) {
      installed++;
      continue;
    }
    if (state.selected[component.id]) {
      selected++;
      if (!component.required) pending++;
    }
  }
  return { selected, installed, pending };
}

/** Rows of the review screen: "[Category]" headers plus indented labels,
 *  covering exactly the selected-not-applied components. */
export function reviewRows(state: TuiState, components: Component[]): string[] {
  const rows: string[] = [];
  let lastCategory = "";
  for (const component of components) {
    if (!state.selected[component.id] || state.applied[component.id]) continue;
    if (component.category !== lastCategory) {
      rows.push("[" + component.category + "]");
      lastCategory = component.category;
    }
    rows.push("   " + component.label);
  }
  return rows;
}

export function stateMark(state: TuiState, component: Component): string {
  if (state.applied[component.id]) return ansiGreen + "✓" + ansiReset;
  if (state.selected[component.id]) return ansiYellow + "x" + ansiReset;
  return " ";
}

/** Sets every non-required component of the category (ports selectCategory). */
export function selectCategory(
  components: Component[],
  selected: Record<string, boolean>,
  category: string,
  enabled: boolean,
): Record<string, boolean> {
  const next = { ...selected };
  for (const component of components) {
    if (component.category === category && !component.required) {
      next[component.id] = enabled;
    }
  }
  return next;
}

export function reducer(state: TuiState, action: Action): TuiState {
  switch (action.type) {
    case "resize":
      return { ...state, width: action.width, height: action.height };
    case "key":
      return reduceKey(state, action);
  }
}

// Ports Update()'s "a"/"n" branch: toggles every ordinary component of the
// active category (categories pane) or of the cursor component's category.
function categoryToggle(state: TuiState, enabled: boolean): TuiState {
  const indices = visibleIndices(state, COMPONENTS);
  if (indices.length === 0) return state;
  const category =
    state.pane === "categories"
      ? activeCategory(state, COMPONENTS)
      : COMPONENTS[indices[state.cursor]!]!.category;
  return {
    ...state,
    selected: selectCategory(COMPONENTS, state.selected, category, enabled),
  };
}

// Mirrors Update()'s precedence: review first, then search mode, then the main
// switch. Quit ("q"/"ctrl+c") is owned by the App component (tea.Quit analog).
function reduceKey(
  state: TuiState,
  action: Extract<Action, { type: "key" }>,
): TuiState {
  const name = action.key;

  if (state.review) {
    switch (name) {
      case "enter":
      case "y":
        // App exits (tea.Quit) once submitted flips true.
        return { ...state, submitted: true, review: false };
      case "esc":
        return { ...state, review: false };
      case "up":
        return state.reviewTop > 0
          ? { ...state, reviewTop: state.reviewTop - 1 }
          : state;
      case "down":
        return { ...state, reviewTop: state.reviewTop + 1 };
      default:
        return state;
    }
  }

  if (state.searching) {
    if (name === "esc" || name === "enter")
      return { ...state, searching: false };
    if (name === "backspace") {
      if (state.query === "") return state;
      return { ...state, query: state.query.slice(0, -1), cursor: 0 };
    }
    if (name === "text") {
      const text = action.text ?? "";
      // Spec: a/n/space are no-ops while the visible set is empty.
      if (
        visibleIndices(state, COMPONENTS).length === 0 &&
        (text === "a" || text === "n")
      ) {
        return state;
      }
      return { ...state, query: state.query + text, cursor: 0 };
    }
    return state;
  }

  switch (name) {
    case "/":
      return { ...state, searching: true };
    case "tab":
    case "left":
    case "right":
      return {
        ...state,
        pane: state.pane === "categories" ? "components" : "categories",
      };
    case "enter": {
      if (visibleIndices(state, COMPONENTS).length === 0) return state;
      return { ...state, review: true, reviewTop: 0 };
    }
    case "up":
    case "down": {
      if (state.pane === "categories") {
        const categories = categoryOrder(COMPONENTS);
        let catCursor = state.catCursor;
        if (name === "up" && catCursor > 0) catCursor--;
        if (name === "down" && catCursor < categories.length - 1) catCursor++;
        const jumped: TuiState = { ...state, catCursor };
        return {
          ...jumped,
          cursor: firstIndexInCategory(
            COMPONENTS,
            activeCategory(jumped, COMPONENTS),
          ),
        };
      }
      const indices = visibleIndices(state, COMPONENTS);
      if (indices.length === 0) return state;
      let cursor = state.cursor;
      if (name === "up" && cursor > 0) cursor--;
      if (name === "down" && cursor < indices.length - 1) cursor++;
      return { ...state, cursor };
    }
    case "a":
      return categoryToggle(state, true);
    case "n":
      return categoryToggle(state, false);
    case "text": {
      // Ink delivers printable runes as text; route the ones that are
      // commands in the Go key.String() vocabulary onto their handlers.
      if (action.text === "/") return { ...state, searching: true };
      if (action.text === "a") return categoryToggle(state, true);
      if (action.text === "n") return categoryToggle(state, false);
      return state;
    }
    case "space": {
      const indices = visibleIndices(state, COMPONENTS);
      if (indices.length === 0) return state;
      const component = COMPONENTS[indices[state.cursor]!]!;
      if (!component.required && !state.applied[component.id]) {
        return {
          ...state,
          selected: {
            ...state.selected,
            [component.id]: !state.selected[component.id],
          },
        };
      }
      return state;
    }
    default:
      return state;
  }
}

/** Copies the live selection into a Profile (ports Model.Profile()). */
export function profileOf(state: TuiState): Profile {
  return { components: { ...state.selected } };
}

function padRight(text: string, width: number): string {
  let padded = text;
  while (padded.length < width) padded += " ";
  return padded;
}

function categoryRows(state: TuiState, components: Component[]): string[] {
  const active = activeCategory(state, components);
  return categoryOrder(components).map((category) => {
    const mark = category === active ? ">" : " ";
    return mark + " " + category;
  });
}

function componentRows(
  state: TuiState,
  components: Component[],
): { rows: string[]; cursorRow: number } {
  const indices = visibleIndices(state, components);
  if (indices.length === 0) {
    return {
      rows: [ansiDim + "No matches for " + state.query + ansiReset],
      cursorRow: 0,
    };
  }
  const rows: string[] = [];
  let lastCategory = "";
  let cursorRow = 0;
  for (let i = 0; i < indices.length; i++) {
    const component = components[indices[i]!]!;
    if (component.category !== lastCategory) {
      rows.push(ansiDim + "[" + component.category + "]" + ansiReset);
      lastCategory = component.category;
    }
    if (i === state.cursor) cursorRow = rows.length;
    const cursor = i === state.cursor ? ">" : " ";
    rows.push(
      cursor + " " + stateMark(state, component) + " " + component.label,
    );
  }
  return { rows, cursorRow };
}

/** Ports Model.selectionView(): sidebar + viewport + status + footer. */
export function selectionView(
  state: TuiState,
  components: Component[] = COMPONENTS,
): string {
  const { installed, pending } = counts(state, components);

  const cats = categoryRows(state, components);
  let sidebarWidth = 0;
  for (const row of cats) {
    if (row.length > sidebarWidth) sidebarWidth = row.length;
  }

  const { rows: compRows, cursorRow } = componentRows(state, components);
  const bodyHeight = Math.max(state.height - 4, 1);

  let header = ansiBold + " dot installer " + ansiReset;
  if (state.searching) {
    header += ansiDim + " search: " + state.query + "_" + ansiReset;
  } else {
    header += ansiDim + "(tab pane  / search)" + ansiReset;
  }

  const status =
    " " +
    ansiGreen +
    "✓ installed " +
    String(installed) +
    ansiReset +
    "  " +
    ansiYellow +
    "selected " +
    String(pending) +
    ansiReset;

  const lines: string[] = [header, ""];

  const compStart = clampViewport(cursorRow, bodyHeight, compRows.length);
  let compEnd = compStart + bodyHeight;
  if (compEnd > compRows.length) compEnd = compRows.length;

  const moreTop = compStart > 0;
  const moreBottom = compEnd < compRows.length;
  const lastRow = bodyHeight - 1;
  for (let row = 0; row < bodyHeight; row++) {
    let left = "";
    if (!state.searching) {
      left = row < cats.length ? cats[row]! : "";
      left = padRight(left, sidebarWidth);
      if (state.pane === "categories" && row === state.catCursor) {
        left = ansiReverse + left + ansiReset;
      }
    }
    let right = "";
    if (compStart + row < compEnd) right = compRows[compStart + row]!;
    if (row === 0 && moreTop) right = ansiDim + "↑ more" + ansiReset;
    if (row === lastRow && moreBottom) right = ansiDim + "↓ more" + ansiReset;
    lines.push(left + "  " + right);
  }

  const help =
    ansiDim + "space toggle  a all  n none  enter review  q quit" + ansiReset;
  lines.push(status, help);
  return lines.join("\n");
}

/** Ports Model.reviewView(). */
export function reviewView(
  state: TuiState,
  components: Component[] = COMPONENTS,
): string {
  const rows = reviewRows(state, components);
  const available = Math.max(state.height - 5, 1);
  let start = state.reviewTop;
  if (start + available > rows.length) {
    start = rows.length - available;
    if (start < 0) start = 0;
  }
  let end = start + available;
  if (end > rows.length) end = rows.length;

  const { installed, pending } = counts(state, components);
  const lines: string[] = [
    ansiBold +
      " Review plan " +
      ansiReset +
      " (" +
      ansiGreen +
      "✓ installed " +
      String(installed) +
      ansiReset +
      ", " +
      ansiYellow +
      "to install " +
      String(pending) +
      ansiReset +
      ")",
    "",
  ];

  if (rows.length === 0) {
    lines.push(
      ansiDim +
        "Nothing to install — everything is already applied." +
        ansiReset,
    );
  } else {
    if (start > 0) lines.push(ansiDim + "↑ more" + ansiReset);
    for (let i = start; i < end; i++) lines.push(rows[i]!);
    if (end < rows.length) lines.push(ansiDim + "↓ more" + ansiReset);
  }

  lines.push("");
  lines.push(ansiDim + "enter apply  esc back  q quit" + ansiReset);
  return lines.join("\n");
}

export interface MappedKey {
  key: string;
  text?: string;
}

interface InkKeyFlags {
  upArrow?: boolean;
  downArrow?: boolean;
  leftArrow?: boolean;
  rightArrow?: boolean;
  return?: boolean;
  escape?: boolean;
  tab?: boolean;
  backspace?: boolean;
  delete?: boolean;
  ctrl?: boolean;
  meta?: boolean;
}

/** Normalizes Ink's (input, key) pair onto the Go key.String() vocabulary. */
export function mapInkKey(input: string, key: InkKeyFlags): MappedKey | null {
  if (key.upArrow) return { key: "up" };
  if (key.downArrow) return { key: "down" };
  if (key.leftArrow) return { key: "left" };
  if (key.rightArrow) return { key: "right" };
  if (key.return) return { key: "enter" };
  if (key.escape) return { key: "esc" };
  if (key.tab) return { key: "tab" };
  if (key.backspace || key.delete) return { key: "backspace" };
  if (input === " ") return { key: "space" };
  if (key.ctrl && input === "c") return { key: "ctrl+c" };
  // "q" is a control key in the app vocabulary (tea.Quit analog); App owns the
  // mode-dependent handling (quit outside search, literal insert inside).
  if (input === "q" && !key.ctrl && !key.meta) return { key: "q" };
  if (input.length > 0 && !key.ctrl && !key.meta)
    return { key: "text", text: input };
  return null;
}

export interface AppProps {
  /** Seeds the applied set (main.ts passes the previous round's results). */
  initialApplied?: Record<string, boolean>;
  /** Test seam: seeds extra selections (Go tests assigned model.selected). */
  initialSelected?: Record<string, boolean>;
  /** Test seam: deterministic terminal size instead of the real stdout. */
  fixedSize?: { width: number; height: number };
  /** Loop-owner seam (main.ts): receives the final state on submission,
   *  immediately before exit() — the tea.Program return-value analog. */
  onSubmit?: (state: TuiState) => void;
}

export function App({
  initialApplied = {},
  initialSelected,
  fixedSize,
  onSubmit,
}: AppProps): React.ReactElement {
  const [state, dispatch] = useReducer(reducer, undefined, () => {
    const base = initialState(COMPONENTS, initialApplied);
    return initialSelected
      ? { ...base, selected: { ...base.selected, ...initialSelected } }
      : base;
  });
  const stateRef = useRef(state);
  stateRef.current = state;
  const { exit } = useApp();
  const { stdout } = useStdout();

  // tea.WindowSizeMsg equivalent: seed real dimensions and follow resizes.
  useEffect(() => {
    if (fixedSize) {
      dispatch({
        type: "resize",
        width: fixedSize.width,
        height: fixedSize.height,
      });
      return;
    }
    const stream = stdout as typeof stdout & {
      columns?: number;
      rows?: number;
      on?: (event: string, listener: () => void) => unknown;
      off?: (event: string, listener: () => void) => unknown;
    };
    const dispatchResize = () =>
      dispatch({
        type: "resize",
        width: stream.columns ?? 80,
        height: stream.rows ?? 24,
      });
    dispatchResize();
    stream.on?.("resize", dispatchResize);
    return () => {
      stream.off?.("resize", dispatchResize);
    };
  }, [fixedSize, stdout]);

  // tea.Quit equivalent after submit; main.ts reads the submitted
  // selection through onSubmit (the finalModel return of tea.NewProgram).
  useEffect(() => {
    if (state.submitted) {
      onSubmit?.(stateRef.current);
      exit();
    }
  }, [state.submitted, exit]);

  useInput((input, key) => {
    const mapped = mapInkKey(input, key);
    if (!mapped) return;
    // Go returned tea.Quit for q/ctrl+c outside search mode (both panes and
    // review); everything else flows through the reducer.
    if (
      !stateRef.current.searching &&
      (mapped.key === "q" || mapped.key === "ctrl+c")
    ) {
      exit();
      return;
    }
    // Go's searching branch appends key.Text, so a literal "q" must reach it
    // as text even though mapInkKey classifies it as a named key.
    if (stateRef.current.searching && mapped.key === "q") {
      dispatch({ type: "key", key: "text", text: "q" });
      return;
    }
    dispatch({
      type: "key",
      key: mapped.key,
      ...(mapped.text === undefined ? {} : { text: mapped.text }),
    });
  });

  return <Text>{state.review ? reviewView(state) : selectionView(state)}</Text>;
}
