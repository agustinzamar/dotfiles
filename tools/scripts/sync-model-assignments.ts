#!/usr/bin/env bun
// Sync per-agent model/effort assignments from the tracked KB
// (config/gentle-ai/model-assignments.json) into the live agent configs for
// OpenCode, PI, and Claude Code.
//
// Why: gentle-ai's own sync/install commands do not reliably apply this file
// to live configs. This script replaces that reliance with a direct,
// auditable write per platform.
//
// Usage: bun tools/scripts/sync-model-assignments.ts [--dry-run]

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

type ProviderAlias = {
  opencode: string | null;
  pi: string | null;
  claude: string | null;
};

type AgentEntry = {
  provider_id: string | null;
  model_id: string | null;
  effort: string | null;
};

type Kb = {
  provider_aliases: Record<string, ProviderAlias>;
  agents: Record<string, AgentEntry>;
};

type PlannedChange = { agent: string; field: string; value: string };
type Skip = { agent: string; reason: string };

type PlatformReport = {
  changes: PlannedChange[];
  skips: Skip[];
};

const dryRun = process.argv.includes("--dry-run");

const scriptDir = dirname(fileURLToPath(import.meta.url));
const kbPath = join(scriptDir, "..", "..", "config", "gentle-ai", "model-assignments.json");

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

let kb: Kb;
try {
  const raw = readFileSync(kbPath, "utf8");
  kb = JSON.parse(raw);
} catch (err) {
  fail(`Cannot read/parse KB file at ${kbPath}: ${(err as Error).message}`);
}

// --- OpenCode -------------------------------------------------------------

const opencodePath = join(homedir(), ".config", "opencode", "opencode.json");

function syncOpencode(): PlatformReport {
  const report: PlatformReport = { changes: [], skips: [] };

  let opencodeConfig: any;
  try {
    opencodeConfig = JSON.parse(readFileSync(opencodePath, "utf8"));
  } catch (err) {
    fail(`Cannot read/parse OpenCode config at ${opencodePath}: ${(err as Error).message}`);
  }

  let touched = false;
  for (const [agentName, entry] of Object.entries(kb.agents)) {
    if (entry.provider_id === null || entry.model_id === null) continue;

    const resolvedProvider = kb.provider_aliases[entry.provider_id]?.opencode;
    if (!resolvedProvider) {
      report.skips.push({ agent: agentName, reason: "no opencode provider mapping" });
      continue;
    }
    if (!opencodeConfig.agent?.[agentName]) {
      report.skips.push({ agent: agentName, reason: "no such opencode agent" });
      continue;
    }

    const newModel = `${resolvedProvider}/${entry.model_id}`;
    if (opencodeConfig.agent[agentName].model !== newModel) {
      opencodeConfig.agent[agentName].model = newModel;
      report.changes.push({ agent: agentName, field: "model", value: newModel });
      touched = true;
    }

    if (entry.effort !== null && opencodeConfig.agent[agentName].variant !== entry.effort) {
      opencodeConfig.agent[agentName].variant = entry.effort;
      report.changes.push({ agent: agentName, field: "variant", value: entry.effort });
      touched = true;
    }
  }

  if (touched && !dryRun) {
    try {
      writeFileSync(opencodePath, JSON.stringify(opencodeConfig, null, 2));
    } catch (err) {
      fail(`Cannot write OpenCode config at ${opencodePath}: ${(err as Error).message}`);
    }
  }

  return report;
}

// --- Shared frontmatter editing -------------------------------------------

type FrontmatterEdit = {
  key: string;
  value: string;
  /** Insert right after this key's line if `key` is missing. Omit to insert
   * right after the opening `---` line. */
  insertAfterKey?: string;
};

/**
 * Replace or insert `key: value` lines inside a YAML frontmatter block
 * (`---` ... `---`) without touching the markdown body or any other
 * frontmatter field. Returns null when the file has no valid frontmatter
 * block (malformed — caller should treat this as a skip, not a hard error).
 */
function applyFrontmatterEdits(
  text: string,
  edits: FrontmatterEdit[],
): { text: string; changedKeys: string[] } | null {
  const lines = text.split("\n");
  if (lines[0]?.trim() !== "---") return null;

  let closeIdx = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === "---") {
      closeIdx = i;
      break;
    }
  }
  if (closeIdx === -1) return null;

  const changedKeys: string[] = [];
  for (const edit of edits) {
    const keyRe = new RegExp(`^${edit.key}:\\s*`);
    let foundIdx = -1;
    for (let i = 1; i < closeIdx; i++) {
      if (keyRe.test(lines[i])) {
        foundIdx = i;
        break;
      }
    }

    const newLine = `${edit.key}: ${edit.value}`;
    if (foundIdx !== -1) {
      if (lines[foundIdx] !== newLine) {
        lines[foundIdx] = newLine;
        changedKeys.push(edit.key);
      }
      continue;
    }

    let insertIdx = 1;
    if (edit.insertAfterKey) {
      const afterRe = new RegExp(`^${edit.insertAfterKey}:\\s*`);
      for (let i = 1; i < closeIdx; i++) {
        if (afterRe.test(lines[i])) {
          insertIdx = i + 1;
          break;
        }
      }
    }
    lines.splice(insertIdx, 0, newLine);
    closeIdx += 1;
    changedKeys.push(edit.key);
  }

  return { text: lines.join("\n"), changedKeys };
}

