// Task 5.1 (RED first): pins the exact stdout/stderr string contract that
// main.ts must emit in -profile/-apply/-dry-run flag mode and the interactive
// loop. Every expected literal below is copied verbatim from
// cmd/dot-tui/main.go and traces to dot-cli-bootstrap "Non-Interactive Flag
// Mode" / "Interactive Loop Persists Then Applies" scenarios. main.ts stays
// thin (ADR-1); these are the only unit seams — full CLI behavior is gated by
// Bats in Phases 6/8.
import { describe, expect, test } from "bun:test";

import {
  failedLine,
  installedLine,
  LINK_FAILED,
  LINK_OK,
  defaultProfilePath,
  parseFlags,
  progressLine,
  skipLine,
  skippedLine,
  taskLine,
} from "./main";

describe("flag parsing accepts Go-style single-dash forms", () => {
  test("no flags: empty profile, apply/dryRun false", () => {
    expect(parseFlags([])).toEqual({
      profile: "",
      apply: false,
      dryRun: false,
    });
  });

  test("-profile <path>", () => {
    expect(parseFlags(["-profile", "/tmp/p.json"])).toEqual({
      profile: "/tmp/p.json",
      apply: false,
      dryRun: false,
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
