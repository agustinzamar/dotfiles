// Entrypoint port of cmd/dot-tui/main.go (ADR-1: thin, unit-tested only at
// these pure seams — full CLI behavior is gated by Bats in Phases 6/8).
//
// Flag mode (-profile/-apply/-dry-run) and the interactive loop follow main.go
// line-for-line; all stdout/stderr strings are byte-identical (pinned by
// main.test.ts, traced to dot-cli-bootstrap scenarios). The pipeline body only
// runs when this file is the process entrypoint (import.meta.main ≙ Go's
// func main), so tests can import the helpers safely.
import { createElement } from "react";
import { render } from "ink";
import { loadProfile, saveProfile } from "./profile";
import {
  detectEnvironment,
  executeWithProgress,
  plan,
  shellRunner,
  summarize,
  type ComponentSummary,
  type Progress,
} from "./plan";
import { App, type TuiState } from "./tui";

// --- String contract (verbatim from main.go Printf formats; see main.test.ts).

export const skipLine = (componentId: string, reason: string): string =>
  `skip ${componentId}: ${reason}`;

export const taskLine = (label: string, operation: string): string =>
  `${label}: ${operation}`;

export const progressLine = (label: string): string => `🔧 ${label}...`;

export const installedLine = (label: string): string => `✅ ${label} installed`;

export const skippedLine = (label: string, output: string): string =>
  `⚠️ ${label} skipped: ${output}`;

export const failedLine = (label: string): string =>
  `❌ ${label} install failed`;

export const LINK_OK = "✅ Config links installed";
export const LINK_FAILED = "❌ Config links failed";

const errorMessage = (err: unknown): string =>
  err instanceof Error ? err.message : String(err);

/** Ports Go's configPath/profilePath derivation for interactive mode. */
export function defaultProfilePath(
  env: NodeJS.ProcessEnv = process.env,
): string {
  const configHome = env.XDG_CONFIG_HOME || `${env.HOME}/.config`;
  return `${configHome}/dot/profile.json`;
}

// --- Flags (Go's flag package accepts -flag, --flag, and -flag=value).

export interface Flags {
  profile: string;
  apply: boolean;
  dryRun: boolean;
}

export function parseFlags(argv: string[]): Flags {
  const flags: Flags = { profile: "", apply: false, dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    const eq = arg.indexOf("=");
    const [name, inlineValue] =
      eq === -1 ? [arg, undefined] : [arg.slice(0, eq), arg.slice(eq + 1)];
    switch (name) {
      case "-profile":
      case "--profile":
        flags.profile = inlineValue ?? argv[++i] ?? "";
        break;
      case "-apply":
      case "--apply":
        flags.apply = inlineValue === undefined || inlineValue !== "false";
        break;
      case "-dry-run":
      case "--dry-run":
        flags.dryRun = inlineValue === undefined || inlineValue !== "false";
        break;
    }
  }
  return flags;
}

// --- Shared pipeline pieces.

function printResult(result: ComponentSummary): void {
  switch (result.status) {
    case "installed":
      console.log(installedLine(result.label));
      break;
    case "skipped":
      console.log(skippedLine(result.label, result.output));
      break;
    case "failed":
      console.error(failedLine(result.label));
      if (result.output !== "") {
        console.error(result.output);
      }
      break;
  }
}

/** Progress callback: 🔧 once before each component's first task. */
const progressPrinter: Progress = (() => {
  const started = new Set<string>();
  return (task) => {
    if (started.has(task.componentId)) return;
    started.add(task.componentId);
    console.log(progressLine(task.label));
  };
})();

/**
 * Ports linkProfile(): runs `dot link` with DOT_PROFILE=<path>, returns the
 * combined output; throws {output} on non-zero exit.
 */
async function linkProfile(profilePath: string): Promise<string> {
  const proc = Bun.spawn(["dot", "link"], {
    env: { ...process.env, DOT_PROFILE: profilePath },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const output = stdout + stderr;
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    throw Object.assign(new Error(`dot link exited with code ${exitCode}`), {
      output,
    });
  }
  return output;
}

// --- Flag mode.

async function runFlagMode(
  profilePath: string,
  apply: boolean,
  dryRun: boolean,
): Promise<number> {
  let loaded;
  try {
    loaded = await loadProfile(profilePath);
  } catch (err) {
    console.error(errorMessage(err));
    return 1;
  }

  // Plan is synchronous/pure (see plan.ts): no try/catch needed.
  const { tasks, skips } = plan(loaded, detectEnvironment());
  for (const skip of skips) {
    console.log(skipLine(skip.componentId, skip.reason));
  }
  for (const task of tasks) {
    console.log(taskLine(task.label, task.operation));
  }
  if (dryRun || !apply) {
    return 0;
  }

  const results = await executeWithProgress(
    tasks,
    shellRunner,
    undefined,
    progressPrinter,
  );
  let failed = false;
  for (const component of summarize(results)) {
    printResult(component);
    failed = failed || component.status === "failed";
  }

  try {
    await saveProfile(profilePath, loaded);
  } catch (err) {
    console.error(errorMessage(err));
    return 1;
  }

  try {
    await linkProfile(profilePath);
  } catch (err) {
    console.error(LINK_FAILED);
    console.error((err as { output?: string }).output ?? "");
    return 1;
  }

  return failed ? 1 : 0;
}

// --- Interactive loop.

/**
 * One TUI round: mounts a fresh <App> (MarkApplied/ResetSubmission reduce to
 * seeding initialApplied on a new mount per ADR-2). Resolves with the final
 * state at submit, or null when the user quit without submitting.
 */
function runTuiRound(
  applied: Record<string, boolean>,
): Promise<TuiState | null> {
  return new Promise((resolve) => {
    let finalState: TuiState | null = null;
    const instance = render(
      createElement(App, {
        initialApplied: applied,
        onSubmit: (state: TuiState) => {
          finalState = state;
        },
      }),
    );
    void instance.waitUntilExit().then(() => resolve(finalState));
  });
}

async function runInteractive(): Promise<number> {
  const profilePath = defaultProfilePath();
  const applied: Record<string, boolean> = {};
  for (;;) {
    const finalState = await runTuiRound(applied);
    // Quit without submission: nothing executed, no write, no link.
    if (!finalState || !finalState.submitted) {
      return 0;
    }

    const profile = { components: { ...finalState.selected } };
    try {
      await saveProfile(profilePath, profile);
    } catch (err) {
      console.error(errorMessage(err));
      return 0;
    }

    const { tasks, skips } = plan(profile, detectEnvironment(), applied);
    for (const skip of skips) {
      console.log(skipLine(skip.componentId, skip.reason));
    }

    const results = await executeWithProgress(
      tasks,
      shellRunner,
      undefined,
      progressPrinter,
    );
    for (const component of summarize(results)) {
      printResult(component);
      // MarkApplied(successful ids): an immediately following round plans no
      // tasks for components whose every task installed.
      if (component.status === "installed") {
        applied[component.componentId] = true;
      }
    }

    try {
      await linkProfile(profilePath);
      console.log(LINK_OK);
    } catch (err) {
      console.error(LINK_FAILED);
      console.error((err as { output?: string }).output ?? "");
      // Go continues looping after a link failure in interactive mode.
    }
  }
}

// --- Entry (func main analog).

if (import.meta.main) {
  const flags = parseFlags(process.argv.slice(2));
  const exitCode =
    flags.profile === ""
      ? await runInteractive()
      : await runFlagMode(flags.profile, flags.apply, flags.dryRun);
  if (exitCode !== 0) {
    process.exit(exitCode);
  }
}
