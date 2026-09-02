// AI picker (item 8, UI portion): component mount test. Frame
// technique mirrors tui.test.tsx: chalk.level=1 at module top,
// ink-testing-library render/cleanup, stripAnsi for words, afterEach(cleanup),
// small delay to let the MultiSelect paint.
import { afterEach, describe, expect, test } from "bun:test";
import chalk from "chalk";
import { cleanup, render } from "ink-testing-library";
import { AiPicker } from "./ai";

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
    // Skills and plugins render in ONE combined list (kinds tagged on every row).
    expect(text).toContain("[plugin]");
    expect(text).toContain("[skill]");
    // A known plugin id appears (manifest `label` is humanized, so match
    // case-insensitively against the id-derived text).
    expect(text).toContain("ponytail");
    // Agent tagging paints: skills resolve to every agent, plugins to a subset.
    expect(text).toContain("all agents");
    // Never renders a raw ANSI reset that would indicate a broken frame.
    expect(frame).not.toContain("\x1b[0m");
    ui.unmount();
  });
});
