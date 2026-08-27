import type { ContextPackage } from "./context";

// Types kept from the merged executor (installer-execute spec): a Task is one
// operation; statuses are the exact strings the specs pin.
export interface Task {
  componentId: string;
  label: string;
  operation: string;
  dependencies: string[];
}

export interface Result {
  task: Task;
  status: "installed" | "failed" | "skipped";
  output: string;
  started: Date;
  finished: Date;
}

export type Runner = (
  operation: string,
  signal?: AbortSignal,
) => Promise<{ output: string; err?: Error }>;

export type Progress = (task: Task) => void;

/**
 * One package row -> its brew command, or null for delegated topic rows.
 */
export function brewCommandFor(packageRow: ContextPackage): string | null {
  if (packageRow.kind === "tap") return `brew tap ${packageRow.id}`;
  if (packageRow.kind === "brew") return `brew install ${packageRow.id}`;
  if (packageRow.kind === "cask") return `brew install --cask ${packageRow.id}`;
  return null; // kind "topic" is delegated to `dot install`, never planned here.
}

// Production runner ported from ShellRunner: sh -c with Homebrew update/hint
// suppression inherited on top of the current environment, combined stream
// capture. A non-zero exit maps to err while output is preserved.
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

// Sequential executor ported from ExecuteWithProgress. Check order matches the
// Go original exactly: blocked dependencies first, then cancellation, then
// progress fires immediately before the runner is invoked.
export async function executeWithProgress(
  tasks: Task[],
  run: Runner,
  signal?: AbortSignal,
  progress?: Progress,
  isCancelled?: (task: Task) => boolean,
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
    if (signal?.aborted || isCancelled?.(task)) {
      results.push({
        task,
        status: "skipped",
        output: isCancelled?.(task) ? "interrupted" : "cancelled",
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
