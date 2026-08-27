// Two-step installer flow (design §2, ADR-1..7):
// Step 1 is a hand-rolled collapsible tool selector: an inert always-checked
// LockedBlock (shell/git essentials) renders ABOVE the list — locked rows are
// NEVER options (ADR-1). Tools are grouped under per-category headers that
// start expanded and collapse independently (ADR-7); App owns ALL step-1 keys
// (arrows navigate, space toggles a focused tool, enter expands/collapses a
// focused header or submits the step from a focused tool row) since no
// library component supports mixed header/checkbox rows. Step 2 stays on
// @inkjs/ui MultiSelect: a checkbox list of the ADR-3/4-filtered .main config
// links (agents pruned), all unchecked, one row per multi-target NAME (value
// = name). App owns ONLY the quit keys on step 2 (q / ctrl+c, ADR-2): quitting
// submits nothing — main.ts maps that to exit 10 with zero filesystem writes.
// Selected/checked values cross into main.ts through thin adapters
// (adaptStepOne/adaptStepTwo) that reinsert locked ids as always-true
// (applyConfirmed-critical, ADR-3).
import { Box, Text, useApp, useInput, useStdout, type Key } from "ink";
import { Fragment, useEffect, useMemo, useRef, useState } from "react";
import { MultiSelect } from "@inkjs/ui";
import type { ContextLink, InstallContext } from "./context";
import {
  offeredLinks,
  OPTIONAL_PSEUDO_STEPS,
  toolRows,
  toolRowsGrouped,
  type LinkGrouping,
  type ToolRow,
} from "./manifest";

export interface TuiState {
  step: 1 | 2;
  /** Per-tool row selections (package ids + locked pseudo-step ids). */
  selected: Record<string, boolean>;
  /** Confirmed link names (step 2), toggled as one unit per multi-target name. */
  checked: Record<string, boolean>;
  submitted: boolean;
  /** Step-1 category collapse state (ADR-7): `false` = collapsed, anything
   *  else (including absent) = expanded — every category starts open. */
  expanded: Record<string, boolean>;
  /** Step-1 focused row: a stable index into `step1Rows(context)` (the FULL
   *  list, not the filtered-visible one), so collapsing/expanding a category
   *  elsewhere never invalidates it. */
  step1Cursor: number;
}

/** Seeds every locked/default row checked, every other row unchecked, every
 *  category expanded, focus on the first row. */
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
    selected: { ...selected, ...initialSelected },
    checked: {},
    submitted: false,
    expanded: {},
    step1Cursor: 0,
  };
}

/** Step-1 submit adapter: every locked/pseudo row id -> true REGARDLESS of
 *  value (the applyConfirmed-critical locked reinsertion, ADR-1/3), every
 *  toggleable row id -> `value.includes(id)`. Special installers
 *  (code/duti-defaults/dock/macos) are ordinary toggleable rows: present in
 *  value -> true, absent -> false. */
export function adaptStepOne(
  value: string[],
  context: InstallContext,
): Record<string, boolean> {
  const selected: Record<string, boolean> = {};
  for (const row of toolRows(context)) {
    selected[row.id] = row.locked || row.pseudo || value.includes(row.id);
  }
  return selected;
}

/** Step-2 submit adapter: one `{ [name]: true }` entry per confirmed link
 *  name. The value IS the name, so multi-target names are exactly ONE key
 *  (never per-target keys); empty value -> {} (nothing links unless checked). */
export function adaptStepTwo(value: string[]): Record<string, boolean> {
  const checked: Record<string, boolean> = {};
  for (const name of value) {
    checked[name] = true;
  }
  return checked;
}

/** Step-1 component options: `toolRowsGrouped` minus the locked/pseudo rows
 *  (ADR-1 — locked rows render as the inert block, never MultiSelect options).
 *  Same-category adjacency from the grouped order is preserved. */
export function toggleableRowsForStep(context: InstallContext): ToolRow[] {
  return toolRowsGrouped(context).filter((row) => !row.locked && !row.pseudo);
}

/** Step-1 display row: one collapsible header per category (first-seen
 *  order — same grouping as toggleableRowsForStep), followed by that
 *  category's tool rows. Headers are focusable/collapsible (ADR-7); the tool
 *  rows are the exact same set/order as toggleableRowsForStep. */
