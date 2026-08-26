// Task 5.1 (RED first): pins the exact stdout/stderr string contract that
// main.ts must emit in -profile/-apply/-dry-run flag mode and the interactive
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
  defaultProfilePath,
  parseFlags,
  progressLine,
  roundExitCode,
  runFlagMode,
  skipLine,
  skippedLine,
  taskLine,
  TUI_VERSION,
} from "./main";
import type { InstallContext } from "./context";
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import type { Runner } from "./plan";

const tempDirs: string[] = [];

afterAll(async () => {
  for (const dir of tempDirs) {
    await rm(dir, { recursive: true, force: true });
  }
});

async function makeTempDir(): Promise<string> {
  const dir = await mkdtemp(path.join(tmpdir(), "dot-tui-main-test-"));
  tempDirs.push(dir);
  return dir;
}

// Fixture context mirroring the real-tree shape (locked rows + defaults +
// topic rows + requirement-gated and optional links).
async function makeContextFile(): Promise<string> {
  const dir = await makeTempDir();
  const target = path.join(dir, "context.json");
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
        id: "lazygit",
        topic: "git",
        kind: "brew",
        area: "git",
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
    ],
  };
  await writeFile(target, JSON.stringify(context));
  return target;
}

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
    expect(TUI_VERSION).toBe("dot-tui-context-v4");
  });
});

describe("flag parsing accepts Go-style single-dash forms", () => {
  test("no flags: empty profile, apply/dryRun false, no context", () => {
    expect(parseFlags([])).toEqual({
      profile: "",
      apply: false,
      dryRun: false,
      context: "",
    });
  });

  test("-profile <path>", () => {
    expect(parseFlags(["-profile", "/tmp/p.json"])).toEqual({
      profile: "/tmp/p.json",
      apply: false,
      dryRun: false,
      context: "",
    });
  });

  test("--profile alias", () => {
    expect(parseFlags(["--profile", "/tmp/p.json"])).toMatchObject({
      profile: "/tmp/p.json",
    });
  });

  test("-profile=<path> equals form", () => {
    expect(parseFlags(["-profile=/tmp/p.json"])).toMatchObject({
      profile: "/tmp/p.json",
    });
  });

  test("-apply and --apply set apply", () => {
    expect(parseFlags(["-apply"]).apply).toBe(true);
    expect(parseFlags(["--apply"]).apply).toBe(true);
  });

  test("-dry-run and --dry-run set dryRun", () => {
    expect(parseFlags(["-dry-run"]).dryRun).toBe(true);
    expect(parseFlags(["--dry-run"]).dryRun).toBe(true);
  });

  test("combined flag mode argv", () => {
    expect(parseFlags(["-profile", "p.json", "-apply"])).toEqual({
      profile: "p.json",
      apply: true,
      dryRun: false,
      context: "",
    });
  });

  test("-context <path> and = form", () => {
    expect(parseFlags(["--context", "/tmp/c.json"])).toMatchObject({
      context: "/tmp/c.json",
    });
    expect(parseFlags(["-context=/tmp/c.json"])).toMatchObject({
      context: "/tmp/c.json",
    });
    expect(parseFlags(["--context", "c.json", "--dry-run"])).toEqual({
      profile: "",
      apply: false,
      dryRun: true,
      context: "c.json",
    });
  });
});

