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

# The one place an agent is declared: `<manifest name>:<executable>`, where the
# executable is what proves the agent is on this machine. Adding an agent is
# adding one entry here. bash 3.2 ships no associative arrays, hence the pairs.
AI_AGENTS=(claude-code:claude codex:codex opencode:opencode)

ai_agent_cli() {
  local pair
  for pair in "${AI_AGENTS[@]}"; do
    if [[ "${pair%%:*}" == "$1" ]]; then
      printf '%s' "${pair#*:}"
      return 0
    fi
  done
  return 1
}

# Every agent name, space separated. Feeds the help text, the error messages,
# the manifest default, and `dot ai` with no agent named.
ai_agent_names() {
  local pair names=()
  for pair in "${AI_AGENTS[@]}"; do names+=("${pair%%:*}"); done
  printf '%s' "${names[*]}"
}

# Emit `item|command` lines for one manifest and one agent.
#
# Skills carry a default command, so an entry only names an agent when that
# agent needs something else. Plugins have no useful default: every entry
# spells out its own per-agent command.
ai_manifest_lines() {
  local kind="$1" agent="$2"
  case "$kind" in
    skills)
      jq -r --arg agent "$agent" --arg all "$(ai_agent_names)" '
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

# The skills CLI runs through pnpm. Install it once, up front, rather than
# letting every entry fail on its own.
ai_ensure_pnpm() {
  is_executable pnpm && return 0
  is_executable brew || {
    echo "pnpm is missing and Homebrew is not here to install it" >&2
    return 1
  }
  log "Installing pnpm"
  run brew install pnpm
}

# ai_install <skills|plugins> <agent>
ai_install() {
  local kind="$1" agent="$2" cli lines item cmd failures=()
  cli=$(ai_agent_cli "$agent") || {
    echo "unknown agent: $agent — try: $(ai_agent_names)" >&2
    return 1
  }
  if ! is_executable "$cli"; then
    echo "$agent: $cli is not installed, skipping $kind" >&2
    return 0
  fi

  lines=$(ai_manifest_lines "$kind" "$agent")
  [[ "$lines" == *"pnpm "* ]] && { ai_ensure_pnpm || return 1; }

  log "Installing $kind for $agent"
  while IFS='|' read -r item cmd; do
    [[ -n "$cmd" ]] || continue
    echo "-- $item"
    if "$DRY_RUN"; then
      echo "+ $cmd"
    else
      eval "$cmd" || failures+=("$item")
    fi
  done <<<"$lines"

  [[ "$kind" == skills && "$agent" == claude-code ]] && ai_link_local_skills

  if ((${#failures[@]})); then
    echo "$agent: $kind that failed: ${failures[*]}" >&2
    return 1
  fi
  return 0
}
