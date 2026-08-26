// Planner metadata + ADR-3 link-filter rule over the context contract.
//
// The Go-era embedded package/command tables are RETIRED (ADR-2): the Bash
// emitter install/manifest.sh is the single package source of truth and the
// TUI consumes context packages exclusively. This module keeps only pure
// planning/metadata helpers: selector row shaping, the link filter rule, and
// profile-area derivation.
import type { ContextLink, ContextPackage, InstallContext } from "./context";

/** Locked informational rows rendered at the top of the selector. They always
 *  run at apply time, mapped onto bin/dot's sub_zsh / sub_git. */
export const LOCKED_PSEUDO_STEPS: Array<{
  id: string;
  label: string;
  area: string;
  command: string;
}> = [
  {
    id: "zsh-setup",
    label: "Zinit/Zsh setup",
    area: "shell",
    command: "dot zsh",
  },
  {
    id: "git-signing",
    label: "Git signing config",
    area: "git",
    command: "dot git",
  },
];

export interface ToolRow {
  id: string;
  label: string;
  topic: string;
  /** Selector group header (category override from the emitter). */
  category: string;
  area: string;
  locked: boolean;
  default: boolean;
  /** Pre-check signal from `brew list` at emit time (v1 additive field). */
  installed?: boolean;
  /** Row is a locked pseudo-step (informational, always applied). */
  pseudo: boolean;
}

export interface LinkGrouping {
  /** Links offered by the ADR-3 rule over confirmed selections. */
  main: ContextLink[];
  /** Opt-in optional links (agents), always offered, never auto-checked. */
  agents: ContextLink[];
}

/** Pinned rows for Step 1: pseudo-steps and locked packages first, then every
 *  toggleable package in context order (topic grouping is a view concern). */
export function toolRows(context: InstallContext): ToolRow[] {
  const rows: ToolRow[] = [];
  for (const step of LOCKED_PSEUDO_STEPS) {
    rows.push({
      id: step.id,
      label: step.label,
      topic: "locked",
      category: "locked",
      area: step.area,
      locked: true,
      default: true,
      pseudo: true,
    });
  }
  for (const p of context.packages) {
    // kind "topic" rows (code extensions / duti defaults) never render in
    // step 1: the user picks vscode/duti there and code/duti-defaults are
    // offered as gated extra rows in step 2. kind "tap" rows are never
    // directly toggleable either: a user picks a TOOL (yabai, sketchybar),
    // never "enable this Homebrew tap" — withRequiredTaps() below adds the
    // tap install automatically whenever a sibling formula is selected.
    if (p.kind === "topic" || p.kind === "tap") continue;
    rows.push({
      id: p.id,
      label: p.label ?? p.id,
      topic: p.topic,
      // Locked rows stay pinned under their own header; the rest use the
      // emitter's category override (ai / Communication / Browsers / topic).
      category: p.locked ? "locked" : (p.category ?? p.topic),
      area: p.area,
      locked: p.locked,
      default: p.default,
      installed: p.installed,
      pseudo: false,
    });
  }
  return rows;
}

/** Topic groups for Step 1 rendering, in first-seen order. */
export function toolGroups(context: InstallContext): Array<{
  topic: string;
  rows: ToolRow[];
}> {
  const groups: Array<{ topic: string; rows: ToolRow[] }> = [];
  const seen = new Set<string>();
  for (const row of toolRows(context)) {
    if (seen.has(row.category)) continue;
    seen.add(row.category);
    groups.push({ topic: row.category, rows: [] });
  }
  for (const row of toolRows(context)) {
    groups.find((g) => g.topic === row.category)!.rows.push(row);
  }
  return groups;
}

/** Flat row order for rendering/navigation: every same-category row is
 *  guaranteed contiguous (unlike raw `toolRows`, whose order follows the
 *  context/topic-file order and can interleave categories). `toolView` and
 *  `reduceKey` both index into this SAME order, so the displayed cursor
 *  position and the interacted-with row never drift apart. */
export function toolRowsGrouped(context: InstallContext): ToolRow[] {
  return toolGroups(context).flatMap((group) => group.rows);
}

/**
 * ADR-3 link-filter rule (requirement-first). A link is offered iff:
 *  1. requirement != "" -> the package row with id == requirement is a
 *     CONFIRMED selection; or
 *  2. requirement == "" -> the link's component area is active: the area is in
 *     context.locked, or >=1 confirmed row has that area.
 *
 * Locked package rows are always installed through a separate channel and do
 * NOT count as confirmed selections here: with only the locked block active,
 * only locked-block untagged links are offered (installer-tui spec scenario).
 * Optional links form their own group, always present and unchecked.
 */
export function offeredLinks(
  context: InstallContext,
  selected: ReadonlySet<string>,
): LinkGrouping {
  const toggleable = context.packages.filter((p) => !p.locked);
  const selectedAreas = new Set(
    toggleable.filter((p) => selected.has(p.id)).map((p) => p.area),
  );

  const main = context.links.filter((link) => {
    if (link.optional) return false;
    if (link.requirement !== "") {
      // The requirement names a toggleable package row (locked rows never hit).
      return toggleable.some(
        (p) => p.id === link.requirement && selected.has(p.id),
      );
    }
    const active =
      context.locked.includes(link.component) ||
      selectedAreas.has(link.component);
    return active;
  });
  const agents = context.links.filter((link) => link.optional);
  return { main, agents };
}

/**
 * ADR-4: active area ids for the profile — areas of every confirmed row
 * (locked rows are always confirmed) union the locked areas. Locked rows'
 * areas (shell/git/terminal via fzf/git/gh/tmux) preserve today's
 * component_default_selected baseline in the written profile.
 */
export function activeProfileAreas(
  context: InstallContext,
  selected: ReadonlySet<string>,
): string[] {
  const areas = new Set<string>(context.locked);
  for (const step of LOCKED_PSEUDO_STEPS) {
    areas.add(step.area);
  }
  for (const p of context.packages) {
    if (selected.has(p.id)) {
      areas.add(p.area);
    }
  }
  return [...areas];
}

/**
 * The subset of confirmed rows whose package needs a brew command, in context
 * order. Kept here so main.ts can share the exact same selection semantics
 * between interactive and headless apply.
 */
export function selectedPackages(
  context: InstallContext,
  selected: ReadonlySet<string>,
): ContextPackage[] {
  return context.packages.filter((p) => selected.has(p.id));
}

/**
 * Tap rows are never directly toggleable (see toolRows); the tap they
 * represent is required whenever ANY sibling package from the same topic
 * file is a confirmed selection (Homebrew Bundle semantics: a topic's taps
 * cover every formula/cask declared in that same file). Returns a NEW set
 * that is `selected` plus every such tap id, so callers can feed it straight
 * into `selectedPackages`/`planBrewCommands` without a separate tap step.
 */
export function withRequiredTaps(
  context: InstallContext,
  selected: ReadonlySet<string>,
): Set<string> {
  const selectedTopics = new Set(
    context.packages
      .filter((p) => p.kind !== "tap" && selected.has(p.id))
      .map((p) => p.topic),
  );
  const augmented = new Set(selected);
  for (const p of context.packages) {
    if (p.kind === "tap" && selectedTopics.has(p.topic)) {
      augmented.add(p.id);
    }
  }
  return augmented;
}