describe("stdout string contract (verbatim from main.go Printf formats)", () => {
  // dot-cli-bootstrap: "print one `skip <id>: <reason>` line per skip entry"
  test("skip lines precede task lines: `skip %s: %s`", () => {
    expect(skipLine("git", "Homebrew is not installed")).toBe(
      "skip git: Homebrew is not installed",
    );
  });

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

describe("default profile path (interactive mode)", () => {
  test("${XDG_CONFIG_HOME:-$HOME/.config}/dot/profile.json", () => {
    expect(defaultProfilePath({ XDG_CONFIG_HOME: "/x", HOME: "/h" })).toBe(
      "/x/dot/profile.json",
    );
    expect(defaultProfilePath({ HOME: "/h" })).toBe(
      "/h/.config/dot/profile.json",
    );
  });
});

describe("boolean flag values (Go flag parity)", () => {
  test("-apply=false and -dry-run=false parse false", () => {
    expect(parseFlags(["-apply=false"]).apply).toBe(false);
    expect(parseFlags(["-dry-run=true"]).dryRun).toBe(true);
    expect(parseFlags(["-profile=p.json", "-apply=false"]).profile).toBe(
      "p.json",
    );
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
    const dir = await makeTempDir();
    const profilePath = path.join(dir, "profile.json");
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
        profilePath,
        dryRun: true,
        run: recordingRunner(calls),
        linkRunner: async (name: string) => {
          calls.push(`dot link ${name}`);
        },
      },
    );
    expect(exit).toBe(EXIT_OK);
    expect(calls).toEqual([]); // nothing executed
    expect(await Bun.file(profilePath).exists()).toBe(false);
  });

  test("confirmed apply writes the profile first, then brew, links, special topics, pseudo-steps", async () => {
    const dir = await makeTempDir();
    const profilePath = path.join(dir, "profile.json");
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
        profilePath,
        dryRun: false,
        run: recordingRunner(calls),
        linkRunner: async (name: string) => {
          calls.push(`dot link ${name}`);
        },
      },
    );
    expect(exit).toBe(EXIT_OK);

    // Profile write is FIRST and contains area ids only (active ∪ locked).
    const profile = JSON.parse(await readFile(profilePath, "utf8")) as {
      components: Record<string, boolean>;
    };
    expect(profile.components["base"]).toBe(true); // locked area
    expect(profile.components["shell"]).toBe(true); // locked area + fzf row
    expect(profile.components["git"]).toBe(true); // locked git row + hunk
    expect(profile.components["terminal"]).toBe(true); // locked tmux + ghostty
    expect(profile.components["vscode"]).toBe(true); // code row selected
    expect(profile.components["desktop"]).toBe(true); // tap row selected
    expect(profile.components["ai"]).toBeUndefined(); // agents don't activate ai
    // NO link names or links section ever appear in the profile.
    expect(JSON.stringify(profile)).not.toContain("links");
    expect(JSON.stringify(profile)).not.toContain("ghostty");
    expect(JSON.stringify(profile)).not.toContain("agents");
    expect(JSON.stringify(profile)).not.toContain("zsh");

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

  test("a tap is installed automatically when a sibling formula is selected, even though the tap itself is never in `selected`", async () => {
    const dir = await makeTempDir();
    const profilePath = path.join(dir, "profile.json");
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
          id: "raycast",
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
        profilePath,
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
    expect(brewCalls).not.toContain("brew install --cask raycast");
  });

  test("mid-apply interruption exits non-zero and short-circuits the next steps", async () => {
    const dir = await makeTempDir();
    const profilePath = path.join(dir, "profile.json");
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
        profilePath,
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
    const dir = await makeTempDir();
    const profilePath = path.join(dir, "profile.json");
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
        profilePath,
        dryRun: false,
        run: recordingRunner([], () => ({
          output: "boom",
          err: new Error("exit 7"),
        })),
        linkRunner: async () => {},
      },
    );
    expect(exit).toBe(EXIT_ERROR);
    // Partial state is reported, never silently rolled back.
    const profile = JSON.parse(await readFile(profilePath, "utf8")) as {
      components: Record<string, boolean>;
    };
    expect(profile.components["git"]).toBe(true);
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
        const dir = await makeTempDir();
        const profilePath = path.join(dir, "profile.json");
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
            profilePath,
            dryRun: false,
            run: recordingRunner(calls),
            linkRunner: async () => {},
            ui,
          },
        );
        expect(exit).toBe(EXIT_OK);
        // Planned order: bootstrap, then brew steps (ghostty), then the
        // always-run locked pseudo-steps (Zinit/Zsh setup, Git signing config).
        expect(events[0]).toBe("progress:0/4:Bootstrap (Xcode CLT + Homebrew)");
        expect(events[1]).toBe("progress:1/4:ghostty");
        expect(events[2]).toBe("progress:2/4:Zinit/Zsh setup");
        expect(events[3]).toBe("progress:3/4:Git signing config");
        expect(events).toContain("result:installed:ghostty:ok");
        expect(events[events.length - 1]).toBe("finished:true");
      });

      test("a failed brew step reports result:failed (with output) and finished:false", async () => {
        const dir = await makeTempDir();
        const profilePath = path.join(dir, "profile.json");
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
            profilePath,
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
        const dir = await makeTempDir();
        const profilePath = path.join(dir, "profile.json");
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
            profilePath,
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
        expect(events.some((e) => e.startsWith("error:❌ Interrupted"))).toBe(
          true,
        );
        expect(events[events.length - 1]).toBe("finished:false");
      });

      test("dry-run ignores the ui seam entirely (plan stays plain lines)", async () => {
        const dir = await makeTempDir();
        const profilePath = path.join(dir, "profile.json");
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
            profilePath,
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

    describe("runFlagMode — headless -apply -profile (no UI mounts)", () => {
  test("missing --context fails loudly instead of guessing", async () => {
    const dir = await makeTempDir();
    const profilePath = path.join(dir, "profile.json");
    await writeFile(profilePath, JSON.stringify({ components: { ai: true } }));
    const exit = await runFlagMode(profilePath, "", false, false);
    expect(exit).toBe(EXIT_ERROR);
  });

  test("dry-run prints the plan and leaves the profile untouched", async () => {
    const dir = await makeTempDir();
    const profilePath = path.join(dir, "profile.json");
    await writeFile(
      profilePath,
      JSON.stringify({ components: { vscode: true } }),
    );
    const contextPath = await makeContextFile();
    const calls: string[] = [];
    const exit = await runFlagMode(profilePath, contextPath, false, true, {
      run: recordingRunner(calls),
      linkRunner: async (name: string) => {
        calls.push(`dot link ${name}`);
      },
    });
    expect(exit).toBe(EXIT_OK);
    expect(calls).toEqual([]);
    expect(await readFile(profilePath, "utf8")).toBe(
      JSON.stringify({ components: { vscode: true } }),
    );
  });

  test("apply mode installs every area in the profile at area granularity", async () => {
    const dir = await makeTempDir();
    const profilePath = path.join(dir, "profile.json");
    const contextPath = await makeContextFile();
    await writeFile(
      profilePath,
      JSON.stringify({ components: { vscode: true } }),
    );
    const calls: string[] = [];
    const exit = await runFlagMode(profilePath, contextPath, true, false, {
      run: recordingRunner(calls),
      linkRunner: async (name: string) => {
        calls.push(`dot link ${name}`);
      },
    });
    expect(exit).toBe(EXIT_OK);
    // vscode active: the code topic row (and only it) is applied via dot.
    expect(calls).toContain("dot install code");
    // Locked areas/rows are always part of the plan.
    expect(calls.some((c) => c === "brew install fzf")).toBe(true);
    // base/shell/git/terminal are default-active (component_default_selected
    // fallback when absent), so ghostty (terminal, default:true) installs.
    expect(calls.some((c) => c.startsWith("brew install --cask ghostty"))).toBe(
      true,
    );
    // Every offered link is linked and agents never are.
    expect(calls).toContain("dot link zsh");
    expect(calls).not.toContain("dot link agents");
  });
});
