import { COMPONENTS, type Component } from "./manifest";
import type { Profile } from "./profile";

// Types ported from internal/installer/plan.go (Task, Skip, Result) and
// cmd/dot-tui/main.go (ComponentResult). Statuses are the exact strings the
// specs pin: "installed" | "failed" | "skipped".

export interface Task {
  componentId: string;
  label: string;
  operation: string;
  dependencies: string[];
}

export interface Skip {
  componentId: string;
  reason: string;
}

export interface Result {
  task: Task;
  status: "installed" | "failed" | "skipped";
  output: string;
  started: Date;
  finished: Date;
}

export interface ComponentSummary {
  componentId: string;
  label: string;
  status: "installed" | "failed" | "skipped";
  output: string;
}

export type Runner = (
  operation: string,
  signal?: AbortSignal,
) => Promise<{ output: string; err?: Error }>;

export type Progress = (task: Task) => void;

// Environment detection is a PATH scan only — equivalent to Go's
// exec.LookPath over this fixed command list. Commands are never executed
// (installer-plan spec: "Detection reports presence without running tools").
const DETECTED_COMMANDS = [
  "brew",
  "xcode-select",
  "git",
  "gh",
  "code",
  "php",
  "composer",
  "opencode",
];

export function detectEnvironment(): Record<string, boolean> {
  const commands: Record<string, boolean> = {};
  // PATH is passed explicitly so callers (and tests) observe live mutations
  // of process.env.PATH, matching Go's exec.LookPath behavior.
  const path_ = process.env.PATH ?? "";
  for (const name of DETECTED_COMMANDS) {
    commands[name] = Bun.which(name, { PATH: path_ }) !== null;
  }
  return commands;
}

// Production runner ported from ShellRunner: sh -c with Homebrew update/hint
// suppression inherited on top of the current environment, combined stream
// capture (installer-execute spec: "Task runs via sh and captures combined
// output"). A non-zero exit maps to err while output is preserved.
export const shellRunner: Runner = async (operation, signal) => {
  const proc = Bun.spawn(["sh", "-c", operation], {
    env: {
      ...process.env,
      HOMEBREW_NO_AUTO_UPDATE: "1",
      HOMEBREW_NO_ENV_HINTS: "1",
    },
    stdout: "pipe",
    stderr: "pipe",
    signal,
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const output = stdout + stderr;
  const exitCode = await proc.exited;
  if (exitCode === 0) {
    return { output };
  }
  return { output, err: new Error(`command exited with code ${exitCode}`) };
};

/**
 * DFS planner over an explicit component list — the test seam that lets
 * plan.test.ts exercise dependency ordering with synthetic fixtures (the real
 * manifest carries no Dependencies today). plan()/planWithApplied() delegate
 * here with the verbatim COMPONENTS catalog, mirroring Go's closure over
 * Components().
 */
export function planFrom(
  components: Component[],
  profile: Profile,
  envCommands: Record<string, boolean>,
  applied?: Record<string, boolean>,
): { tasks: Task[]; skips: Skip[] } {
  // Depth-first ordering over manifest order: dependencies are visited before
  // the dependent; visiting/visited guards keep each component to one pass
  // (cycles and shared deps included), exactly as in plan.go.
  const ordered: Component[] = [];
  const visiting = new Set<string>();
  const visited = new Set<string>();
  const add = (component: Component): void => {
    if (visited.has(component.id) || visiting.has(component.id)) {
      return;
    }
    visiting.add(component.id);
    for (const dependency of component.dependencies ?? []) {
      for (const candidate of components) {
        if (candidate.id === dependency) {
          add(candidate);
        }
      }
    }
    visiting.delete(component.id);
    visited.add(component.id);
    ordered.push(component);
  };
  for (const component of components) {
    if (
      profile.components[component.id] &&
      !(applied && applied[component.id])
    ) {
      add(component);
    }
  }

  const tasks: Task[] = [];
  const skips: Skip[] = [];
  for (const component of ordered) {
    for (const command of component.commands ?? []) {
      if (command === "xcode-select --install" && envCommands["xcode-select"]) {
        continue;
      }
      if (command.startsWith("brew ") && !envCommands["brew"]) {
        skips.push({
          componentId: component.id,
          reason: "Homebrew is not installed",
        });
        break;
      }
      tasks.push({
        componentId: component.id,
        label: component.label,
        operation: command,
        dependencies: component.dependencies ?? [],
      });
    }
  }
  return { tasks, skips };
}

export function plan(
  profile: Profile,
  envCommands: Record<string, boolean>,
  applied?: Record<string, boolean>,
): { tasks: Task[]; skips: Skip[] } {
  return planFrom(COMPONENTS, profile, envCommands, applied);
}

// Sequential executor ported from ExecuteWithProgress. Check order matches Go
// exactly: blocked dependencies first, then cancellation, then progress fires
// immediately before the runner is invoked.
export async function executeWithProgress(
  tasks: Task[],
  run: Runner,
  signal?: AbortSignal,
  progress?: Progress,
): Promise<Result[]> {
  const results: Result[] = [];
  const failed = new Set<string>();
  for (const task of tasks) {
    const started = new Date();
    let blocked = false;
    for (const dependency of task.dependencies) {
      if (failed.has(dependency)) {
        blocked = true;
        break;
      }
    }
    if (blocked) {
      results.push({
        task,
        status: "skipped",
        output: "dependency failed",
        started,
        finished: new Date(),
      });
      continue;
    }
    if (signal?.aborted) {
      results.push({
        task,
        status: "skipped",
        output: "cancelled",
        started,
        finished: new Date(),
      });
      continue;
    }
    if (progress) {
      progress(task);
    }
    const { output, err } = await run(task.operation, signal);
    let status: Result["status"] = "installed";
    if (err) {
      status = "failed";
      failed.add(task.componentId);
    }
    results.push({ task, status, output, started, finished: new Date() });
  }
  return results;
}

// Per-component aggregation ported line-for-line from summarize() in
// cmd/dot-tui/main.go: first-appearance order; a failed task resets prior
// output and accumulates all failed outputs joined by newlines; a skip only
// sticks when the component has not already failed.
export function summarize(results: Result[]): ComponentSummary[] {
  const components: ComponentSummary[] = [];
  const indexes = new Map<string, number>();
  for (const result of results) {
    const id = result.task.componentId;
    let index = indexes.get(id);
    if (index === undefined) {
      indexes.set(id, components.length);
      components.push({
        componentId: id,
        label: result.task.label,
        status: result.status,
        output: "",
      });
      index = components.length - 1;
    }
    const component = components[index];
    if (result.status === "failed") {
      if (component.status !== "failed") {
        component.output = "";
      }
      component.status = "failed";
      if (result.output !== "") {
        if (component.output !== "") {
          component.output += "\n";
        }
        component.output += result.output;
      }
    } else if (result.status === "skipped" && component.status !== "failed") {
      component.status = "skipped";
      component.output = result.output;
    }
  }
  return components;
}
