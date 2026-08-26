// Component-driven apply screen (work unit 9 — @inkjs/ui adoption). The apply
// phase used to print 🔧/✅/❌ console lines; the interactive path now renders
// this tiny Ink tree: Spinner (running step), ProgressBar (steps completed /
// total), StatusMessage per-step results (success/error/warning variants) and
// a final Badge. applyConfirmed keeps its single logic path — it just feeds
// this tree through the ApplyUi seam; the console reporter stays for headless
// -apply -profile and dry-run (the spec: headless MUST NOT mount a UI).
//
// Deliberately NO useInput anywhere in this tree: ink only enables stdin raw
// mode while a useInput hook is mounted, so this screen never intercepts
// ctrl+c — SIGINT stays a real signal and applyConfirmedLive's abort handler
// keeps working (mid-apply interruption still reports loudly).
import { Badge, ProgressBar, Spinner, StatusMessage } from "@inkjs/ui";
import { Box, Text, useApp } from "ink";
import { useEffect, useReducer } from "react";
import type { Dispatch, ReactElement } from "react";

export type ApplyResultStatus = "installed" | "failed" | "skipped";

/** Output seam driven by applyConfirmed. Main connects it to the Ink tree via
 *  ApplyUiBridge; tests inject a recording mock. */
export interface ApplyUi {
  /** One step is about to run; done/total feed the ProgressBar. */
  progress(label: string, done: number, total: number): void;
  /** One step finished (installed / failed / skipped). */
  result(status: ApplyResultStatus, label: string, output: string): void;
  /** Loud stderr-equivalent line (interruption summary, profile error). */
  error(line: string): void;
  /** Apply finished; ok mirrors the exit code. */
  finished(ok: boolean): void;
}

export interface ApplyResult {
  status: ApplyResultStatus;
  label: string;
  output: string;
}

export interface ApplyState {
  phase: "running" | "done";
  /** Completed steps so far (ProgressBar value = done / total). */
  done: number;
  total: number;
  currentLabel: string | null;
  results: ApplyResult[];
  errors: string[];
  failed: boolean;
}

export type ApplyAction =
  | { type: "progress"; label: string; done: number; total: number }
  | { type: "result"; status: ApplyResultStatus; label: string; output: string }
  | { type: "error"; line: string }
  | { type: "finished"; ok: boolean };

export function initialState(): ApplyState {
  return {
    phase: "running",
    done: 0,
    total: 0,
    currentLabel: null,
    results: [],
    errors: [],
    failed: false,
  };
}

/** Pure state machine for the apply screen. Finish is terminal: a late event
 *  (e.g. an abort summary racing the final result) can never mutate a done
 *  frame. */
export function applyReducer(
  state: ApplyState,
  action: ApplyAction,
): ApplyState {
  switch (action.type) {
    case "progress":
      return {
        ...state,
        phase: "running",
        currentLabel: action.label,
        done: action.done,
        total: action.total,
      };
    case "result":
      if (state.phase === "done") return state;
      return {
        ...state,
        failed: state.failed || action.status === "failed",
        results: [
          ...state.results,
          { status: action.status, label: action.label, output: action.output },
        ],
      };
    case "error":
      if (state.phase === "done") return state;
      return { ...state, errors: [...state.errors, action.line] };
    case "finished":
      return { ...state, phase: "done", failed: !action.ok };
  }
}

/** Bridge between the async applyConfirmed pipeline and this Ink tree. Events
 *  arriving before the screen mounted are queued and flushed on register, so
 *  the first runner ticks can never be lost. */
export class ApplyUiBridge implements ApplyUi {
  private dispatch: Dispatch<ApplyAction> | null = null;
  private queue: ApplyAction[] = [];

  register(dispatch: Dispatch<ApplyAction> | null): void {
    this.dispatch = dispatch;
    if (dispatch !== null && this.queue.length > 0) {
      const pending = this.queue;
      this.queue = [];
      for (const action of pending) dispatch(action);
    }
  }

  private send(action: ApplyAction): void {
    if (this.dispatch === null) this.queue.push(action); else this.dispatch(action);
  }

  progress(label: string, done: number, total: number): void {
    this.send({ type: "progress", label, done, total });
  }

  result(status: ApplyResultStatus, label: string, output: string): void {
    this.send({ type: "result", status, label, output });
  }

  error(line: string): void {
    this.send({ type: "error", line });
  }

  finished(ok: boolean): void {
    this.send({ type: "finished", ok });
  }
}

function resultVariant(result: ApplyResult): "success" | "error" | "warning" {
  if (result.status === "installed") return "success";
  if (result.status === "failed") return "error";
  return "warning";
}

function resultMessage(result: ApplyResult): string {
  if (result.status === "installed") return `${result.label} installed`;
  if (result.status === "failed") return `${result.label} install failed`;
  return `${result.label} skipped${result.output ? `: ${result.output}` : ""}`;
}

function ResultLine({ result }: { result: ApplyResult }): ReactElement {
  return (
    <Box flexDirection="column">
      <StatusMessage variant={resultVariant(result)}>
        {resultMessage(result)}
      </StatusMessage>
      {result.status === "failed" && result.output !== "" ? (
        <Text dimColor>{result.output}</Text>
      ) : null}
    </Box>
  );
}

function percentComplete(state: ApplyState): number {
  if (state.total <= 0) return 0;
  return Math.max(
    0,
    Math.min(100, Math.round((state.done / state.total) * 100)),
  );
}

export function ApplyScreen({ ui }: { ui: ApplyUiBridge }): ReactElement {
  const [state, dispatch] = useReducer(
    applyReducer,
    undefined,
    () => initialState(),
  );
  const { exit } = useApp();

  useEffect(() => {
    ui.register(dispatch);
    return () => ui.register(null);
  }, [ui]);

  useEffect(() => {
    if (state.phase === "done") exit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.phase, exit]);

  return (
    <Box flexDirection="column" gap={1}>
      {state.phase === "running" && state.total > 0 ? (
        <ProgressBar value={percentComplete(state)} />
      ) : null}
      {state.phase === "running" && state.currentLabel !== null ? (
        <Spinner label={state.currentLabel} />
      ) : null}
      {state.errors.map((line) => (
        <StatusMessage key={line} variant="error">
          {line}
        </StatusMessage>
      ))}
      {state.results.map((result) => (
        <ResultLine
          key={`${result.status}:${result.label}`}
          result={result}
        />
      ))}
      {state.phase === "done" ? (
        <Badge color={state.failed ? "red" : "green"}>
          {state.failed ? "Failed" : "Done"}
        </Badge>
      ) : null}
    </Box>
  );
}