// --- PI ---------------------------------------------------------------

function syncPi(): PlatformReport {
  const report: PlatformReport = { changes: [], skips: [] };

  for (const [agentName, entry] of Object.entries(kb.agents)) {
    if (entry.provider_id === null || entry.model_id === null) continue;

    const targetPath = join(homedir(), ".pi", "agent", "agents", `${agentName}.md`);
    if (!existsSync(targetPath)) {
      report.skips.push({ agent: agentName, reason: "no such PI agent file" });
      continue;
    }

    const resolvedProvider = kb.provider_aliases[entry.provider_id]?.pi;
    if (!resolvedProvider) {
      report.skips.push({ agent: agentName, reason: "no pi provider mapping" });
      continue;
    }

    let original: string;
    try {
      original = readFileSync(targetPath, "utf8");
    } catch (err) {
      fail(`Cannot read PI agent file ${targetPath}: ${(err as Error).message}`);
    }

    const newModel = `${resolvedProvider}/${entry.model_id}`;
    const edits: FrontmatterEdit[] = [{ key: "model", value: newModel }];
    if (entry.effort !== null) {
      edits.push({ key: "thinking", value: entry.effort, insertAfterKey: "model" });
    }

    const result = applyFrontmatterEdits(original, edits);
    if (result === null) {
      report.skips.push({ agent: agentName, reason: "malformed frontmatter" });
      continue;
    }

    if (result.changedKeys.includes("model")) {
      report.changes.push({ agent: agentName, field: "model", value: newModel });
    }
    if (entry.effort !== null && result.changedKeys.includes("thinking")) {
      report.changes.push({ agent: agentName, field: "thinking", value: entry.effort });
    }

    if (result.changedKeys.length > 0 && !dryRun) {
      try {
        writeFileSync(targetPath, result.text);
      } catch (err) {
        fail(`Cannot write PI agent file ${targetPath}: ${(err as Error).message}`);
      }
    }
  }

  return report;
}

// --- Claude -------------------------------------------------------------

function syncClaude(): PlatformReport {
  const report: PlatformReport = { changes: [], skips: [] };

  for (const [agentName, entry] of Object.entries(kb.agents)) {
    if (entry.provider_id === null || entry.model_id === null) continue;
    if (entry.effort === null) continue; // expected, not an error — no note

    const targetPath = join(homedir(), ".claude", "agents", `${agentName}.md`);
    if (!existsSync(targetPath)) {
      report.skips.push({ agent: agentName, reason: "no such Claude agent file" });
      continue;
    }

    let original: string;
    try {
      original = readFileSync(targetPath, "utf8");
    } catch (err) {
      fail(`Cannot read Claude agent file ${targetPath}: ${(err as Error).message}`);
    }

    // Never touch `model:`. Insert/replace `effort:` right after `model:`.
    const result = applyFrontmatterEdits(original, [
      { key: "effort", value: entry.effort, insertAfterKey: "model" },
    ]);
    if (result === null) {
      report.skips.push({ agent: agentName, reason: "malformed frontmatter" });
      continue;
    }

    if (result.changedKeys.includes("effort")) {
      report.changes.push({ agent: agentName, field: "effort", value: entry.effort });
      if (!dryRun) {
        try {
          writeFileSync(targetPath, result.text);
        } catch (err) {
          fail(`Cannot write Claude agent file ${targetPath}: ${(err as Error).message}`);
        }
      }
    }
  }

  return report;
}

// --- Run + report ---------------------------------------------------------

const platforms: Array<{ name: string; report: PlatformReport }> = [
  { name: "OpenCode", report: syncOpencode() },
  { name: "PI", report: syncPi() },
  { name: "Claude", report: syncClaude() },
];

if (dryRun) {
  console.log("DRY RUN — no files were written.");
  console.log();
}

for (const { name, report } of platforms) {
  console.log(`=== ${name} ===`);
  const updatedCount = new Set(report.changes.map((c) => c.agent)).size;

  if (dryRun) {
    if (report.changes.length === 0) {
      console.log("  (no planned changes)");
    } else {
      for (const change of report.changes) {
        console.log(`  ${change.agent}: ${change.field} = ${change.value}`);
      }
    }
    console.log(`Would update: ${updatedCount}, Skipped: ${report.skips.length}`);
  } else {
    console.log(`Updated: ${updatedCount}, Skipped: ${report.skips.length}`);
  }

  if (report.skips.length > 0) {
    console.log("Skips:");
    for (const skip of report.skips) {
      console.log(`  ${skip.agent}: ${skip.reason}`);
    }
  }
  console.log();
}

process.exit(0);
