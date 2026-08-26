// Entrypoint for the Bun installer TUI (ADR-1: thin, unit-tested at pure
// seams). `--context FILE` supplies the v1 context JSON emitted by
// install/manifest.sh; exit codes are 0 success, 10 aborted-by-user (zero
// writes), any other non-zero a loud error. Confirmed apply follows the design
// sequence: atomic profile write -> planned brew installs -> `dot link <name>`
// per checked link -> `dot install code`/`dot install duti` when selected, with
// the locked pseudo-steps (`dot zsh`, `dot git`) always applied. Headless
// `-apply -profile` consumes the SAME context JSON + area-level profile through
// the identical applyConfirmed path — the two modes cannot diverge, and no UI
// mounts. Mid-apply interruption prints a loud ❌ completed-vs-pending summary.
import { createElement } from "react";
import { render } from "ink";
import { loadContext, type InstallContext } from "./context";
import {
  activeProfileAreas,
  LOCKED_PSEUDO_STEPS,
  offeredLinks,
  selectedPackages,
} from "./manifest";
import {
  brewCommandFor,
  executeWithProgress,
  shellRunner,
  type Runner,
  type Task,
} from "./plan";
import { loadProfile, saveProfile } from "./profile";
import { App, type TuiState } from "./tui";

export const EXIT_OK = 0;
export const EXIT_ABORTED = 10;
export const EXIT_ERROR = 1;

// --- String contract (pinned by main.test.ts; kept from the Go-era port).

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

/** Ports the configPath/profilePath derivation for interactive mode. */
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
  context: string;
}

