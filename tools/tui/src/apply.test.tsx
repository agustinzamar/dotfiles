// Work unit 9 (ink-ui): component-driven apply screen. The apply phase used to
// print 🔧/✅/❌ lines through a console reporter; it now renders @inkjs/ui
// Spinner + ProgressBar + StatusMessage/Badge in a tiny Ink tree fed by a
// bridge. The reducer is pure and unit-tested; frame tests assert rendered
// output. Ink normalizes a bare \x1b[0m reset into attribute-specific closes
// (\x1b[39m color, \x1b[22m bold/dim), so frame assertions check the rendered
// closes, never the constants.
import { afterEach, describe, expect, test } from "bun:test";
import chalk from "chalk";
import { cleanup, render } from "ink-testing-library";
import {
  ApplyScreen,
  ApplyUiBridge,
  applyReducer,
  initialState,
} from "./apply";

// The test worker disables color detection, but the point of these frame tests
// is asserting ink's RENDERED style closes. Force chalk level 1 so @inkjs/ui/
// ink emit real codes — chalk never emits a bare \x1b[0m; it uses
// attribute-specific closes (\x1b[39m colors, \x1b[22m bold/dim, \x1b[27m
// reverse), exactly what production terminals see.
chalk.level = 1;

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

afterEach(() => {
  cleanup();
});

/** Visible-text helper: strips every ANSI escape so text assertions never
 *  depend on style codes. */
function stripAnsi(frame: string): string {
  return frame.replace(/\x1b\[[0-9;]*m/g, "");
}

// ---------------------------------------------------------------------------
// applyReducer — pure state transitions fed by the apply bridge
// ---------------------------------------------------------------------------

describe("applyReducer", () => {
  test("progress moves the running step and records done/total", () => {
    const s = applyReducer(initialState(), {
      type: "progress",
      label: "git",
      done: 2,
      total: 5,
    });
    expect(s.phase).toBe("running");
    expect(s.currentLabel).toBe("git");
    expect(s.done).toBe(2);
    expect(s.total).toBe(5);
    expect(s.failed).toBe(false);
  });

  test("result appends and marks failure on any failed step", () => {
    let s = applyReducer(initialState(), {
      type: "progress",
      label: "git",
      done: 0,
      total: 2,
    });
    s = applyReducer(s, {
      type: "result",
      status: "installed",
      label: "git",
      output: "ok",
    });
    expect(s.results).toEqual([
      { status: "installed", label: "git", output: "ok" },
    ]);
    expect(s.failed).toBe(false);
    s = applyReducer(s, {
      type: "result",
      status: "failed",
      label: "hunk",
      output: "boom",
    });
    expect(s.failed).toBe(true);
    expect(s.results[1]!.status).toBe("failed");
  });

  test("error lines accumulate for loud interruption summaries", () => {
    let s = applyReducer(initialState(), {
      type: "error",
      line: "❌ Interrupted during apply",
    });
    s = applyReducer(s, { type: "error", line: "completed: none" });
    expect(s.errors).toEqual([
      "❌ Interrupted during apply",
      "completed: none",
    ]);
  });

  test("finished pins the phase; later events are inert (terminal)", () => {
    let s = applyReducer(initialState(), {
      type: "progress",
      label: "git",
      done: 0,
      total: 1,
    });
    s = applyReducer(s, { type: "finished", ok: true });
    expect(s.phase).toBe("done");
    expect(s.failed).toBe(false);
    const frozen = s;
    // A late event (e.g. an abort summary racing the finish) must not mutate.
    s = applyReducer(s, {
      type: "result",
      status: "failed",
      label: "late",
      output: "x",
    });
    expect(s).toBe(frozen);
  });

  test("finished(ok:false) marks the run failed", () => {
    const s = applyReducer(initialState(), { type: "finished", ok: false });
    expect(s.phase).toBe("done");
    expect(s.failed).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// ApplyScreen frame tests — bridge-fed, asserted on rendered output
// ---------------------------------------------------------------------------

describe("ApplyScreen frame", () => {
  test("live frame shows the running Spinner label and then StatusMessage results", async () => {
    const ui = new ApplyUiBridge();
    const app = render(<ApplyScreen ui={ui} />);
    await delay(20);
    ui.progress("brew install --cask ghostty", 0, 3);
    await delay(20);
    expect(stripAnsi(app.lastFrame() ?? "")).toContain(
      "brew install --cask ghostty",
    );
    ui.result("installed", "ghostty", "ok");
    await delay(20);
    expect(stripAnsi(app.lastFrame() ?? "")).toContain("ghostty installed");
    app.unmount();
  });

  test("a failed step renders the red icon with attribute-specific closes, never a bare \\x1b[0m", async () => {
    const ui = new ApplyUiBridge();
    const app = render(<ApplyScreen ui={ui} />);
    await delay(20);
    ui.progress("brew install ghostty", 0, 1);
    await delay(20);
    ui.result("failed", "ghostty", "exit 7");
    await delay(20);
    const frame = app.lastFrame() ?? "";
    // Red status icon (figures.cross) with ink's color close...
    expect(frame).toContain("\x1b[31m");
    expect(frame).toContain("\x1b[39m");
    // ...and the dim failure output with its bold/dim close...
    expect(frame).toContain("\x1b[2m");
    expect(frame).toContain("\x1b[22m");
    // ...while a bare reset never appears (ink normalizes it away).
    expect(frame).not.toContain("\x1b[0m");
    expect(stripAnsi(frame)).toContain("ghostty install failed");
    expect(stripAnsi(frame)).toContain("exit 7");
    app.unmount();
  });

  test("skipped steps render the warning variant", async () => {
    const ui = new ApplyUiBridge();
    const app = render(<ApplyScreen ui={ui} />);
    await delay(20);
    ui.progress("dot git", 0, 1);
    await delay(20);
    ui.result("skipped", "dot git", "dependency failed");
    await delay(20);
    expect(stripAnsi(app.lastFrame() ?? "")).toContain(
      "dot git skipped: dependency failed",
    );
    app.unmount();
  });

  test("the interruption summary surfaces as an error message", async () => {
    const ui = new ApplyUiBridge();
    const app = render(<ApplyScreen ui={ui} />);
    await delay(20);
    ui.error("❌ Interrupted during apply\ncompleted: none\npending: git");
    await delay(20);
    expect(stripAnsi(app.lastFrame() ?? "")).toContain(
      "Interrupted during apply",
    );
    app.unmount();
  });

  test("finished(ok) exits the app leaving a green DONE badge in the final frame", async () => {
    const ui = new ApplyUiBridge();
    const app = render(<ApplyScreen ui={ui} />);
    await delay(20);
    ui.progress("brew install git", 0, 1);
    await delay(20);
    ui.result("installed", "git", "ok");
    ui.finished(true);
    await delay(60);
    const frame = app.lastFrame() ?? "";
    expect(frame).toContain("\x1b[32m"); // green badge color
    expect(frame).toContain("\x1b[39m"); // attribute-specific color close
    expect(stripAnsi(frame)).toContain("DONE");
    app.unmount();
  });

  test("failed finishes leave a red FAILED badge", async () => {
    const ui = new ApplyUiBridge();
    const app = render(<ApplyScreen ui={ui} />);
    await delay(20);
    ui.progress("brew install git", 0, 1);
    await delay(20);
    ui.result("failed", "git", "boom");
    ui.finished(false);
    await delay(60);
    const frame = app.lastFrame() ?? "";
    expect(frame).toContain("\x1b[31m");
    expect(stripAnsi(frame)).toContain("FAILED");
    app.unmount();
  });
});
