#!/usr/bin/env bash
# Skills and plugins for the AI agent CLIs. Sourced by bin/dot.
#
# Nothing in here runs during `dot install`: the agents themselves come from
# Homebrew (install/topics/ai), and what they load on top is opt-in through
# `dot ai`. A fresh machine gets the CLIs and nothing else until asked.
#
# ai/skills.json and ai/plugins.json are data. One entry can install
# differently per agent, because the same upstream ships as a skill package for
# one CLI and as a plugin for another:
#
#   { "source": "mattpocock/skills", "install": { "claude-code": "claude ..." } }
#
# Resolution per entry, per agent:
#   agents      which agents want it            (default: all of AI_AGENTS)
#   install.X   the command agent X needs       (default: the skills CLI call)
#
# Every generated command installs globally and without prompting, and every
# CLI involved is idempotent, so `dot ai` is safe to re-run.

AI_AGENTS=(claude-code codex opencode)

# The executable that proves an agent is installed. Also the guard that keeps
# `dot ai` quiet about agents this machine does not have.
ai_agent_cli() {
  case "$1" in
    claude-code) printf 'claude' ;;
    codex) printf 'codex' ;;
    opencode) printf 'opencode' ;;
    *) return 1 ;;
  esac
}

ai_agent_names() { printf '%s' "${AI_AGENTS[*]}"; }

# Emit `item|command` lines for one manifest and one agent.
#
# Skills carry a default command, so an entry only names an agent when that
# agent needs something else. Plugins have no useful default: every entry
# spells out its own per-agent command.
ai_manifest_lines() {
  local kind="$1" agent="$2"
  case "$kind" in
    skills)
      jq -r --arg agent "$agent" --arg all "${AI_AGENTS[*]}" '
        .skills[]
        | select((.agents // ($all | split(" "))) | index($agent))
        | [ (.source + (if .skill then "/" + .skill else "" end)),
            (.install[$agent] //
              ("pnpm dlx skills@latest add " + .source
                + (if .skill then " --skill " + .skill else "" end)
                + " --agent " + $agent + " --global --yes"))
          ] | join("|")' "$DOTFILES_DIR/ai/skills.json"
      ;;
    plugins)
      jq -r --arg agent "$agent" '
        .plugins[]
        | select(.install[$agent])
        | [.name, .install[$agent]] | join("|")' "$DOTFILES_DIR/ai/plugins.json"
      ;;
  esac
}

# ai/skills holds skills tracked in this repo rather than pulled from a
# package. Claude Code is the only agent that reads a whole directory, so it is
# the only one that gets the symlink.
ai_link_local_skills() {
  local target="$HOME/.claude/skills"
  [[ -n "$(ls -A "$DOTFILES_DIR/ai/skills" 2>/dev/null)" ]] || return 0
  # A dangling symlink from a previous run would make link_file back up a
  # broken target instead of replacing it.
  [[ -L "$target" && ! -e "$target" ]] && run rm "$target"
  link_file "ai/skills" "$target"
}

# ai_install <skills|plugins> <agent>
ai_install() {
  local kind="$1" agent="$2" cli item cmd failures=()
  cli=$(ai_agent_cli "$agent") || {
    echo "unknown agent: $agent — try: $(ai_agent_names)" >&2
    return 1
  }
  if ! is_executable "$cli"; then
    echo "$agent: $cli is not installed, skipping $kind" >&2
    return 0
  fi

  log "Installing $kind for $agent"
  while IFS='|' read -r item cmd; do
    [[ -n "$cmd" ]] || continue
    echo "-- $item"
    if "$DRY_RUN"; then
      echo "+ $cmd"
    else
      eval "$cmd" || failures+=("$item")
    fi
  done < <(ai_manifest_lines "$kind" "$agent")

  [[ "$kind" == skills && "$agent" == claude-code ]] && ai_link_local_skills

  if ((${#failures[@]})); then
    echo "$agent: $kind that failed: ${failures[*]}" >&2
    return 1
  fi
  return 0
}
