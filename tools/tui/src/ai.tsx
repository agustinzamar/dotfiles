// AI asset picker (AI Assets Plan, item 8 — UI portion). A standalone Ink +
// @inkjs/ui TUI that replaces the previous "everything, every agent" `dot ai`
// behavior behind an explicit selector. Flow (plan D5):
//   1. MultiSelect the items (skills + plugins, one combined list, each tagged
//      by kind and by the agents its `install` map supports).
//   2. MultiSelect the agents — only the DETECTED set is selectable, pre-checked
//      (plan D5 §3); absent agents render as dimmed, non-interactive lines
//      (MultiSelect has no per-option disabled flag, so the absent ones are not
//      offered as options at all — see <AgentsStep>).
//   3. ConfirmInput shows the resolved `item → [agents]` plan, then writes
//      `~/.config/dot/ai-profile.json` and spawns `dot ai --profile picker --all`
//      (child_process) so the REAL install loop in install/ai.sh runs.
//   4. Spinner while the spawned installer runs; one StatusMessage on finish.
//
// The install loop is NEVER reimplemented here (plan D5, requirement 7): this
// component only gathers the selection, writes the profile, and invokes `dot`.
// Cancelling the ConfirmInput exits without writing anything.
import { Box, Text, useApp } from "ink";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { useEffect, useMemo, useState } from "react";
import {
  ConfirmInput,
  MultiSelect,
  Spinner,
  StatusMessage,
} from "@inkjs/ui";

/** Declared agents, keyed by the profile's agent KEY (plan D3 / item 6). The
 *  executable probed for each (absent → shown unselectable). */
export const AGENT_EXECUTABLES: Record<string, string> = {
  "claude-code": "claude",
  codex: "codex",
  opencode: "opencode",
  pi: "pi",
};

export const ALL_AGENTS: string[] = Object.keys(AGENT_EXECUTABLES);

/** One selectable thing: a skill entry or a plugin entry. */
export interface AiItem {
  id: string;
  label: string;
  kind: "skill" | "plugin";
  /** Agent KEYS this item can be installed for (install map keys). */
  agents: string[];
}

/** Output contract written to `~/.config/dot/ai-profile.json` (plan item 9). */
export interface AiProfile {
  version: 1;
  items: Record<string, string[]>;
}

/** Agents an entry supports: `install` map keys when present; skills carry no
 *  per-agent map (cross-agent `npx skills`, plan D2) so they default to every
 *  declared agent until item 5 gives them explicit maps. ponytail: plugins
 *  ALWAYS carry an install map, so this fallback is skills-only. */
function agentsForEntry(install?: Record<string, string>): string[] {
  if (install && Object.keys(install).length > 0) {
    return Object.keys(install);
  }
  return [...ALL_AGENTS];
}

function agentSummary(agents: string[]): string {
  if (agents.length === 0) return "no agents";
  if (ALL_AGENTS.every((a) => agents.includes(a))) return "all agents";
  return agents.join(", ");
}

/** Repo root: `ai.tsx` lives at `<root>/tools/tui/src`, so three ups. An
 *  explicit `DOTFILES_DIR` wins (test seam / override). */
export function defaultRepoRoot(): string {
  if (process.env.DOTFILES_DIR) return process.env.DOTFILES_DIR;
  return path.resolve(import.meta.dir, "..", "..", "..");
}

/** `~/.config/dot/ai-profile.json` (honors XDG_CONFIG_HOME). */
export function defaultProfilePath(): string {
  const configHome =
    process.env.XDG_CONFIG_HOME ?? `${process.env.HOME ?? "~"}/.config`;
  return path.join(configHome, "dot", "ai-profile.json");
}

/** Loads and flattens `ai/skills.json` + `ai/plugins.json` into one item list.
 *  A missing/unreadable file contributes nothing (loud-by-design would block
 *  the picker entirely; better to offer what we can see). */
