// Two-step installer flow (design §2): Step 1 is a per-tool selector with the
// locked essentials pinned at top (🔒, never toggleable), visual topic
// grouping, strictly per-row toggles and the special code/duti rows included.
// Step 2 lists the ADR-3-filtered config links (all unchecked, multi-target
// names as ONE row) followed by the opt-in AI-agents group (unchecked).
// Quitting anywhere before confirm submits nothing — main.ts maps that to
// exit 10 with zero filesystem writes. Views stay pure-string Ink text.
import { Text, useApp, useInput, useStdout } from "ink";
import { useEffect, useReducer, useRef } from "react";
import type { ContextLink, ContextPackage, InstallContext } from "./context";
import {
  offeredLinks,
  toolRows,
  toolRowsGrouped,
  type LinkGrouping,
  type ToolRow,
} from "./manifest";

export const LOCK_MARK = "🔒";

export interface TuiState {
  step: 1 | 2;
  cursor: number;
  /** Per-tool row selections (package ids + locked pseudo-step ids). */
  selected: Record<string, boolean>;
  /** Confirmed link names (step 2), toggled as one unit per multi-target name. */
  checked: Record<string, boolean>;
  /** Step-2 extra-install rows (code, duti-defaults), gated by step-1 picks. */
  special: Record<string, boolean>;
  submitted: boolean;
  width: number;
  height: number;
}

export type Action =
  | { type: "resize"; width: number; height: number }
  | { type: "key"; key: string };

/** Seeds every locked/default row checked, every other row unchecked. */
export function initialState(
  context: InstallContext,
  initialSelected: Record<string, boolean> = {},
): TuiState {
  const selected: Record<string, boolean> = {};
  for (const row of toolRows(context)) {
    selected[row.id] = row.locked || row.default || row.installed === true;
  }
  return {
    step: 1,
    cursor: 0,
    selected: { ...selected, ...initialSelected },
    checked: {},
    special: {},
    submitted: false,
    // 80x24 dingbat defaults keep the pure views readable before the App
    // dispatches the real terminal size on mount.
    width: 80,
    height: 24,
  };
}

/**
 * Step-2 link listing: offered main links, then the opt-in agents group.
 * Locked rows stay in the selection map but offeredLinks ignores them, so only
 * confirmed toggleable rows light up areas (ADR-3).
 */
export function linkRowsForStep(
  context: InstallContext,
  state: TuiState,
): LinkGrouping {
  const selected = new Set(
    Object.keys(state.selected).filter((id) => state.selected[id]),
  );
  return offeredLinks(context, selected);
}

/** Toggles one link name (all its targets together). */
export function toggleLink(state: TuiState, name: string): TuiState {
  return {
    ...state,
    checked: { ...state.checked, [name]: !state.checked[name] },
  };
}

/**
 * Step-2 extra-install rows (kind "topic": VS Code extensions, duti default
 * file handlers). Offered only when their prerequisite was picked in step 1:
 * code iff visual-studio-code is selected, duti-defaults iff the duti
 * formula is selected. Never part of step 1.
 */
export function specialRowsForStep(
  context: InstallContext,
  state: TuiState,
): ContextPackage[] {
  return context.packages.filter((p) => {
    if (p.kind !== "topic") return false;
    if (p.id === "code") return state.selected["visual-studio-code"] === true;
    if (p.id === "duti-defaults") return state.selected["duti"] === true;
    return false;
  });
}

export function toggleSpecial(state: TuiState, id: string): TuiState {
  return {
    ...state,
    special: { ...state.special, [id]: !state.special[id] },
  };
}

function selectedMark(selected: boolean): string {
  return selected ? "[x]" : "[ ]";
}