export function parseFlags(argv: string[]): Flags {
  const flags: Flags = { profile: "", apply: false, dryRun: false, context: "" };
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
      case "-context":
      case "--context":
        flags.context = inlineValue ?? argv[++i] ?? "";
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

// --- Apply orchestration (the ONE code path for interactive and headless).

export interface ApplyIO {
  /** Executes one shell-command step (brew/tap). */
  run: Runner;
  /** Executes `dot link <name>` for one confirmed link. */
  linkRunner: (name: string) => Promise<void>;
}

export interface ApplyConfirmedOptions extends ApplyIO {
  profilePath: string;
  dryRun: boolean;
  /** Signal observed by the process owner (SIGINT mid-apply). */
  interrupt?: () => boolean;
  signal?: AbortSignal;
  /** Output seam; defaults to console.log (progress) / console.error. */
  report?: (line: string, stderr?: boolean) => void;
}

interface ApplyStep {
  id: string;
  label: string;
  operation: string;
}

/** Loud completed-vs-pending summary for mid-apply interruption. */
export function interruptionSummary(
  completed: string[],
  pending: string[],
): string {
  return [
    "❌ Interrupted during apply",
    `completed: ${completed.length > 0 ? completed.join(", ") : "none"}`,
    `pending: ${pending.length > 0 ? pending.join(", ") : "none"}`,
  ].join("\n");
}

/** Quit-before-confirm exit mapping: null/unsubmitted -> 10, submitted -> 0. */
export function roundExitCode(finalState: TuiState | null): number {
  return finalState && finalState.submitted ? EXIT_OK : EXIT_ABORTED;
}

/**
 * Applies the confirmed selection. Phase order is fixed (design ADR-5):
 * profile write -> brew installs (taps first) -> locked pseudo-steps ->
 * checked links -> special topic installers. A mid-apply interruption prints
 * the ❌ completed-vs-pending summary and returns EXIT_ERROR; brew failures
 * also surface loudly. Dry-run simulates: prints the plan, touches nothing.
 */
export async function applyConfirmed(
  context: InstallContext,
  selection: { selected: Record<string, boolean>; checked: Record<string, boolean> },
  opts: ApplyConfirmedOptions,
): Promise<number> {
  const report = opts.report ?? ((line: string, stderr?: boolean) => {
    if (stderr) console.error(line);
    else console.log(line);
  });

  const selectedIds = new Set(
    Object.keys(selection.selected).filter((id) => selection.selected[id]),
  );
  const areas = activeProfileAreas(context, selectedIds);
  const packages = selectedPackages(context, selectedIds);

  const brewSteps: ApplyStep[] = [];
  for (const p of packages) {
    const command = brewCommandFor(p);
    if (command !== null && p.kind !== "tap") {
      brewSteps.push({ id: p.id, label: p.id, operation: command });
    }
  }
  const tapSteps: ApplyStep[] = [];
  for (const p of packages) {
    const command = brewCommandFor(p);
    if (command !== null && p.kind === "tap") {
      tapSteps.push({ id: p.id, label: p.id, operation: command });
    }
  }
  const pseudoSteps: ApplyStep[] = LOCKED_PSEUDO_STEPS.map((s) => ({
    id: s.id,
    label: s.label,
    operation: s.command,
  }));
  const linkSteps: ApplyStep[] = context.links
    .filter((link) => selection.checked[link.name])
    .map((link) => ({
      id: link.name,
      label: `link ${link.name}`,
      operation: `dot link ${link.name}`,
    }));
  const specialSteps: ApplyStep[] = packages
    .filter((p) => p.kind === "topic")
    .map((p) => ({
      id: p.id,
      label: `install ${p.topic}`,
      operation: `dot install ${p.topic}`,
    }));
  // taps before formulas, then locked pseudo-steps, then links, then specials.
      const runSteps: ApplyStep[] = [
        // Xcode CLT + Homebrew, installed only now that the user confirmed
        // (never before the selector). PATH-independent: uses the absolute dot
        // binary path, falling back to a bare `dot` on PATH.
        {
          id: "bootstrap",
          label: "Bootstrap (Xcode CLT + Homebrew)",
          operation:
            (process.env.DOTFILES_DIR ?? "")
              ? `${process.env.DOTFILES_DIR}/bin/dot bootstrap`
              : "dot bootstrap",
        },
        ...tapSteps,
        ...brewSteps,
        ...pseudoSteps,
        ...linkSteps,
        ...specialSteps,
      ];

  // Dry-run: plan only, zero filesystem writes, exit 0.
  if (opts.dryRun) {
    report(taskLine("profile", opts.profilePath));
    for (const step of runSteps) {
      report(taskLine(step.label, step.operation));
    }
    return EXIT_OK;
  }

  const completed: string[] = [];
  const plannedLabels = runSteps.map((s) => s.label);
  let failed = false;
  const interrupted = (): boolean => opts.interrupt?.() ?? false;

  // 1. Atomic profile write (areas only; link choices are never persisted).
  if (interrupted()) {
    report(interruptionSummary([], plannedLabels), true);
    return EXIT_ERROR;
  }
  const profile = { components: Object.fromEntries(areas.map((a) => [a, true])) };
  try {
    await saveProfile(opts.profilePath, profile);
    completed.push("profile");
  } catch (err) {
    report(errorMessage(err), true);
    return EXIT_ERROR;
  }

      // 2-5. Steps in fixed order. Tap/fail results and interruption are reported.
      // Short-circuit: isCancelled checks the interrupt flag before each step,
      // so a mid-apply interrupt stops at the next step boundary instead of
      // running everything to completion.
      const tasks: Task[] = runSteps.map((step) => ({
        componentId: step.id,
        label: step.label,
        operation: step.operation,
        dependencies: [],
      }));
      const executed = await executeWithProgress(
        tasks,
        opts.run,
        opts.signal,
        (task) => report(progressLine(task.label)),
        () => interrupted(),
      );
  for (const result of executed) {
    if (result.status === "failed") {
      failed = true;
      report(failedLine(result.task.label), true);
      if (result.output !== "") {
        report(result.output, true);
      }
    } else if (result.status === "skipped") {
      report(skippedLine(result.task.label, result.output));
    } else {
      report(installedLine(result.task.label));
      completed.push(result.task.label);
    }
  }

  if (failed || interrupted()) {
    if (interrupted()) {
      const pendingLabels = plannedLabels.filter((l) => !completed.includes(l));
      report(interruptionSummary(completed, pendingLabels), true);
    }
    return EXIT_ERROR;
  }
  return EXIT_OK;
}

/** Production wrapper: SIGINT mid-apply aborts the run and reports loudly. */
export async function applyConfirmedLive(
  context: InstallContext,
  selection: { selected: Record<string, boolean>; checked: Record<string, boolean> },
  opts: ApplyConfirmedOptions,
): Promise<number> {
  const controller = new AbortController();
  let interrupted = false;
  const handler = (): void => {
    interrupted = true;
    controller.abort();
  };
  process.on("SIGINT", handler);
  try {
    return await applyConfirmed(context, selection, {
      ...opts,
      interrupt: () => interrupted || (opts.interrupt?.() ?? false),
      signal: controller.signal,
    });
  } finally {
    process.off("SIGINT", handler);
  }
}

/** Runs `dot link <name>` (link_named semantics; one name may cover many rows). */
async function runDotLink(name: string): Promise<void> {
  const proc = Bun.spawn(["dot", "link", name], {
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
    throw Object.assign(new Error(`dot link ${name} exited with code ${exitCode}`), {
      output,
    });
  }
}

// --- Headless flag mode (-apply -profile).

/**
 * Headless apply: consumes the same context JSON plus the area-level profile.
 * Rows selected = locked rows (always installed) ∪ rows whose area is enabled
 * in the profile; every offered (non-optional) link is linked; agents never.
 * Prints the plan and exits 0 unless applying.
 */
export async function runFlagMode(
  profilePath: string,
  contextPath: string,
  apply: boolean,
  dryRun: boolean,
  io: ApplyIO = { run: shellRunner, linkRunner: runDotLink },
): Promise<number> {
  if (contextPath === "") {
    console.error(
      "headless -apply -profile needs --context FILE (install/manifest.sh context JSON)",
    );
    return EXIT_ERROR;
  }
  let profile;
  try {
    profile = await loadProfile(profilePath);
  } catch (err) {
    console.error(errorMessage(err));
    return EXIT_ERROR;
  }
  let context: InstallContext;
  try {
    context = await loadContext(contextPath);
  } catch (err) {
    console.error(errorMessage(err));
    return EXIT_ERROR;
  }

  const activeAreas = new Set(
    Object.keys(profile.components).filter((id) => profile.components[id]),
  );
  const selected: Record<string, boolean> = {};
  for (const p of context.packages) {
    selected[p.id] = p.locked || activeAreas.has(p.area);
  }
  const selectedIds = new Set(Object.keys(selected).filter((id) => selected[id]));
  const checked: Record<string, boolean> = {};
  for (const link of offeredLinks(context, selectedIds).main) {
    checked[link.name] = true;
  }

  return applyConfirmedLive(context, { selected, checked }, {
    profilePath,
    dryRun: !apply || dryRun,
    ...io,
  });
}

// --- Interactive loop.

function runTuiRound(context: InstallContext): Promise<TuiState | null> {
  return new Promise((resolve) => {
    let finalState: TuiState | null = null;
    const instance = render(
      createElement(App, {
        context,
        onSubmit: (state: TuiState) => {
          finalState = state;
        },
      }),
    );
    void instance.waitUntilExit().then(() => resolve(finalState));
  });
}

export async function runInteractive(
  contextPath: string,
  dryRun: boolean,
  io: ApplyIO = { run: shellRunner, linkRunner: runDotLink },
): Promise<number> {
  let context: InstallContext;
  try {
    context = await loadContext(contextPath);
  } catch (err) {
    console.error(errorMessage(err));
    return EXIT_ERROR;
  }

  const finalState = await runTuiRound(context);
  // Quit before confirm: nothing executed, no write, no link -> exit 10.
  const round = roundExitCode(finalState);
  if (round !== EXIT_OK || !finalState) {
    return round;
  }

  return applyConfirmedLive(context, finalState, {
    profilePath: defaultProfilePath(),
    dryRun,
    ...io,
  });
}

// --- Entry (func main analog).

if (import.meta.main) {
  const flags = parseFlags(process.argv.slice(2));
  const exitCode =
    flags.profile === ""
      ? flags.context === ""
        ? await (() => {
            console.error("missing --context FILE for the interactive installer");
            return EXIT_ERROR;
          })()
        : await runInteractive(flags.context, flags.dryRun)
      : await runFlagMode(flags.profile, flags.context, flags.apply, flags.dryRun);
  if (exitCode !== 0) {
    process.exit(exitCode);
  }
}