export function loadItems(repoRoot: string): AiItem[] {
  const items: AiItem[] = [];

  const pluginsPath = path.join(repoRoot, "ai", "plugins.json");
  try {
    const parsed = JSON.parse(readFileSync(pluginsPath, "utf8")) as {
      plugins?: Array<Record<string, unknown>>;
    };
    for (const p of parsed.plugins ?? []) {
      const id = (p.id ?? p.name ?? p.repo) as string;
      if (!id) continue;
      const label =
        (p.label ?? p.name ?? p.repo ?? id) as string;
      items.push({
        id,
        label,
        kind: "plugin",
        agents: agentsForEntry(p.install as Record<string, string> | undefined),
      });
    }
  } catch {
    // File missing or malformed: skip plugins, keep skills.
  }

  const skillsPath = path.join(repoRoot, "ai", "skills.json");
  try {
    const parsed = JSON.parse(readFileSync(skillsPath, "utf8")) as {
      skills?: Array<Record<string, unknown>>;
    };
    for (const s of parsed.skills ?? []) {
      const id = (s.id ?? s.name ?? s.source) as string;
      if (!id) continue;
      const skillNames = Array.isArray(s.skills)
        ? (s.skills as string[]).join(", ")
        : "";
      const label = (s.label ??
        (skillNames ? `${s.source} (${skillNames})` : s.source)) as string;
      items.push({
        id,
        label,
        kind: "skill",
        agents: agentsForEntry(s.install as Record<string, string> | undefined),
      });
    }
  } catch {
    // File missing or malformed: skip skills.
  }

  return items;
}

/** Probes each agent executable; returns the KEYS present on PATH. */
export function detectAgents(): string[] {
  return Object.entries(AGENT_EXECUTABLES)
    .filter(([, exe]) => Bun.which(exe) !== null)
    .map(([key]) => key);
}

/** Resolves the profile: each selected item maps to the selected agents that
 *  the item actually supports (intersection), so a plugin that has no `pi`
 *  command never proposes a `pi` install. */
export function buildProfile(
  selectedItemIds: string[],
  selectedAgents: string[],
  items: AiItem[],
): AiProfile {
  const byId = new Map(items.map((it) => [it.id, it]));
  const result: Record<string, string[]> = {};
  for (const id of selectedItemIds) {
    const item = byId.get(id);
    if (!item) continue;
    result[id] = selectedAgents.filter((a) => item.agents.includes(a));
  }
  return { version: 1, items: result };
}

/** Writes the profile atomically-ish: mkdir the dir, then write JSON. */
export function writeProfile(profilePath: string, profile: AiProfile): void {
  mkdirSync(path.dirname(profilePath), { recursive: true });
  writeFileSync(profilePath, `${JSON.stringify(profile, null, 2)}\n`);
}

/** Default installer invocation: `dot ai --profile picker --all` (item 9 /
 *  requirement 6). The real loop lives in install/ai.sh. */
async function defaultRunInstall(): Promise<number> {
  const proc = Bun.spawn(["dot", "ai", "--profile", "picker", "--all"], {
    stdout: "pipe",
    stderr: "pipe",
  });
  return await proc.exited;
}

function itemLabel(item: AiItem): string {
  return `${item.label} [${item.kind}] — ${agentSummary(item.agents)}`;
}

type Step = "items" | "agents" | "confirm" | "running" | "done";

export interface AiPickerProps {
  /** Override manifest location (test seam / DOTFILES_DIR alternative). */
  repoRoot?: string;
  /** Override profile output path (test seam). */
  profilePath?: string;
  /** Override the installer spawn (test seam). */
  runInstall?: () => Promise<number>;
  /** Called once the profile is written + install finished (test seam). */
  onDone?: (info: { profile: AiProfile; code: number }) => void;
}

