// Task 5.1 (RED first): pins the exact stdout/stderr string contract that
// main.ts must emit in --context/--dry-run flag mode and the interactive
// loop. Every expected literal below is copied verbatim from
// cmd/dot-tui/main.go and traces to dot-cli-bootstrap "Non-Interactive Flag
// Mode" / "Interactive Loop Persists Then Applies" scenarios. main.ts stays
// thin (ADR-1); these are the only unit seams — full CLI behavior is gated by
// Bats in Phases 6/8.
import {
  applyConfirmed,
  EXIT_ABORTED,
  EXIT_ERROR,
  EXIT_OK,
  failedLine,
  installedLine,
  LINK_FAILED,
  LINK_OK,
  parseFlags,
  progressLine,
  roundExitCode,
  skippedLine,
  taskLine,
  TUI_VERSION,
} from "./main";
import type { InstallContext } from "./context";
import { describe, expect, test } from "bun:test";
import type { Runner } from "./plan";

function recordingRunner(
  calls: string[],
  behavior?: (op: string) => { output: string; err?: Error },
): Runner {
  return async (operation) => {
    calls.push(operation);
    await new Promise((r) => setTimeout(r, 0));
    return behavior ? behavior(operation) : { output: "ok" };
  };
}

describe("TUI_VERSION binary contract", () => {
  test("matches the marker dot_runtime_path in bin/dot gates on", () => {
    expect(TUI_VERSION).toBe("dot-tui-context-v13");
  });
});

describe("flag parsing accepts Go-style single-dash forms", () => {
  test("no flags: dryRun false, no context", () => {
    expect(parseFlags([])).toEqual({
      dryRun: false,
      context: "",
    });
  });

  test("-dry-run and --dry-run set dryRun", () => {
    expect(parseFlags(["-dry-run"]).dryRun).toBe(true);
    expect(parseFlags(["--dry-run"]).dryRun).toBe(true);
  });

  test("-context <path> and = form", () => {
    expect(parseFlags(["--context", "/tmp/c.json"])).toMatchObject({
      context: "/tmp/c.json",
    });
    expect(parseFlags(["-context=/tmp/c.json"])).toMatchObject({
      context: "/tmp/c.json",
    });
    expect(parseFlags(["--context", "c.json", "--dry-run"])).toEqual({
      dryRun: true,
      context: "c.json",
    });
  });
});

describe("stdout string contract (verbatim from main.go Printf formats)", () => {
  // dot-cli-bootstrap: "print one `<label>: <command>` line per planned task"
  test("plan lines: `%s: %s`", () => {
    expect(taskLine("Git", "brew install git")).toBe("Git: brew install git");
  });

  // progress fires once before each component's first executed task
  test("progress line: `🔧 %s...`", () => {
    expect(progressLine("Git")).toBe("🔧 Git...");
  });

  // dot-cli-bootstrap Apply scenario: per-component result lines
  test("installed result: `✅ %s installed`", () => {
    expect(installedLine("Git")).toBe("✅ Git installed");
  });

  test("skipped result: `⚠️ %s skipped: %s`", () => {
    expect(skippedLine("Git", "dependency failed")).toBe(
      "⚠️ Git skipped: dependency failed",
    );
  });

  // stderr on component failure; output follows on its own line
  test("failed result header: `❌ %s install failed`", () => {
    expect(failedLine("Git")).toBe("❌ Git install failed");
  });

  // interactive link confirmations (dot-cli-bootstrap Interactive Loop)
  test("link success confirmation is exact", () => {
    expect(LINK_OK).toBe("✅ Config links installed");
  });

  test("link failure header is exact", () => {
    expect(LINK_FAILED).toBe("❌ Config links failed");
  });
});

