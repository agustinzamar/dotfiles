#!/usr/bin/env bun
// Project sdd-profile.json (single source of truth) into the live configs:
//   - OpenCode: ~/.config/opencode/opencode.jsonc (agent model+variant,
//     surgical text edit that preserves prompts/comments) + probe cleanup in
//     opencode.json + ~/.gentle-ai/state.json model_assignments.
//   - Pi: ~/.pi/agent/agents/*.md frontmatter + subagents.json +
//     settings.json default (orchestrator) + derived flat file for installs.
//   - Claude: ~/.claude/agents/*.md effort only (unchanged legacy behavior).
//
// Usage: bun tools/scripts/sync-sdd-profile.ts [--dry-run]

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

type AgentEntry = {
  model: string;
  effort: string;
  opencode?: boolean;
  pi_file?: string;
  pi_target?: string;
};

type Profile = {
  providers: { opencode: string; pi: string };
  agents: Record<string, AgentEntry>;
};

type Change = { agent: string; field: string; value: string };
type Skip = { agent: string; reason: string };
type Report = { changes: Change[]; skips: Skip[]; notes: string[] };

const dryRun = process.argv.includes("--dry-run");
const OPENCODE_EFFORTS = new Set(["low", "medium", "high"]);
const PI_EFFORTS = new Set(["off", "minimal", "low", "medium", "high", "xhigh", "max"]);

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

const scriptDir = dirname(fileURLToPath(import.meta.url));
const profilePath = join(scriptDir, "..", "..", "ai", "gentle-ai", "sdd-profile.json");
const derivedPath = join(scriptDir, "..", "..", "ai", "gentle-ai", "model-assignments.json");

let profile: Profile;
try {
  profile = JSON.parse(readFileSync(profilePath, "utf8"));
} catch (err) {
  fail(`Cannot read/parse profile at ${profilePath}: ${(err as Error).message}`);
}

// --- Validate profile -------------------------------------------------------
for (const [name, e] of Object.entries(profile.agents)) {
  if (!e.model) fail(`Agent ${name}: missing model`);
  if (e.opencode !== false && !OPENCODE_EFFORTS.has(e.effort)) {
    fail(`Agent ${name}: effort '${e.effort}' invalid for OpenCode (low|medium|high)`);
  }
  if (!PI_EFFORTS.has(e.effort)) fail(`Agent ${name}: effort '${e.effort}' invalid for Pi`);
}

const ocProvider = profile.providers.opencode;
const piProvider = profile.providers.pi;
const opencodeRoles = Object.entries(profile.agents).filter(([, e]) => e.opencode !== false);

// --- Derived flat file (install/ai.sh + tests consume this shape) -----------
const flat: Record<string, { provider_id: string; model_id: string; effort: string }> = {};
for (const [name, e] of opencodeRoles) {
  flat[name] = { provider_id: ocProvider, model_id: e.model, effort: e.effort };
}

// --- OpenCode jsonc (surgical, preserves everything else) --------------------
const jsoncPath = join(homedir(), ".config", "opencode", "opencode.jsonc");

function setJsoncBlock(text: string, role: string, model: string, effort: string): { text: string; changed: Change[] } {
  const lines = text.split("\n");
  const openRe = new RegExp(`^    "${role}": \\{$`);
  const opens: number[] = [];
  lines.forEach((l, i) => {
    if (openRe.test(l)) opens.push(i);
  });
  if (opens.length !== 1) return { text, changed: [] }; // caller reports skip
  const open = opens[0];
  const changed: Change[] = [];
  let modelDone = false;
  let variantDone = false;
  let i = open + 1;
  for (; i < lines.length; i++) {
    const l = lines[i];
    if (/^    \},?$/.test(l)) break;
    if (!modelDone && /^      "model": ".*",?$/.test(l)) {
      const want = `      "model": "${model}",`;
      if (l !== want) {
        lines[i] = want;
        changed.push({ agent: role, field: "model", value: model });
      }
      modelDone = true;
      continue;
    }
    if (!variantDone && /^      "variant": ".*",?$/.test(l)) {
      const want = `      "variant": "${effort}",`;
      if (l !== want) {
        lines[i] = want;
        changed.push({ agent: role, field: "variant", value: effort });
      }
      variantDone = true;
    }
    if (modelDone && variantDone) break;
  }
  if (!modelDone || !variantDone) fail(`Agent ${role}: model/variant lines not found inside block`);
  return { text: lines.join("\n"), changed };
}

