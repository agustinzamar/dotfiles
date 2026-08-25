// Context-file loader for the `--context <path>` contract (ADR-2). The JSON v1
// file is emitted by install/manifest.sh; this is the single TS-side validator.
// Hand-rolled like profile.ts — no zod. There is no default context: a missing
// or malformed file is a fatal, loud error.
import { readFile } from "node:fs/promises";

export interface ContextPackage {
  id: string;
  topic: string;
  kind: "brew" | "cask" | "tap" | "topic";
  area: string;
  locked: boolean;
  default: boolean;
}

export interface LinkRow {
  source: string;
  target: string;
  mode: string;
}

export interface ContextLink {
  name: string;
  optional: boolean;
  component: string;
  requirement: string;
  rows: LinkRow[];
}

export interface InstallContext {
  version: 1;
  locked: string[];
  packages: ContextPackage[];
  links: ContextLink[];
}

function requireObject(value: unknown, what: string): asserts value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`invalid context: ${what} is required`);
  }
}

function requireStringArray(
  value: unknown,
  what: string,
): asserts value is string[] {
  if (!Array.isArray(value) || value.some((v) => typeof v !== "string")) {
    throw new Error(`invalid context: ${what} must be an array of strings`);
  }
}

/** Loads and validates the versioned installer context file. */
export async function loadContext(path_: string): Promise<InstallContext> {
  let data: string;
  try {
    data = await readFile(path_, "utf8");
  } catch (err) {
    throw new Error(
      `invalid context: ${path_} is not readable: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(data);
  } catch (cause) {
    throw new Error(
      `invalid context: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
  requireObject(parsed, "context");
  const raw = parsed as Record<string, unknown>;

  if (raw.version !== 1) {
    throw new Error("invalid context: version must be 1");
  }
  requireStringArray(raw.locked, "locked");
  if (!Array.isArray(raw.packages)) {
    throw new Error("invalid context: packages must be an array");
  }
  if (!Array.isArray(raw.links)) {
    throw new Error("invalid context: links must be an array");
  }

  const packages = raw.packages.map((row) => {
    requireObject(row, "packages");
    if (
      typeof row.id !== "string" ||
      typeof row.topic !== "string" ||
      typeof row.area !== "string" ||
      typeof row.locked !== "boolean" ||
      typeof row.default !== "boolean"
    ) {
      throw new Error("invalid context: malformed packages row");
    }
    // Every field was type-checked above; row has exactly ContextPackage's shape.
    return {
      id: row.id,
      topic: row.topic,
      kind: row.kind as ContextPackage["kind"],
      area: row.area,
      locked: row.locked,
      default: row.default,
    };
  });

  const links = raw.links.map((row) => {
    requireObject(row, "links");
    if (
      typeof row.name !== "string" ||
      typeof row.optional !== "boolean" ||
      typeof row.component !== "string" ||
      typeof row.requirement !== "string" ||
      !Array.isArray(row.rows)
    ) {
      throw new Error("invalid context: malformed links row");
    }
    for (const entry of row.rows as unknown[]) {
      requireObject(entry, "rows");
      if (
        typeof entry.source !== "string" ||
        typeof entry.target !== "string" ||
        typeof entry.mode !== "string"
      ) {
        throw new Error("invalid context: malformed links row");
      }
    }
    // Every field was type-checked above; row has exactly ContextLink's shape.
    return {
      name: row.name,
      optional: row.optional,
      component: row.component,
      requirement: row.requirement,
      rows: (row.rows as Record<string, unknown>[]).map((entry) => ({
        source: entry.source as string,
        target: entry.target as string,
        mode: entry.mode as string,
      })),
    };
  });

  return {
    version: 1,
    locked: raw.locked,
    packages,
    links,
  };
}