export type Step1Row =
  { kind: "header"; category: string } | { kind: "tool"; row: ToolRow };

export function step1Rows(context: InstallContext): Step1Row[] {
  const rows: Step1Row[] = [];
  let previousCategory: string | null = null;
  for (const row of toggleableRowsForStep(context)) {
    if (row.category !== previousCategory) {
      rows.push({ kind: "header", category: row.category });
      previousCategory = row.category;
    }
    rows.push({ kind: "tool", row });
  }
  return rows;
}

/** A header is always visible; a tool row is visible iff its category isn't
 *  explicitly collapsed (ADR-7: absent/true = expanded, only `false` hides). */
export function isStep1RowVisible(
  row: Step1Row,
  expanded: Record<string, boolean>,
): boolean {
  return row.kind === "header" || expanded[row.row.category] !== false;
}

export function visibleStep1Rows(
  rows: Step1Row[],
  expanded: Record<string, boolean>,
): Step1Row[] {
  return rows.filter((row) => isStep1RowVisible(row, expanded));
}

/** Moves the step-1 cursor to the next/previous VISIBLE row, skipping any
 *  row hidden by a collapsed category. Clamps at both ends — no wraparound,
 *  matching the component-driven MultiSelect's edge behavior on step 2. */
export function moveStep1Cursor(
  rows: Step1Row[],
  expanded: Record<string, boolean>,
  cursor: number,
  delta: 1 | -1,
): number {
  let next = cursor;
  for (let i = 0; i < rows.length; i++) {
    next += delta;
    if (next < 0 || next >= rows.length) return cursor;
    if (isStep1RowVisible(rows[next]!, expanded)) return next;
  }
  return cursor;
}

/** Flips one category's collapsed state (Enter on a focused header, ADR-7). */
export function toggleCategory(
  expanded: Record<string, boolean>,
  category: string,
): Record<string, boolean> {
  const isOpen = expanded[category] !== false;
  return { ...expanded, [category]: !isOpen };
}

/** Windows the VISIBLE step-1 rows around the cursor's position WITHIN that
 *  visible list, so a small terminal scrolls instead of overflowing — the
 *  hand-rolled equivalent of MultiSelect's own internal viewport. */