function syncOpencode(): Report {
  const report: Report = { changes: [], skips: [], notes: [] };
  let text: string;
  try {
    text = readFileSync(jsoncPath, "utf8");
  } catch (err) {
    fail(`Cannot read ${jsoncPath}: ${(err as Error).message}`);
  }
  for (const [name, e] of opencodeRoles) {
    const before = text;
    const res = setJsoncBlock(text, name, `${ocProvider}/${e.model}`, e.effort);
    if (res.text === before && res.changed.length === 0) {
      // Distinguish "already correct" from "block missing": re-scan.
      const openRe = new RegExp(`^    "${name}": \\{$`, "m");
      if (!openRe.test(before)) report.skips.push({ agent: name, reason: "no such opencode agent" });
      continue;
    }
    text = res.text;
    report.changes.push(...res.changed);
  }
  if (text !== readFileSync(jsoncPath, "utf8") && !dryRun) {
    writeFileSync(jsoncPath, text);
  }
  return report;
}

// --- opencode.json: drop *-probe leftovers (user asked probes gone) ----------
const jsonPath = join(homedir(), ".config", "opencode", "opencode.json");

function pruneOpencodeJson(): Report {
  const report: Report = { changes: [], skips: [], notes: [] };
  if (!existsSync(jsonPath)) return report;
  const raw = readFileSync(jsonPath, "utf8");
  const cfg = JSON.parse(raw);
  const agents = cfg.agent ?? {};
  let shadowed = 0;
  for (const key of Object.keys(agents)) {
    if (key.includes("gentle-sdd-probe")) {
      delete agents[key];
      report.changes.push({ agent: key, field: "removed", value: "probe leftover" });
    }
  }
  try {
    const jsonc = readFileSync(jsoncPath, "utf8");
    for (const key of Object.keys(agents)) {
      if (new RegExp(`^    "${key}": \\{$`, "m").test(jsonc)) shadowed++;
    }
  } catch {
    /* jsonc unreadable — skip shadow count */
  }
  if (shadowed > 0) {
    report.notes.push(`${shadowed} opencode.json entries are shadowed by opencode.jsonc (inert)`);
  }
  if (report.changes.length > 0 && !dryRun) {
    writeFileSync(jsonPath, JSON.stringify(cfg, null, 2));
  }
  return report;
}

// --- state.json + derived flat file ------------------------------------------
const statePath = join(homedir(), ".gentle-ai", "state.json");

function syncStateAndDerived(): Report {
  const report: Report = { changes: [], skips: [], notes: [] };
  const flatText = JSON.stringify(flat, null, 2) + "\n";
  let prevDerived = "";
  try {
    prevDerived = readFileSync(derivedPath, "utf8");
  } catch {
    /* missing — will create */
  }
  if (prevDerived !== flatText) {
    report.changes.push({ agent: "*", field: "derived file", value: derivedPath });
    if (!dryRun) writeFileSync(derivedPath, flatText);
  }
  if (!existsSync(statePath)) {
    report.skips.push({ agent: "*", reason: "no gentle-ai state.json" });
    return report;
  }
  const state = JSON.parse(readFileSync(statePath, "utf8"));
  if (JSON.stringify(state.model_assignments) !== JSON.stringify(flat)) {
    report.changes.push({ agent: "*", field: "state model_assignments", value: "synced" });
    if (!dryRun) {
      state.model_assignments = flat;
      writeFileSync(statePath, JSON.stringify(state, null, 2));
    }
  }
  return report;
}

// --- Shared frontmatter editing (same semantics as the retired script) --------
type FrontmatterEdit = { key: string; value: string; insertAfterKey?: string };

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

// --- Pi -----------------------------------------------------------------------
const piAgentsDir = join(homedir(), ".pi", "agent", "agents");
const subagentsPath = join(homedir(), ".pi", "agent", "subagents.json");
const piSettingsPath = join(homedir(), ".pi", "agent", "settings.json");

