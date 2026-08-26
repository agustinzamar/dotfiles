// Two-step installer flow on @inkjs/ui MultiSelect (design §2, ADR-1..6):
// Step 1 is a component tool selector with an inert always-checked LockedBlock
// (shell/git essentials: zsh, fzf, git, gh, tmux + Zinit/Git-signing pseudo
// steps) rendered ABOVE the MultiSelect — locked rows are NEVER options (the
// installed MultiSelect has no per-option disabled; ADR-1). Former baseline
// rows render pre-checked via defaultValue and CAN be unchecked. Step 2 is a
// checkbox list of the ADR-3/4-filtered .main config links (agents pruned),
// all unchecked, one row per multi-target NAME (value = name). App owns ONLY
// the quit keys (q / ctrl+c, ADR-2): quitting submits nothing — main.ts maps
// that to exit 10 with zero filesystem writes. Selected/checked values cross
// into main.ts through thin adapters (adaptStepOne/adaptStepTwo) that reinsert
// locked ids as always-true (applyConfirmed-critical, ADR-3).
import { Box, Text, useApp, useInput, useStdout, type Key } from "ink";
import { Fragment, useEffect, useMemo, useRef, useState } from "react";
import { MultiSelect } from "@inkjs/ui";
import type { ContextLink, InstallContext } from "./context";
import {
  offeredLinks,
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
}

/** Seeds every locked/default row checked, every other row unchecked. Cursor
 *  and viewport bookkeeping are gone — the component owns focus/scroll. */
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

/** Step-1 component defaultValue: the pre-checked set = TOGGLEABLE rows where
 *  `row.default || row.installed`, plus the `initialSelected` test seam
 *  (truthy entries appended). Locked/pseudo ids never appear (they are not
 *  options); unchecked defaults are omitted so the user can un-check them. */
export function defaultValuesFor(
  context: InstallContext,
  initialSelected: Record<string, boolean> = {},
): string[] {
  const ids = toggleableRowsForStep(context)
    .filter((row) => row.default || row.installed === true)
    .map((row) => row.id);
  for (const [id, on] of Object.entries(initialSelected)) {
    if (on && !ids.includes(id)) ids.push(id);
  }
  return ids;
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

/**
 * Visible options the MultiSelect should show, derived from the form's
 * available height. reserveres the chrome of the current step — step 1:
 * header + locked block + hint + margin; step 2: header + hint + margin —
 * and clamps to [3, 20] so tiny terminals stay usable and huge ones don't
 * render an unwieldy list.
 */
export function visibleOptionsFor(
  height: number,
  step: 1 | 2,
  lockedCount: number,
): number {
  const reserved = step === 1 ? 2 + lockedCount + 1 : 3;
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

  // App owns ONLY the quit keys (ADR-2): arrows/space/enter belong to the
  // mounted MultiSelect. Quitting submits nothing; main.ts maps that to exit
  // 10 with zero writes, from either step.
  useInput((input, key) => {
    if (quitRequested(input, key)) {
      exit();
    }
  });

  // ADR-6: memoize per mounted step so the MultiSelect never receives a
  // deep-inequal options array from a parent re-render (which resets it to
  // defaultValue). Step 1 unmounts before step 2 mounts, so the two selections
  // never co-live.
  const lockedRows = useMemo(
    () => toolRowsGrouped(context).filter((row) => row.locked || row.pseudo),
    [context],
  );
  const step1Options = useMemo(
    () =>
      toggleableRowsForStep(context).map((row) => ({
        label: row.label,
        value: row.id,
      })),
    [context],
  );
  const step1Defaults = useMemo(
    () => defaultValuesFor(context, initialSelected),
    [context, initialSelected],
  );
  const step2Options = useMemo(
    () =>
      state.step === 2
        ? stepTwoRows(context, state).map((link) => ({
            label:
              link.rows.length > 1
                ? `${link.name} (${link.rows.length} targets)`
                : link.name,
            value: link.name,
          }))
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
          <Text bold> dot installer step 1/2: choose tools </Text>
          <LockedBlock rows={lockedRows} />
          <MultiSelect
            options={step1Options}
            defaultValue={step1Defaults}
            visibleOptionCount={visibleOptionCount}
            onSubmit={(value) => {
              // The adapter reinserts every locked/pseudo id as true (ADR-1/3)
              // and flips to step 2; step-1 MultiSelect unmounts.
              setState((s) => ({
                ...s,
                selected: adaptStepOne(value, context),
                step: 2,
              }));
            }}
          />
          <Text dimColor>
            {" "}
            ↑/↓ navigate · space toggle · enter submit · q quit{" "}
          </Text>
        </Fragment>
      ) : (
        <Fragment>
          <Text bold> dot installer step 2/2: link configs </Text>
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