export function AiPicker({
  repoRoot,
  profilePath,
  runInstall,
  onDone,
}: AiPickerProps): React.ReactElement {
  const root = repoRoot ?? defaultRepoRoot();
  const items = useMemo(() => loadItems(root), [root]);
  const detected = useMemo(() => detectAgents(), []);

  const [step, setStep] = useState<Step>("items");
  const [selectedItems, setSelectedItems] = useState<string[]>([]);
  const [selectedAgents, setSelectedAgents] = useState<string[]>(detected);
  const [profile, setProfile] = useState<AiProfile | null>(null);
  const [result, setResult] = useState<{ ok: boolean; output: string } | null>(
    null,
  );
  const { exit } = useApp();

  // Resolve the item→[agents] plan for the confirm screen + final write.
  const plan = useMemo(
    () => buildProfile(selectedItems, selectedAgents, items).items,
    [selectedItems, selectedAgents, items],
  );

  async function handleConfirm(): Promise<void> {
    const next = buildProfile(selectedItems, selectedAgents, items);
    try {
      writeProfile(profilePath ?? defaultProfilePath(), next);
    } catch (err) {
      setProfile(next);
      setResult({
        ok: false,
        output: err instanceof Error ? err.message : String(err),
      });
      setStep("done");
      return;
    }
    setProfile(next);
    setStep("running");
    try {
      const code = await (runInstall ?? defaultRunInstall)();
      setResult({
        ok: code === 0,
        output: code === 0 ? "" : `install exited with code ${code}`,
      });
    } catch (err) {
      setResult({
        ok: false,
        output: err instanceof Error ? err.message : String(err),
      });
    }
    setStep("done");
  }

  // After the final StatusMessage, hand control back to the shell.
  useEffect(() => {
    if (step !== "done") return;
    if (profile) onDone?.({ profile, code: result?.ok ? 0 : 1 });
    exit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step]);

  if (step === "items") {
    return (
      <Box flexDirection="column">
        <Text bold color="cyan">
          Step 1: Select AI items
        </Text>
        <MultiSelect
          options={items.map((it) => ({ label: itemLabel(it), value: it.id }))}
          defaultValue={[]}
          visibleOptionCount={10}
          onSubmit={(value) => {
            setSelectedItems(value);
            setStep("agents");
          }}
        />
      </Box>
    );
  }

  if (step === "agents") {
    const detectedSet = new Set(detected);
    return (
      <Box flexDirection="column">
        <Text bold color="cyan">
          Step 2: Select agents (detected pre-checked)
        </Text>
        {ALL_AGENTS.filter((a) => !detectedSet.has(a)).map((a) => (
          <Text key={a} dimColor>{`  ${a} (not detected)`}</Text>
        ))}
        <MultiSelect
          options={detected.map((a) => ({ label: a, value: a }))}
          defaultValue={detected}
          visibleOptionCount={Math.max(detected.length, 1)}
          onSubmit={(value) => {
            setSelectedAgents(value);
            setStep("confirm");
          }}
        />
      </Box>
    );
  }

  if (step === "confirm") {
    return (
      <Box flexDirection="column">
        <Text bold color="cyan">
          Confirm AI asset install
        </Text>
        {Object.keys(plan).length === 0 ? (
          <Text dimColor>  (nothing selected)</Text>
        ) : (
          Object.entries(plan).map(([id, ags]) => (
            <Text key={id}>{`  ${id} → ${
              ags.length ? ags.join(", ") : "(no matching agent)"
            }`}</Text>
          ))
        )}
        <ConfirmInput onConfirm={handleConfirm} onCancel={() => exit()} />
      </Box>
    );
  }

  if (step === "running") {
    return <Spinner label="Installing AI assets…" />;
  }

  // step === "done"
  const ok = result?.ok ?? false;
  return (
    <StatusMessage variant={ok ? "success" : "error"}>
      {ok
        ? "AI assets installed"
        : `Install failed${result?.output ? `: ${result.output}` : ""}`}
    </StatusMessage>
  );
}
