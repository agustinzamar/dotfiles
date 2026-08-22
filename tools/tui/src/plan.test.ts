import { afterAll, describe, expect, test } from "bun:test";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { COMPONENTS, type Component } from "./manifest";
import { defaultProfile, type Profile } from "./profile";
import {
  detectEnvironment,
  executeWithProgress,
  plan,
  planFrom,
  shellRunner,
  summarize,
  type Runner,
  type Task,
} from "./plan";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Independent source of truth: installer-plan spec "Environment Detection"
// pins this exact command-name list.
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

function env(...present: string[]): Record<string, boolean> {
  return Object.fromEntries(
    DETECTED_COMMANDS.map((n) => [n, present.includes(n)]),
  );
}

function comp(partial: Partial<Component> & { id: string }): Component {
  return {
    label: partial.id,
    category: "Test",
    default: false,
    required: false,
    ...partial,
  };
}

function profileWith(...ids: string[]): Profile {
  const p = defaultProfile();
  for (const c of COMPONENTS) p.components[c.id] = false;
  for (const id of ids) p.components[id] = true;
  // Required baseline cannot be disabled; drop it entirely instead so tests
  // stay about the components under examination.
  delete p.components.base;
  delete p.components.shell;
  delete p.components.git;
  delete p.components.terminal;
  for (const id of ids) if (!(id in p.components)) p.components[id] = true;
  return { components: p.components };
}

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
// Planner — installer-plan spec scenarios
// ---------------------------------------------------------------------------

describe("environment detection", () => {
  test("reports presence from PATH without running tools", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "dot-tui-plan-env-"));
    tempDirs.push(dir);
    const marker = path.join(dir, ".executed");
    for (const name of ["brew", "git"]) {
      // If anything EXECUTES these, they leave `.executed` behind — the spec
      // forbids side effects from running the tools.
      const body = `touch "${marker}"\nexit 1\n`;
      await writeFile(path.join(dir, name), body);
      await chmod(path.join(dir, name), 0o755);
    }

    const previousPath = process.env.PATH;
    process.env.PATH = dir;
    let detected: Record<string, boolean>;
    try {
      detected = detectEnvironment();
    } finally {
      process.env.PATH = previousPath;
    }

    expect(detected["brew"]).toBe(true);
    expect(detected["xcode-select"]).toBe(false);
    expect(detected["git"]).toBe(true);
    expect(detected["gh"]).toBe(false);
    expect(detected["composer"]).toBe(false);
    // No side effects: detection resolved names on PATH only.
    expect(await Bun.file(marker).exists()).toBe(false);
  });
});