export function step1Window(
  visibleCount: number,
  visibleCursorIndex: number,
  optionCount: number,
): { start: number; end: number } {
  const count = Math.max(1, optionCount);
  const start = Math.max(
    0,
    Math.min(
      visibleCursorIndex - Math.floor(count / 2),
      Math.max(visibleCount - count, 0),
    ),
  );
  const end = Math.min(start + count, visibleCount);
  return { start, end };
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

/** Step-2 rows: the ADR-3-filtered config links only (no opt-in agents,
 *  no gated extra installs — extras like code/duti-defaults/dock/macos are
 *  first-class step-1 rows now). */
export function stepTwoRows(
  context: InstallContext,
  state: TuiState,
): ContextLink[] {
  return linkRowsForStep(context, state).main;
}

/** App-level quit-only contract (ADR-2): plain `q` (no ctrl/meta) and
 *  `ctrl+c` request a quit; arrows/space/return/uppercase Q and every other
 *  ctrl/meta-combo are the component's keys, not App's. */
export function quitRequested(input: string, key: Partial<Key>): boolean {
  if (key.ctrl && input === "c") return true;
  return input === "q" && !key.ctrl && !key.meta;
}

/** Banner height in terminal rows: bordered box is top border + content +
 *  bottom border, always 3 for our single-line titles. Exported so
 *  `visibleOptionsFor`'s reserved-chrome math and its tests share one
 *  source of truth instead of a duplicated magic number. */
export const BANNER_HEIGHT = 3;

/**
 * Visible options the MultiSelect should show, derived from the form's
 * available height. Reserves the chrome of the current step — step 1:
 * banner + locked block + hint + margin; step 2: banner + hint + margin —
 * and clamps to [3, 20] so tiny terminals stay usable and huge ones don't
 * render an unwieldy list.
 */
export function visibleOptionsFor(
  height: number,
  step: 1 | 2,
  lockedCount: number,
): number {
  const reserved =
    step === 1 ? BANNER_HEIGHT + 2 + lockedCount : BANNER_HEIGHT + 2;
  return Math.max(3, Math.min(height - reserved, 20));
}

export interface AppProps {
  context: InstallContext;
  /** Test seam: seeds extra selections. */
  initialSelected?: Record<string, boolean>;
  /** Test seam: deterministic terminal height for `visibleOptionCount`. */
  fixedSize?: { width: number; height: number };
  /** main.ts: receives the final state on submission, immediately before exit. */
  onSubmit?: (state: TuiState) => void;
}

/** Bigger, boxed step title — a bordered banner instead of a single line of
 *  text, so the current step reads clearly even in a scrolled/noisy
 *  terminal. Fixed 3-row height (BANNER_HEIGHT): top border, one content
 *  row, bottom border — never wraps for our short titles. */
function Banner({ children }: { children: string }): React.ReactElement {
  return (
    <Box borderStyle="round" borderColor="cyan" paddingX={1}>
      <Text bold color="cyan">
        {children}
      </Text>
    </Box>
  );
}

/** Inert always-checked row block ABOVE the step-1 MultiSelect (ADR-1): the
 *  locked essentials are visible and permanently selected, but never appear in
 *  the component's options — space/enter cannot reach them by construction. */
function LockedBlock({ rows }: { rows: ToolRow[] }): React.ReactElement {
  return (
    <Box flexDirection="column">
      {rows.map((row) => (
        <Text key={row.id}>✔ {row.label}</Text>
      ))}
    </Box>
  );
}

/** Hand-rolled, windowed, collapsible tool list (ADR-7). One line per
 *  visible row: a bold category header (▾ open / ▸ collapsed) or an indented
 *  tool row (green when checked, blue when focused, tick when checked).
 *  `focusedRow` is compared by reference — callers always pass an element
 *  straight out of the SAME `rows` array, never a reconstructed copy. */
function Step1List({
  rows,
  expanded,
  selected,
  focusedRow,
  optionCount,
}: {
  rows: Step1Row[];
  expanded: Record<string, boolean>;
  selected: Record<string, boolean>;
  focusedRow: Step1Row | undefined;
  optionCount: number;
}): React.ReactElement {
  const visible = visibleStep1Rows(rows, expanded);
  const cursorIndex = focusedRow ? visible.indexOf(focusedRow) : -1;
  const { start, end } = step1Window(
    visible.length,
    Math.max(cursorIndex, 0),
    optionCount,
  );
  const windowed = visible.slice(start, end);
  return (
    <Box flexDirection="column">
      {start > 0 && <Text dimColor>↑ more</Text>}
      {windowed.map((entry) => {
        const isFocused = entry === focusedRow;
        if (entry.kind === "header") {
          const isOpen = expanded[entry.category] !== false;
          return (
            <Text
              key={`header:${entry.category}`}
              bold
              color={isFocused ? "blue" : "cyan"}
            >
              {isFocused ? "❯ " : "  "}
              {isOpen ? "▾" : "▸"} {entry.category}
            </Text>
          );
        }
        const checked = selected[entry.row.id] === true;
        const color = isFocused ? "blue" : checked ? "green" : undefined;
        return (
          <Text key={entry.row.id} color={color}>
            {isFocused ? `❯ ${entry.row.label}` : `  ${entry.row.label}`}
            {checked ? " ✔" : ""}
          </Text>
        );
      })}
      {end < visible.length && <Text dimColor>↓ more</Text>}
    </Box>
  );
}

export function App({
  context,
  initialSelected,
  fixedSize,
  onSubmit,
}: AppProps): React.ReactElement {
  const { stdout } = useStdout();
  const [state, setState] = useState<TuiState>(() =>
    initialState(context, initialSelected),
  );
  const stateRef = useRef(state);
  stateRef.current = state;
  const { exit } = useApp();

  useEffect(() => {
    if (state.submitted) {
      onSubmit?.(stateRef.current);
      exit();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.submitted, exit]);

  // Quitting submits nothing on either step; main.ts maps that to exit 10
  // with zero writes (ADR-2). Step 1 has no library component to delegate
  // to (mixed header/checkbox rows), so App owns ALL of its keys: arrows
  // move the cursor across visible rows, space toggles a focused tool,
  // enter expands/collapses a focused header or submits from a focused
  // tool row (ADR-7). Step 2's arrows/space/enter stay MultiSelect's.
  useInput((input, key) => {
    if (quitRequested(input, key)) {
      exit();
      return;
    }
    if (stateRef.current.step !== 1) return;
    if (key.upArrow || key.downArrow) {
      const delta = key.upArrow ? -1 : 1;
      setState((s) => ({
        ...s,
        step1Cursor: moveStep1Cursor(rows1, s.expanded, s.step1Cursor, delta),
      }));
      return;
    }
    if (input === " ") {
      setState((s) => {
        const focused = rows1[s.step1Cursor];
        if (!focused || focused.kind !== "tool") return s;
        return {
          ...s,
          selected: {
            ...s.selected,
            [focused.row.id]: !s.selected[focused.row.id],
          },
        };
      });
      return;
    }
    if (key.return) {
      setState((s) => {
        const focused = rows1[s.step1Cursor];
        if (!focused) return s;
        if (focused.kind === "header") {
          return {
            ...s,
            expanded: toggleCategory(s.expanded, focused.category),
          };
        }
        // Focused a tool row: submit step 1 (ADR-1/3 locked reinsertion) and
        // flip to step 2.
        const value = Object.keys(s.selected).filter((id) => s.selected[id]);
        return { ...s, selected: adaptStepOne(value, context), step: 2 };
      });
    }
  });

  // ADR-6: memoize per mounted step so the MultiSelect never receives a
  // deep-inequal options array from a parent re-render (which resets it to
  // defaultValue). Step 1 unmounts before step 2 mounts, so the two selections
  // never co-live.

  // Locked PACKAGE rows (fzf/zoxide/eza/poppler) are force-selected —
  // still locked=true, toolRows/initialState never change — but deliberately
  // never RENDERED: every one is silent plumbing another visible tool
  // depends on (fzf's keybindings, the ls/z aliases, yazi's PDF preview),
  // never a real user decision. Only pseudo-steps show here.
  const lockedRows = useMemo(
    () => toolRowsGrouped(context).filter((row) => row.pseudo),
    [context],
  );
  const rows1 = useMemo(() => step1Rows(context), [context]);
  const step2Options = useMemo(
    () =>
      state.step === 2
        ? [
            ...stepTwoRows(context, state).map((link) => ({
              label:
                link.rows.length > 1
                  ? `${link.name} (${link.rows.length} targets)`
                  : link.name,
              value: link.name,
            })),
            // Opt-in pseudo-steps (today: git signing) are actions, not
            // config links, but share step 2's checkbox list and the same
            // `checked` map — always offered, never auto-checked.
            ...OPTIONAL_PSEUDO_STEPS.map((step) => ({
              label: step.label,
              value: step.id,
            })),
          ]
        : [],
    [context, state.step, state.selected],
  );
  const availableHeight = fixedSize ? fixedSize.height : (stdout.rows ?? 5);
  const visibleOptionCount = visibleOptionsFor(
    availableHeight,
    state.step,
    lockedRows.length,
  );

  return (
    <Box flexDirection="column">
      {state.step === 1 ? (
        <Fragment>
          <Banner>Step 1: Select tools</Banner>
          <LockedBlock rows={lockedRows} />
          <Step1List
            rows={rows1}
            expanded={state.expanded}
            selected={state.selected}
            focusedRow={rows1[state.step1Cursor]}
            optionCount={visibleOptionCount}
          />
          <Text dimColor>
            {" "}
            ↑/↓ navigate · space toggle · enter select/expand · q quit{" "}
          </Text>
        </Fragment>
      ) : (
        <Fragment>
          <Banner>Step 2: Link configs</Banner>
          <MultiSelect
            options={step2Options}
            defaultValue={[]}
            visibleOptionCount={visibleOptionCount}
            onSubmit={(value) => {
              // ADR-4: options are pruned .main links; ADR-5: enter on an
              // empty list still fires onSubmit([]) -> checked = {}.
              setState((s) => ({
                ...s,
                checked: adaptStepTwo(value),
                submitted: true,
              }));
            }}
          />
          <Text dimColor>
            {" "}
            ↑/↓ navigate · space toggle · enter apply · q quit{" "}
          </Text>
        </Fragment>
      )}
    </Box>
  );
}