/** Pure string view for Step 1 (per-tool selector). */
export function toolView(state: TuiState, context: InstallContext): string {
  // Grouped order, not raw toolRows: same-category rows are guaranteed
  // contiguous here, so the adjacency-based header check below never repeats
  // a category (reduceKey below indexes this SAME order for the cursor).
  const rows = toolRowsGrouped(context);
  const lines: string[] = [" dot installer  step 1/2: choose tools ", ""];
  let cursorRow = 0;
  for (let i = 0; i < rows.length; i++) {
    if (i === state.cursor) cursorRow = lines.length;
    const row = rows[i]!;
    if (
      row.category !== "locked" &&
      i > 0 &&
      rows[i - 1]!.category !== row.category
    ) {
      lines.push(` [${row.category}]`);
      if (i < state.cursor) cursorRow++;
    }
    const cursorMark = i === state.cursor ? ">" : " ";
    const lock = row.locked ? `${LOCK_MARK} ` : "  ";
    lines.push(
      `${cursorMark} ${lock}${selectedMark(state.selected[row.id] === true)} ${row.label}`,
    );
  }
  return (
    viewportOf(lines, cursorRow, state.height) +
    "\n\nspace toggle  enter next  q quit"
  );
}

function linkRowLine(
  link: ContextLink,
  cursor: boolean,
  checked: boolean,
): string {
  const cursorMark = cursor ? ">" : " ";
  const targets = link.rows.length > 1 ? ` (${link.rows.length} targets)` : "";
  return `${cursorMark} ${selectedMark(checked)} ${link.name}${targets}`;
}

/** Pure string view for Step 2 (filtered links + opt-in agents). */
/** Ordered step-2 rows: offered links, opt-in agents, gated extra installs. */
export function stepTwoRows(
  context: InstallContext,
  state: TuiState,
): Array<
  { kind: "link"; link: ContextLink } | { kind: "special"; pkg: ContextPackage }
> {
  const { main, agents } = linkRowsForStep(context, state);
  const specials = specialRowsForStep(context, state);
  return [
    ...main.map((link) => ({ kind: "link" as const, link })),
    ...agents.map((link) => ({ kind: "link" as const, link })),
    ...specials.map((pkg) => ({ kind: "special" as const, pkg })),
  ];
}

export function linkView(state: TuiState, context: InstallContext): string {
  const rows = stepTwoRows(context, state);
  const lines: string[] = [
    state.special && Object.keys(state.special).length > 0
      ? " dot installer  step 2/2: link configs + extras "
      : " dot installer  step 2/2: link configs ",
    "",
  ];
  let cursorRow = 0;
  let linkIdx = 0;
  for (let i = 0; i < rows.length; i++) {
    if (i === state.cursor) cursorRow = lines.length;
    const row = rows[i]!;
    if (row.kind === "link") {
      const link = row.link;
      if (linkIdx === linkRowsForStep(context, state).main.length) {
        lines.push(" opt-in AI agents (unchecked)");
        if (i <= state.cursor) cursorRow++;
      }
      linkIdx++;
      lines.push(
        linkRowLine(
          link,
          i === state.cursor,
          state.checked[link.name] === true,
        ),
      );
    } else {
      if (i > 0 && rows[i - 1]!.kind === "link") {
        lines.push(" extra installs (from step-1 picks)");
        if (i <= state.cursor) cursorRow++;
      }
      lines.push(
        `${i === state.cursor ? ">" : " "} ${selectedMark(state.special[row.pkg.id] === true)} ${row.pkg.label ?? row.pkg.id}`,
      );
    }
  }
  return (
    viewportOf(lines, cursorRow, state.height) +
    "\n\nspace toggle  enter apply  q quit"
  );
}

/** Keeps the cursor row visible in a small terminal (footer stays last). */
function viewportOf(
  lines: string[],
  cursorRow: number,
  height: number,
): string {
  const viewport = Math.max(height - 3, 3);
  const start = Math.max(
    0,
    Math.min(
      cursorRow - Math.floor(viewport / 2),
      Math.max(lines.length - viewport, 0),
    ),
  );
  const end = Math.min(start + viewport, lines.length);
  return (
    (start > 0 ? "↑ more\n" : "") +
    lines.slice(start, end).join("\n") +
    (end < lines.length ? "\n↓ more" : "")
  );
}

export function reducer(
  state: TuiState,
  action: Action,
  context: InstallContext,
): TuiState {
  switch (action.type) {
    case "resize":
      return { ...state, width: action.width, height: action.height };
    case "key":
      return reduceKey(state, action.key, context);
  }
}