function syncPi(): Report {
  const report: Report = { changes: [], skips: [], notes: [] };
  for (const [name, e] of Object.entries(profile.agents)) {
    if (e.pi_target === "default") continue; // handled via settings.json below
    const file = `${e.pi_file ?? name}.md`;
    const target = join(piAgentsDir, file);
    if (!existsSync(target)) {
      report.skips.push({ agent: name, reason: "no such PI agent file" });
      continue;
    }
    const original = readFileSync(target, "utf8");
    const newModel = `${piProvider}/${e.model}`;
    const result = applyFrontmatterEdits(original, [
      { key: "model", value: newModel },
      { key: "thinking", value: e.effort, insertAfterKey: "model" },
    ]);
    if (result === null) {
      report.skips.push({ agent: name, reason: "malformed frontmatter" });
      continue;
    }
    if (result.changedKeys.includes("model")) {
      report.changes.push({ agent: name, field: "model", value: newModel });
    }
    if (result.changedKeys.includes("thinking")) {
      report.changes.push({ agent: name, field: "thinking", value: e.effort });
    }
    if (result.changedKeys.length > 0 && !dryRun) writeFileSync(target, result.text);
  }

  if (existsSync(subagentsPath)) {
    const sub = JSON.parse(readFileSync(subagentsPath, "utf8"));
    sub.model_profiles ??= {};
    let touched = false;
    for (const [name, e] of Object.entries(profile.agents)) {
      if (e.pi_target === "default") continue;
      const key = e.pi_file ?? name;
      if (!(key in sub.model_profiles)) {
        report.skips.push({ agent: name, reason: "no such subagents.json profile" });
        continue;
      }
      if (sub.model_profiles[key].effort !== e.effort) {
        sub.model_profiles[key].effort = e.effort;
        touched = true;
        report.changes.push({ agent: name, field: "subagents effort", value: e.effort });
      }
    }
    if (touched && !dryRun) writeFileSync(subagentsPath, JSON.stringify(sub, null, 2) + "\n");
  }

  const defEntry = Object.entries(profile.agents).find(([, e]) => e.pi_target === "default");
  if (defEntry && existsSync(piSettingsPath)) {
    const [defName, e] = defEntry;
    const settings = JSON.parse(readFileSync(piSettingsPath, "utf8"));
    const before = JSON.stringify(settings);
    if (settings.defaultModel !== e.model) {
      report.changes.push({ agent: defName, field: "pi defaultModel", value: e.model });
      settings.defaultModel = e.model;
    }
    if (settings.defaultThinkingLevel !== e.effort) {
      report.changes.push({ agent: defName, field: "pi defaultThinkingLevel", value: e.effort });
      settings.defaultThinkingLevel = e.effort;
    }
    const mapKey = `${piProvider}/${e.model}`;
    settings.modelThinkingLevels ??= {};
    if (settings.modelThinkingLevels[mapKey] !== e.effort) {
      report.changes.push({ agent: defName, field: `pi thinkingLevels[${mapKey}]`, value: e.effort });
      settings.modelThinkingLevels[mapKey] = e.effort;
    }
    if (!dryRun && JSON.stringify(settings) !== before) {
      writeFileSync(piSettingsPath, JSON.stringify(settings, null, 2) + "\n");
    }
  }
  return report;
}

// --- Claude (effort only, legacy behavior preserved) ---------------------------
function syncClaude(): Report {
  const report: Report = { changes: [], skips: [], notes: [] };
  for (const [name, e] of Object.entries(profile.agents)) {
    const target = join(homedir(), ".claude", "agents", `${name}.md`);
    if (!existsSync(target)) {
      report.skips.push({ agent: name, reason: "no such Claude agent file" });
      continue;
    }
    const original = readFileSync(target, "utf8");
    const result = applyFrontmatterEdits(original, [{ key: "effort", value: e.effort, insertAfterKey: "model" }]);
    if (result === null) {
      report.skips.push({ agent: name, reason: "malformed frontmatter" });
      continue;
    }
    if (result.changedKeys.includes("effort")) {
      report.changes.push({ agent: name, field: "effort", value: e.effort });
      if (!dryRun) writeFileSync(target, result.text);
    }
  }
  return report;
}

// --- Run + report ---------------------------------------------------------------
const steps: Array<{ name: string; report: Report }> = [
  { name: "Profile→derived+state", report: syncStateAndDerived() },
  { name: "OpenCode", report: syncOpencode() },
  { name: "OpenCode prune", report: pruneOpencodeJson() },
  { name: "PI", report: syncPi() },
  { name: "Claude", report: syncClaude() },
];

if (dryRun) console.log("DRY RUN — no files were written.\n");
for (const { name, report } of steps) {
  console.log(`=== ${name} ===`);
  const updated = new Set(report.changes.map((c) => c.agent)).size;
  if (dryRun) {
    if (report.changes.length === 0) console.log("  (no planned changes)");
    else for (const c of report.changes) console.log(`  ${c.agent}: ${c.field} = ${c.value}`);
    console.log(`Would update: ${updated}, Skipped: ${report.skips.length}`);
  } else {
    console.log(`Updated: ${updated}, Skipped: ${report.skips.length}`);
  }
  for (const n of report.notes) console.log(`Note: ${n}`);
  if (report.skips.length > 0) {
    console.log("Skips:");
    for (const s of report.skips) console.log(`  ${s.agent}: ${s.reason}`);
  }
  console.log();
}
process.exit(0);