describe("boolean flag values (Go flag parity)", () => {
  test("-dry-run=false parses false", () => {
    expect(parseFlags(["-dry-run=false"]).dryRun).toBe(false);
    expect(parseFlags(["-dry-run=true"]).dryRun).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Task 2.8 — exit codes and the shared apply orchestration (RED first)
// ---------------------------------------------------------------------------

describe("exit-code contract", () => {
  test("a quit before confirm (null or unsubmitted) maps to exit 10", () => {
    expect(EXIT_OK).toBe(0);
    expect(EXIT_ABORTED).toBe(10);
    expect(EXIT_ERROR).toBe(1);
    expect(roundExitCode(null)).toBe(EXIT_ABORTED);
    expect(roundExitCode({ submitted: false } as never)).toBe(EXIT_ABORTED);
    expect(roundExitCode({ submitted: true } as never)).toBe(EXIT_OK);
  });
});

describe("applyConfirmed — one code path for interactive and headless", () => {
  test("dry-run prints the plan and writes nothing (zero filesystem writes)", async () => {
    const calls: string[] = [];
    const exit = await applyConfirmed(
      {
        version: 1,
        locked: ["base", "shell"],
        packages: [
          {
            id: "ghostty",
            topic: "core",
            kind: "cask",
            area: "terminal",
            locked: false,
            default: true,
          },
        ],
        links: [],
      },
      { selected: { ghostty: true }, checked: {} },
      {
        dryRun: true,
        run: recordingRunner(calls),
        linkRunner: async (name: string) => {
          calls.push(`dot link ${name}`);
        },
      },
    );
    expect(exit).toBe(EXIT_OK);
    expect(calls).toEqual([]); // nothing executed
  });

  test("confirmed apply runs brew, links, special topics, pseudo-steps in order", async () => {
    const calls: string[] = [];
    const context: InstallContext = {
      version: 1,
      locked: ["base", "shell"],
      packages: [
        {
          id: "fzf",
          topic: "core",
          kind: "brew",
          area: "shell",
          locked: true,
          default: false,
        },
        {
          id: "git",
          topic: "core",
          kind: "brew",
          area: "git",
          locked: true,
          default: false,
        },
        {
          id: "tmux",
          topic: "core",
          kind: "brew",
          area: "terminal",
          locked: true,
          default: false,
        },
        {
          id: "ghostty",
          topic: "core",
          kind: "cask",
          area: "terminal",
          locked: false,
          default: true,
        },
        {
          id: "hunk",
          topic: "git",
          kind: "brew",
          area: "git",
          locked: false,
          default: true,
        },
        {
          id: "koekeishiya/formulae",
          topic: "desktop",
          kind: "tap",
          area: "desktop",
          locked: false,
          default: false,
        },
        {
          id: "code",
          topic: "code",
          kind: "topic",
          area: "vscode",
          locked: false,
          default: false,
        },
        {
          id: "duti-defaults",
          topic: "duti",
          kind: "topic",
          area: "terminal",
          locked: false,
          default: false,
        },
      ],
      links: [
        {
          name: "zsh",
          optional: false,
          component: "shell",
          requirement: "",
          rows: [{ source: "a", target: "b", mode: "" }],
        },
        {
          name: "ghostty",
          optional: false,
          component: "terminal",
          requirement: "",
          rows: [
            { source: "a", target: "b", mode: "" },
            { source: "a", target: "c", mode: "" },
          ],
        },
        {
          name: "hunk",
          optional: false,
          component: "git",
          requirement: "hunk",
          rows: [{ source: "a", target: "b", mode: "" }],
        },
        {
          name: "agents",
          optional: true,
          component: "ai",
          requirement: "",
          rows: [{ source: "a", target: "b", mode: "" }],
        },
      ],
    };
    const exit = await applyConfirmed(
      context,
      {
        selected: {
          ghostty: true,
          hunk: true,
          code: true,
          "koekeishiya/formulae": true,
        },
        checked: { ghostty: true, agents: true },
      },
      {
        dryRun: false,
        run: recordingRunner(calls),
        linkRunner: async (name: string) => {
          calls.push(`dot link ${name}`);
        },
      },
    );
    expect(exit).toBe(EXIT_OK);

    // Brew commands (taps first), then links, then special topics and
    // pseudo-steps — never the reverse order.
    const brewCalls = calls.filter((c) => c.startsWith("brew "));
    expect(brewCalls[0]).toBe("brew tap koekeishiya/formulae"); // taps first
    expect(brewCalls).toContain("brew install hunk");
    expect(brewCalls).toContain("brew install --cask ghostty");
    const linkIdx = calls.findIndex((c) => c === "dot link ghostty");
    expect(linkIdx).toBeGreaterThan(-1);
    expect(calls.indexOf("dot link agents")).toBeGreaterThan(linkIdx);
    const specialCode = calls.findIndex((c) => c === "dot install code");
    const pseudoZsh = calls.findIndex((c) => c === "dot zsh");
    expect(specialCode).toBeGreaterThan(linkIdx);
    expect(pseudoZsh).toBeGreaterThan(-1);
  });

  test("git signing (opt-in pseudo-step) only runs when checked; runs after links when it is", async () => {
    const context: InstallContext = {
      version: 1,
      locked: [],
      packages: [],
      links: [
        {
          name: "zsh",
          optional: false,
          component: "shell",
          requirement: "",
          rows: [{ source: "a", target: "b", mode: "" }],
        },
      ],
    };
    const unchecked: string[] = [];
    await applyConfirmed(
      context,
      { selected: {}, checked: {} },
      {
        dryRun: false,
        run: recordingRunner(unchecked),
        linkRunner: async (name: string) => {
          unchecked.push(`dot link ${name}`);
        },
      },
    );
    expect(unchecked).not.toContain("dot git");

    const checked: string[] = [];
    await applyConfirmed(
      context,
      { selected: {}, checked: { zsh: true, "git-signing": true } },
      {
        dryRun: false,
        run: recordingRunner(checked),
        linkRunner: async (name: string) => {
          checked.push(`dot link ${name}`);
        },
      },
    );
    expect(checked).toContain("dot git");
    expect(checked.indexOf("dot git")).toBeGreaterThan(
      checked.indexOf("dot link zsh"),
    );
  });

  test("a tap is installed automatically when a sibling formula is selected, even though the tap itself is never in `selected`", async () => {
    const calls: string[] = [];
    const context: InstallContext = {
      version: 1,
      locked: [],
      packages: [
        {
          id: "koekeishiya/formulae",
          topic: "desktop",
          kind: "tap",
          area: "desktop",
          locked: false,
          default: false,
        },
        {
          id: "yabai",
          topic: "desktop",
          kind: "brew",
          area: "desktop",
          locked: false,
          default: false,
        },
        {
          id: "tinycast",
          topic: "utilities",
          kind: "cask",
          area: "utilities",
          locked: false,
          default: false,
        },
      ],
      links: [],
    };
    const exit = await applyConfirmed(
      context,
      // Only "yabai" is checked; the tap row is absent from `selected`
      // entirely (it is never a step-1 row — see manifest.ts toolRows).
      { selected: { yabai: true }, checked: {} },
      {
        dryRun: false,
        run: recordingRunner(calls),
        linkRunner: async () => {},
      },
    );
    expect(exit).toBe(EXIT_OK);
    const brewCalls = calls.filter((c) => c.startsWith("brew "));
    expect(brewCalls).toContain("brew tap koekeishiya/formulae");
    expect(brewCalls).toContain("brew install yabai");
    expect(brewCalls.indexOf("brew tap koekeishiya/formulae")).toBeLessThan(
      brewCalls.indexOf("brew install yabai"),
    );
    // A different topic's tap never gets pulled in.
    expect(brewCalls).not.toContain("brew install --cask tinycast");
  });

  test("mid-apply interruption exits non-zero and short-circuits the next steps", async () => {
    const calls: string[] = [];
    let interrupted = false;
    const exit = await applyConfirmed(
      {
        version: 1,
        locked: ["base", "shell"],
        packages: [
          {
            id: "git",
            topic: "core",
            kind: "brew",
            area: "git",
            locked: true,
            default: false,
          },
          {
            id: "hunk",
            topic: "git",
            kind: "brew",
            area: "git",
            locked: false,
            default: true,
          },
        ],
        links: [],
      },
      { selected: { hunk: true }, checked: {} },
      {
        dryRun: false,
        run: recordingRunner(calls, (op) => {
          if (op === "brew install hunk") interrupted = true;
          return { output: "ok" };
        }),
        linkRunner: async () => {},
        interrupt: () => interrupted,
      },
    );
    // The interrupt fires during hunk's own run, so hunk completed; every
    // lock-pseudo step after it must be short-circuited.
    expect(exit).toBe(EXIT_ERROR);
    expect(calls).toContain("brew install hunk");
    expect(calls).not.toContain("dot zsh");
    expect(calls).not.toContain("dot git");
  });

  test("a failing brew step is reported loudly and exits non-zero", async () => {
    const exit = await applyConfirmed(
      {
        version: 1,
        locked: ["base", "shell"],
        packages: [
          {
            id: "hunk",
            topic: "git",
            kind: "brew",
            area: "git",
            locked: false,
            default: true,
          },
        ],
        links: [],
      },
      { selected: { hunk: true }, checked: {} },
      {
        dryRun: false,
        run: recordingRunner([], () => ({
          output: "boom",
          err: new Error("exit 7"),
        })),
        linkRunner: async () => {},
      },
    );
    expect(exit).toBe(EXIT_ERROR);
  });
});

// -------------------------------------------------------------------------
// Work unit 9 — component-driven apply ui (@inkjs/ui Spinner/ProgressBar/
// StatusMessage/Badge). applyConfirmed keeps ONE logic path; the `ui` seam
// routes its output to the Ink apply screen instead of console lines.
// -------------------------------------------------------------------------
describe("applyConfirmed — component-driven ui seam (@inkjs/ui)", () => {
  function captureUi(): {
    ui: {
      progress(label: string, done: number, total: number): void;
      result(
        status: "installed" | "failed" | "skipped",
        label: string,
        output: string,
      ): void;
      error(line: string): void;
      finished(ok: boolean): void;
    };
    events: string[];
  } {
    const events: string[] = [];
    const ui = {
      progress(label: string, done: number, total: number) {
        events.push(`progress:${done}/${total}:${label}`);
      },
      result(
        status: "installed" | "failed" | "skipped",
        label: string,
        output: string,
      ) {
        events.push(`result:${status}:${label}:${output}`);
      },
      error(line: string) {
        events.push(`error:${line.split("\n")[0]}`);
      },
      finished(ok: boolean) {
        events.push(`finished:${ok}`);
      },
    };
    return { ui, events };
  }

  test("successful apply drives progress, results, then finished:true", async () => {
    const calls: string[] = [];
    const { ui, events } = captureUi();
    const exit = await applyConfirmed(
      {
        version: 1,
        locked: ["base", "shell"],
        packages: [
          {
            id: "ghostty",
            topic: "core",
            kind: "cask",
            area: "terminal",
            locked: false,
            default: true,
          },
        ],
        links: [],
      },
      { selected: { ghostty: true }, checked: {} },
      {
        dryRun: false,
        run: recordingRunner(calls),
        linkRunner: async () => {},
        ui,
      },
    );
    expect(exit).toBe(EXIT_OK);
    // Planned order: bootstrap, then brew steps (ghostty), then the
    // always-run locked pseudo-step (Zinit/Zsh setup). Git signing is
    // opt-in (step 2) now and unchecked here, so it's never queued.
    expect(events[0]).toBe("progress:0/3:Bootstrap (Xcode CLT + Homebrew)");
    expect(events[1]).toBe("progress:1/3:ghostty");
    expect(events[2]).toBe("progress:2/3:Zinit/Zsh setup");
    expect(events).toContain("result:installed:ghostty:ok");
    expect(events[events.length - 1]).toBe("finished:true");
  });

  test("a failed brew step reports result:failed (with output) and finished:false", async () => {
    const { ui, events } = captureUi();
    const exit = await applyConfirmed(
      {
        version: 1,
        locked: ["base", "shell"],
        packages: [
          {
            id: "hunk",
            topic: "git",
            kind: "brew",
            area: "git",
            locked: false,
            default: true,
          },
        ],
        links: [],
      },
      { selected: { hunk: true }, checked: {} },
      {
        dryRun: false,
        run: recordingRunner([], () => ({
          output: "boom",
          err: new Error("exit 7"),
        })),
        linkRunner: async () => {},
        ui,
      },
    );
    expect(exit).toBe(EXIT_ERROR);
    expect(events).toContain("result:failed:hunk:boom");
    expect(events[events.length - 1]).toBe("finished:false");
  });

  test("mid-apply interruption pushes the loud summary as an error event + finished:false", async () => {
    const calls: string[] = [];
    let interrupted = false;
    const { ui, events } = captureUi();
    const exit = await applyConfirmed(
      {
        version: 1,
        locked: ["base", "shell"],
        packages: [
          {
            id: "git",
            topic: "core",
            kind: "brew",
            area: "git",
            locked: true,
            default: false,
          },
          {
            id: "hunk",
            topic: "git",
            kind: "brew",
            area: "git",
            locked: false,
            default: true,
          },
        ],
        links: [],
      },
      { selected: { hunk: true }, checked: {} },
      {
        dryRun: false,
        run: recordingRunner(calls, (op) => {
          if (op === "brew install hunk") interrupted = true;
          return { output: "ok" };
        }),
        linkRunner: async () => {},
        interrupt: () => interrupted,
        ui,
      },
    );
    expect(exit).toBe(EXIT_ERROR);
    // The abort summary arrives through the ui as an error event, and the
    // run finishes failed — loudly, exactly like the console path.
    expect(events.some((e) => e.startsWith("error:❌ Interrupted"))).toBe(true);
    expect(events[events.length - 1]).toBe("finished:false");
  });

  test("dry-run ignores the ui seam entirely (plan stays plain lines)", async () => {
    const calls: string[] = [];
    const { ui, events } = captureUi();
    const exit = await applyConfirmed(
      {
        version: 1,
        locked: ["base", "shell"],
        packages: [
          {
            id: "ghostty",
            topic: "core",
            kind: "cask",
            area: "terminal",
            locked: false,
            default: true,
          },
        ],
        links: [],
      },
      { selected: { ghostty: true }, checked: {} },
      {
        dryRun: true,
        run: recordingRunner(calls),
        linkRunner: async () => {},
        ui,
      },
    );
    expect(exit).toBe(EXIT_OK);
    expect(events).toEqual([]); // the ui seam is not mounted for dry-run
    expect(calls).toEqual([]);
  });
});