function reduceKey(
  state: TuiState,
  name: string,
  context: InstallContext,
): TuiState {
  const rows: Array<
    | { kind: "tool"; row: ToolRow }
    | { kind: "link"; link: ContextLink }
    | { kind: "special"; pkg: ContextPackage }
  > =
    state.step === 1
      ? toolRowsGrouped(context).map((row) => ({ kind: "tool" as const, row }))
      : stepTwoRows(context, state);

  switch (name) {
    case "up":
      return { ...state, cursor: Math.max(0, state.cursor - 1) };
    case "down":
      return {
        ...state,
        cursor: Math.max(0, Math.min(rows.length - 1, state.cursor + 1)),
      };
    case "space": {
      if (state.step === 1) {
        const entry = rows[state.cursor] as
          | { kind: "tool"; row: ToolRow }
          | undefined;
        if (!entry || entry.row.locked) return state; // locked rows ignore the key
        return {
          ...state,
          selected: {
            ...state.selected,
            [entry.row.id]: !state.selected[entry.row.id],
          },
        };
      }
      const entry = rows[state.cursor] as
        | { kind: "link"; link: ContextLink }
        | { kind: "special"; pkg: ContextPackage }
        | undefined;
      if (!entry) return state;
      if (entry.kind === "link") return toggleLink(state, entry.link.name);
      return toggleSpecial(state, entry.pkg.id);
    }
    case "enter":
      if (state.step === 1) {
        return { ...state, step: 2, cursor: 0 };
      }
      // Confirm: merge step-2 extra installs into the tool selections so
      // main.ts applies code/duti-defaults exactly like any chosen tool.
      return {
        ...state,
        submitted: true,
        selected: {
          ...state.selected,
          ...Object.fromEntries(
            Object.entries(state.special).filter(([, v]) => v),
          ),
        },
      };
    default:
      return state;
  }
}

export interface MappedKey {
  key: string;
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

/** Normalizes Ink's (input, key) pair onto the app key vocabulary. */
export function mapInkKey(input: string, key: InkKeyFlags): MappedKey | null {
  if (key.upArrow) return { key: "up" };
  if (key.downArrow) return { key: "down" };
  if (key.return) return { key: "enter" };
  if (key.escape) return { key: "esc" };
  if (key.backspace || key.delete) return { key: "backspace" };
  if (input === " ") return { key: "space" };
  if (key.ctrl && input === "c") return { key: "ctrl+c" };
  if (input === "q" && !key.ctrl && !key.meta) return { key: "q" };
  return null;
}

export interface AppProps {
  context: InstallContext;
  /** Test seam: seeds extra selections. */
  initialSelected?: Record<string, boolean>;
  /** Test seam: deterministic terminal size instead of the real stdout. */
  fixedSize?: { width: number; height: number };
  /** main.ts: receives the final state on submission, immediately before exit. */
  onSubmit?: (state: TuiState) => void;
}

export function App({
  context,
  initialSelected,
  fixedSize,
  onSubmit,
}: AppProps): React.ReactElement {
  const [state, dispatch] = useReducer(
    (s: TuiState, a: Action) => reducer(s, a, context),
    undefined,
    () => initialState(context, initialSelected),
  );
  const stateRef = useRef(state);
  stateRef.current = state;
  const { exit } = useApp();
  const { stdout } = useStdout();

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

  useEffect(() => {
    if (state.submitted) {
      onSubmit?.(stateRef.current);
      exit();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.submitted, exit]);

  useInput((input, key) => {
    const mapped = mapInkKey(input, key);
    if (!mapped) return;
    if (mapped.key === "q" || mapped.key === "ctrl+c") {
      // Quit before confirm: submits nothing (main maps to exit 10, zero writes).
      exit();
      return;
    }
    dispatch({ type: "key", key: mapped.key });
  });

  return (
    <Text>
      {state.step === 1 ? toolView(state, context) : linkView(state, context)}
    </Text>
  );
}
