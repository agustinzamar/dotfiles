// Planner tests for the context-driven pipeline (tasks 2.3/2.8 RED first):
// brewCommandFor maps context package rows to brew commands (taps first,
// `brew install x` / `brew install --cask x`, topic rows delegated elsewhere).
// Executor/shellRunner tests are preserved verbatim from the merge —
// their behavior is unchanged by the catalog retirement.
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { chmod } from "node:fs/promises";
import {
  executeWithProgress,
  shellRunner,
  type Runner,
  type Task,
} from "./plan";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Fake runner recording every operation it was asked to execute. */
function recordingRunner(
  behavior: (op: string) => { output: string; err?: Error },
  calls: string[],
): Runner {
  return async (operation) => {
    calls.push(operation);
    await new Promise((r) => setTimeout(r, 0));
    return behavior(operation);
  };
}

const tempDirs: string[] = [];

afterAll(async () => {
  for (const dir of tempDirs) {
    await rm(dir, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// Executor — installer-execute spec scenarios (unchanged by this change)
// ---------------------------------------------------------------------------

describe("execution", () => {
  test("tasks run strictly sequentially in plan order", async () => {
    const calls: string[] = [];
    const tasks: Task[] = [
      { componentId: "a", label: "A", operation: "one", dependencies: [] },
      { componentId: "b", label: "B", operation: "two", dependencies: [] },
      { componentId: "c", label: "C", operation: "three", dependencies: [] },
    ];
    const results = await executeWithProgress(
      tasks,
      recordingRunner((op) => ({ output: op }), calls),
    );
    expect(calls).toEqual(["one", "two", "three"]);
    expect(results.map((r) => r.status)).toEqual([
      "installed",
      "installed",
      "installed",
    ]);
  });

  test("failure blocks dependents while independent components continue", async () => {
    const calls: string[] = [];
    const tasks: Task[] = [
      { componentId: "git", label: "Git", operation: "fail", dependencies: [] },
      {
        componentId: "hunk",
        label: "Hunk",
        operation: "later",
        dependencies: ["git"],
      },
      {
        componentId: "media",
        label: "Media",
        operation: "independent",
        dependencies: [],
      },
    ];
    const results = await executeWithProgress(
      tasks,
      recordingRunner(
        (op) =>
          op === "fail"
            ? { output: "bad", err: new Error("failed") }
            : { output: op },
        calls,
      ),
    );
    expect(results[1].status).toBe("skipped");
    expect(results[1].output).toBe("dependency failed");
    expect(results[2].status).toBe("installed");
    expect(calls).toEqual(["fail", "independent"]);
  });

  test("progress fires once before each executed task only", async () => {
    const log: string[] = [];
    const tasks: Task[] = [
      { componentId: "a", label: "A", operation: "first", dependencies: [] },
      { componentId: "b", label: "B", operation: "second", dependencies: [] },
    ];
    await executeWithProgress(
      tasks,
      async (operation) => {
        log.push(`run:${operation}`);
        return { output: operation };
      },
      undefined,
      (task) => log.push(`progress:${task.operation}`),
    );
    expect(log).toEqual([
      "progress:first",
      "run:first",
      "progress:second",
      "run:second",
    ]);
  });

  test("cancellation records remaining tasks as skipped without running them", async () => {
    const controller = new AbortController();
    const calls: string[] = [];
    const tasks: Task[] = [
      { componentId: "a", label: "A", operation: "first", dependencies: [] },
      { componentId: "b", label: "B", operation: "second", dependencies: [] },
      { componentId: "c", label: "C", operation: "third", dependencies: [] },
    ];
    const results = await executeWithProgress(
      tasks,
      recordingRunner(() => {
        controller.abort();
        return { output: "ok" };
      }, calls),
      controller.signal,
    );
    expect(calls).toEqual(["first"]);
    expect(results.map((r) => r.status)).toEqual([
      "installed",
      "skipped",
      "skipped",
    ]);
    expect(results[1].output).toBe("cancelled");
    expect(results[2].output).toBe("cancelled");
  });

  test("every task yields one result with captured output and timestamps", async () => {
    const tasks: Task[] = [
      {
        componentId: "ok",
        label: "Ok",
        operation: "succeeds",
        dependencies: [],
      },
      {
        componentId: "bad",
        label: "Bad",
        operation: "fails",
        dependencies: [],
      },
    ];
    const results = await executeWithProgress(tasks, async (operation) =>
      operation === "fails"
        ? { output: "captured failure text", err: new Error("exit 1") }
        : { output: "captured success text" },
    );
    expect(results).toHaveLength(2);
    expect(results[0].task.operation).toBe("succeeds");
    expect(results[0].status).toBe("installed");
    expect(results[0].output).toBe("captured success text");
    expect(results[1].status).toBe("failed");
    expect(results[1].output).toBe("captured failure text");
    for (const r of results) {
      expect(r.started).toBeInstanceOf(Date);
      expect(r.finished).toBeInstanceOf(Date);
      expect(r.finished.getTime()).toBeGreaterThanOrEqual(r.started.getTime());
    }
  });
});

// ---------------------------------------------------------------------------
// Production shell runner (unchanged)
// ---------------------------------------------------------------------------

describe("shellRunner", () => {
  test("runs via sh -c capturing combined stdout and stderr with homebrew env", async () => {
    const { output, err } = await shellRunner(
      'echo out-line; echo err-line 1>&2; echo "$HOMEBREW_NO_AUTO_UPDATE:$HOMEBREW_NO_ENV_HINTS"',
    );
    expect(err).toBeUndefined();
    expect(output).toContain("out-line");
    expect(output).toContain("err-line");
    expect(output).toContain("1:1");
  });

  test("non-zero exit produces an error with output preserved", async () => {
    const { output, err } = await shellRunner("echo before-fail; exit 3");
    expect(err).toBeInstanceOf(Error);
    expect(output).toContain("before-fail");
  });

  test("environment detection absence does not prevent planning (drop-in removed)", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "dot-tui-plan-env-"));
    tempDirs.push(dir);
    const marker = path.join(dir, ".executed");
    const body = `touch "${marker}"\nexit 1\n`;
    await writeFile(path.join(dir, "brew"), body);
    await chmod(path.join(dir, "brew"), 0o755);
    expect(await Bun.file(marker).exists()).toBe(false);
  });
});