describe("planning", () => {
  test("hunk rides inside the git task, never standalone", async () => {
    // Port of plan_test.go TestPlanIncludesHunkInGit (uses DefaultProfile()).
    const { tasks } = await plan(defaultProfile(), env("brew"));
    for (const task of tasks) {
      expect(task.componentId).not.toBe("hunk");
    }
    expect(
      tasks.some(
        (t) => t.componentId === "git" && t.operation.includes("hunk"),
      ),
    ).toBeTrue();
  });

  test("xcode-select --install omitted when xcode-select detected", async () => {
    const { tasks } = await plan(defaultProfile(), env("brew", "xcode-select"));
    for (const task of tasks) {
      expect(task.operation).not.toBe("xcode-select --install");
    }
    expect(tasks.length).toBeGreaterThan(0); // other base work still planned
  });

  test("xcode-select --install kept when xcode-select missing, rest still planned", async () => {
    const components = [
      comp({
        id: "base",
        label: "Base tools",
        commands: ["xcode-select --install", "dot base"],
      }),
    ];
    const { tasks, skips } = await planFrom(
      components,
      profileWith("base"),
      env(),
    );
    expect(skips).toHaveLength(0);
    expect(tasks.map((t) => t.operation)).toEqual([
      "xcode-select --install",
      "dot base",
    ]);
  });

  test("dependencies are emitted before dependents (DFS)", async () => {
    const d = comp({ id: "d", label: "Dep", commands: ["install-d"] });
    const x = comp({
      id: "x",
      label: "X",
      dependencies: ["d"],
      commands: ["install-x"],
    });
    const { tasks, skips } = await planFrom([x, d], profileWith("x"), env());
    expect(skips).toHaveLength(0);
    expect(tasks.map((t) => t.operation)).toEqual(["install-d", "install-x"]);
    // Every planned task carries its own id, label, command and dependencies.
    expect(tasks[1]).toMatchObject({
      componentId: "x",
      label: "X",
      operation: "install-x",
      dependencies: ["d"],
    });
  });

  test("shared dependency emitted exactly once, before both dependents", async () => {
    const d = comp({ id: "d", commands: ["install-d"] });
    const x = comp({ id: "x", dependencies: ["d"], commands: ["install-x"] });
    const y = comp({ id: "y", dependencies: ["d"], commands: ["install-y"] });
    const { tasks } = await planFrom([x, y, d], profileWith("x", "y"), env());
    expect(tasks.map((t) => t.componentId)).toEqual(["d", "x", "y"]);
  });

  test("unselected components produce no tasks", async () => {
    const a = comp({ id: "a", commands: ["install-a"] });
    const b = comp({ id: "b", commands: ["install-b"] });
    const { tasks } = await planFrom([a, b], profileWith(), env());
    expect(tasks).toHaveLength(0);
  });

  test("applied-set components are excluded even when enabled", async () => {
    // Port of plan_test.go TestPlanOmitsAppliedComponents.
    const { tasks } = await plan(defaultProfile(), env("brew"), { git: true });
    for (const task of tasks) {
      expect(task.componentId).not.toBe("git");
    }
    expect(tasks.some((t) => t.componentId === "terminal")).toBeTrue();
  });

  test("brew-dependent component fully skipped without brew", async () => {
    const c = comp({
      id: "c1",
      label: "C One",
      commands: ["brew install thing", "dot c1"],
    });
    const { tasks, skips } = await planFrom([c], profileWith("c1"), env());
    expect(tasks.filter((t) => t.componentId === "c1")).toHaveLength(0);
    expect(skips).toEqual([
      { componentId: "c1", reason: "Homebrew is not installed" },
    ]);
  });

  test("brew commands planned normally when brew present", async () => {
    const c = comp({
      id: "c1",
      commands: ["brew install thing", "dot c1"],
    });
    const { tasks, skips } = await planFrom(
      [c],
      profileWith("c1"),
      env("brew"),
    );
    expect(skips).toHaveLength(0);
    expect(tasks.map((t) => t.operation)).toEqual([
      "brew install thing",
      "dot c1",
    ]);
  });

  test("non-brew commands survive a brew skip inside the same component", async () => {
    const base = comp({
      id: "base",
      commands: ["xcode-select --install", "brew install cask-thing"],
    });
    const { tasks, skips } = await planFrom(
      [base],
      profileWith("base"),
      env(), // xcode-select absent, brew absent
    );
    expect(tasks.map((t) => t.operation)).toEqual(["xcode-select --install"]);
    expect(skips).toEqual([
      { componentId: "base", reason: "Homebrew is not installed" },
    ]);
  });
});

