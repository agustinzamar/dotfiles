// AI picker (item 8, UI portion): component mount test. Frame
// technique mirrors tui.test.tsx: chalk.level=1 at module top,
// ink-testing-library render/cleanup, stripAnsi for words, afterEach(cleanup),
// small delay to let the MultiSelect paint.
import { afterEach, describe, expect, test } from "bun:test";
import chalk from "chalk";
import { cleanup, render } from "ink-testing-library";
import { AiPicker, EmptyPlan, backTarget } from "./ai";

// Force real color codes so assertions match what a terminal sees.
chalk.level = 1;

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

afterEach(() => {
  cleanup();
});

function stripAnsi(frame: string): string {
  return frame.replace(/\x1b\[[0-9;]*m/g, "");
}

describe("AiPicker mount", () => {
  test("renders the combined skill+plugin item list without crashing", async () => {
    const ui = render(<AiPicker />);
    await delay(20);
    const frame = ui.lastFrame() ?? "";
    const text = stripAnsi(frame).toLowerCase();
    // Step header paints.
    expect(text).toContain("step 1: select ai items");
    // Rows render clean labels with no kind tags.
    expect(text).not.toContain("[skill]");
    expect(text).not.toContain("[plugin]");
    // A known skill label appears.
    expect(text).toContain("matt pocock");
    // Full-coverage items carry no agent suffix (agents are chosen in step 2).
    expect(text).not.toContain("all agents");
    // Key hint paints so users know space toggles, enter continues.
    expect(text).toContain("space to toggle");
    // Never renders a raw ANSI reset that would indicate a broken frame.
    expect(frame).not.toContain(String.fromCharCode(27) + "[0m");
    ui.unmount();
  });

  test("EmptyPlan explains the empty plan instead of offering install", async () => {
    const ui = render(<EmptyPlan onBack={() => {}} />);
    await delay(20);
    const text = stripAnsi(ui.lastFrame() ?? "").toLowerCase();
    expect(text).toContain("nothing to install");
    expect(text).toContain("press enter or esc to go back");
    ui.unmount();
  });

  test("EmptyPlan calls onBack on esc", async () => {
    let backs = 0;
    const ui = render(<EmptyPlan onBack={() => backs++} />);
    await delay(20);
    ui.stdin.write("\x1b");
    await delay(20);
    expect(backs).toBe(1);
    ui.unmount();
  });
});

describe("backTarget", () => {
  test("maps every step to its esc destination", () => {
    expect(backTarget("items")).toBe("exit");
    expect(backTarget("agents")).toBe("items");
    expect(backTarget("confirm")).toBe("agents");
    expect(backTarget("running")).toBeNull();
    expect(backTarget("done")).toBeNull();
  });
});

describe("AiPicker esc navigation", () => {
  test("esc in agents step goes back to items", async () => {
    const ui = render(<AiPicker />);
    await delay(20);
    ui.stdin.write(" "); // check the highlighted item
    await delay(50);
    ui.stdin.write("\r"); // submit → agents step
    await delay(50);
    expect(stripAnsi(ui.lastFrame() ?? "").toLowerCase()).toContain(
      "step 2: select agents",
    );
    ui.stdin.write("\x1b"); // esc → back to items
    await delay(50);
    expect(stripAnsi(ui.lastFrame() ?? "").toLowerCase()).toContain(
      "step 1: select ai items",
    );
    ui.unmount();
  });

  test("confirm shows one items list and one agents list", async () => {
    const ui = render(<AiPicker />);
    await delay(20);
    ui.stdin.write(" "); // check the highlighted item
    await delay(50);
    ui.stdin.write("\r"); // submit → agents step
    await delay(50);
    ui.stdin.write(" "); // check the highlighted agent
    await delay(50);
    ui.stdin.write("\r"); // submit → confirm step
    await delay(50);
    const text = stripAnsi(ui.lastFrame() ?? "").toLowerCase();
    expect(text).toContain("confirm ai asset install");
    expect(text).toContain("items:");
    expect(text).toContain("agents:");
    // Agents are not repeated on every item line.
    expect(text).not.toContain("→");
    ui.unmount();
  });
});