// ---------------------------------------------------------------------------
// Executor — installer-execute spec scenarios
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
    // Port of plan_test.go TestExecuteContinuesAndSkipsDependents.
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
    // The dependent's command was never executed.
    expect(calls).toEqual(["fail", "independent"]);
  });

  test("progress fires once before each executed task only", async () => {
    // Port of plan_test.go TestExecuteWithProgressReportsBeforeRunning,
    // extended with the installer-execute ordering guarantee: each progress
    // event precedes its task's run.
    const log: string[] = [];
    const failing = comp({ id: "dep", label: "Dep", commands: ["boom"] });
    const child = comp({
      id: "child",
      label: "Child",
      dependencies: ["dep"],
      commands: ["child-cmd"],
    });
    const independent = comp({
      id: "ind",
      label: "Ind",
      commands: ["ind-cmd"],
    });
    const { tasks } = await planFrom(
      [failing, child, independent],
      profileWith("dep", "child", "ind"),
      env(),
    );
    const results = await executeWithProgress(
      tasks,
      async (operation) => {
        log.push(`run:${operation}`);
        await new Promise((r) => setTimeout(r, 0));
        return operation === "boom"
          ? { output: "", err: new Error("failed") }
          : { output: operation };
      },
      undefined,
      (task) => log.push(`progress:${task.operation}`),
    );

    expect(log).toEqual([
      "progress:boom",
      "run:boom",
      // child skipped after failure — no progress event for it
      "progress:ind-cmd", // independent component still gets its own event…
      "run:ind-cmd", // …fired strictly before its run
    ]);

    const statuses = results.map((r) => r.status);
    expect(statuses).toEqual(["failed", "skipped", "installed"]);

    // Minimal Go-port case: single task gets exactly one progress event.
    const seen: string[] = [];
    const single: Task[] = [
      {
        componentId: "base",
        label: "Base",
        operation: "install",
        dependencies: [],
      },
    ];
    await executeWithProgress(
      single,
      async () => ({ output: "install" }),
      undefined,
      (task) => seen.push(task.label),
    );
    expect(seen).toEqual(["Base"]);
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
        controller.abort(); // cancellation observed mid-execution
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
// Summarize — installer-execute per-component roll-up
// ---------------------------------------------------------------------------

describe("summarize", () => {
  function result(
    task: Task,
    status: "installed" | "failed" | "skipped",
    output: string,
  ) {
    return {
      task,
      status,
      output,
      started: new Date(0),
      finished: new Date(0),
    };
  }

  test("one failed command fails the whole component", () => {
    const tasks: Task[] = [
      { componentId: "c", label: "C", operation: "first", dependencies: [] },
      { componentId: "c", label: "C", operation: "second", dependencies: [] },
    ];
    const summary = summarize([
      result(tasks[0], "installed", ""),
      result(tasks[1], "failed", "boom2"),
    ]);
    expect(summary).toHaveLength(1);
    expect(summary[0]).toMatchObject({
      componentId: "c",
      label: "C",
      status: "failed",
    });
    expect(summary[0].output).toContain("boom2");
  });

  test("all tasks installed means component installed", () => {
    const summary = summarize([
      result(
        { componentId: "c", label: "C", operation: "a", dependencies: [] },
        "installed",
        "",
      ),
    ]);
    expect(summary).toEqual([
      { componentId: "c", label: "C", status: "installed", output: "" },
    ]);
  });

  test("skipped-only component reports the skip reason", () => {
    const summary = summarize([
      result(
        { componentId: "x", label: "X", operation: "a", dependencies: ["d"] },
        "skipped",
        "dependency failed",
      ),
    ]);
    expect(summary).toEqual([
      {
        componentId: "x",
        label: "X",
        status: "skipped",
        output: "dependency failed",
      },
    ]);
  });

  test("multiple failures concatenate per component with newlines, never across", () => {
    const a1: Task = {
      componentId: "a",
      label: "A",
      operation: "a1",
      dependencies: [],
    };
    const b1: Task = {
      componentId: "b",
      label: "B",
      operation: "b1",
      dependencies: [],
    };
    const a2: Task = {
      componentId: "a",
      label: "A",
      operation: "a2",
      dependencies: [],
    };
    const summary = summarize([
      result(a1, "failed", "err-a1"),
      result(b1, "failed", "err-b1"),
      result(a2, "failed", "err-a2"),
    ]);
    const byId = Object.fromEntries(summary.map((s) => [s.componentId, s]));
    expect(byId["a"].status).toBe("failed");
    expect(byId["a"].output).toBe("err-a1\nerr-a2");
    expect(byId["b"].status).toBe("failed");
    expect(byId["b"].output).toBe("err-b1");
  });

  test("components with no results produce no summary entry", () => {
    expect(summarize([])).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Production shell runner — installer-execute "Task runs via sh" scenarios
// ---------------------------------------------------------------------------

describe("shellRunner", () => {
  test("runs via sh -c capturing combined stdout and stderr with homebrew env", async () => {
    const { output, err } = await shellRunner(
      'echo out-line; echo err-line 1>&2; echo "$HOMEBREW_NO_AUTO_UPDATE:$HOMEBREW_NO_ENV_HINTS"',
    );
    expect(err).toBeUndefined();
    expect(output).toContain("out-line");
    expect(output).toContain("err-line"); // stderr merged into output
    expect(output).toContain("1:1"); // HOMEBREW_NO_AUTO_UPDATE=1, HOMEBREW_NO_ENV_HINTS=1
  });

  test("non-zero exit produces an error with output preserved", async () => {
    const { output, err } = await shellRunner("echo before-fail; exit 3");
    expect(err).toBeInstanceOf(Error);
    expect(output).toContain("before-fail");
  });
});
