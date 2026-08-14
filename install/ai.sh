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
# Plain entries that share a source collapse into ONE skills CLI call with
# repeated `--skill` and `--agent` flags, so the installer runs once per source
# instead of once per skill. Install values still run per agent.
#
# Every generated command installs globally and without prompting, and every
# CLI involved is idempotent, so `dot ai` is safe to re-run.
#
# An `install` value is executed as a shell command, as you, with the network
# available. These manifests are the trust boundary of this repo: read anything
# you paste into them the way you would read a script.

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

# Emit `item|command` lines for one manifest and a set of agents.
#
# Skills carry a default command, so an entry only names an agent when that
# agent needs something else. One entry is one vendor: `skills` lists every
# skill to install from it, and the entry becomes ONE call with repeated
# `--skill` and `--agent` flags (the skills CLI rejects comma or space
# separated lists, and redisplaying its banner per skill is noise). An entry
# without `skills` installs everything the vendor ships. Plugins have no
# useful default: every entry spells out its own per-agent command. Lines use
# a unit-separator instead of `|` so a command containing `||` reads back
# intact.
ai_manifest_lines() {
  local kind="$1" agents="$2"
  case "$kind" in
    skills)
      jq -r --arg agents "$agents" --arg all "$(ai_agent_names)" '
        ($agents | split(" ")) as $want
        | ($all | split(" ")) as $everyone
        | .skills
        | .[]
        | . as $e
        | (($e.skills // []) + (if $e.skill then [$e.skill] else [] end)) as $sk
        | ($sk | map(" --skill " + .) | join("")) as $sf
        | ($want | map(select(($e.agents // $everyone) | index(.)))) as $targets
        | select($targets | length > 0)
        | if (($e.install // {}) | length == 0)
          then
            [ $e.source,
              ("pnpm dlx skills@latest add " + $e.source + $sf
               + ($targets | map(" --agent " + .) | join(""))
               + " --global --yes") ]
            | join("\u001f")
          else
            ($targets | map(select($e.install[.] == null))) as $defaults
            | ($targets | map(select($e.install[.] != null))) as $overrides
            | ($e.source + (if ($sk | length) > 0 then "/" + ($sk | join(",")) else "" end)) as $item
            | if ($defaults | length) > 0
              then [ $item,
                     ("pnpm dlx skills@latest add " + $e.source + $sf
                      + ($defaults | map(" --agent " + .) | join(""))
                      + " --global --yes") ]
                   | join("\u001f")
              else empty
              end,
              ($overrides[] | [ $item + " [" + . + "]",
                                $e.install[.] ] | join("\u001f"))
          end' "$DOTFILES_DIR/ai/skills.json"
      ;;
    plugins)
      jq -r --arg agents "$agents" '
        ($agents | split(" ")) as $want
        | .plugins[]
        | . as $e
        | $want[]
        | select($e.install[.] != null)
        | [ $e.name + " [" + . + "]",
            $e.install[.] ] | join("\u001f")' "$DOTFILES_DIR/ai/plugins.json"
      ;;
  esac
}

# ai/skills holds skills tracked in this repo rather than pulled from a
# package (single-file skills such as teach-me). Claude Code reads
# ~/.claude/skills, so copy each tracked file INTO it. Never symlink anything
# there that points back into this repo: the skills CLI mirrors the layout it
# finds, so a symlink to ai/skills makes it copy new skills into the repo.
ai_link_local_skills() {
  local dir="$DOTFILES_DIR/ai/skills" target="$HOME/.claude/skills" entry
  [[ -n "$(ls -A "$dir" 2>/dev/null)" ]] || return 0
  run mkdir -p "$target"
  for entry in "$dir"/*; do
    [[ -d "$entry" ]] && continue
    run cp "$entry" "$target/"
  done
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

# ai_install <skills|plugins> <agent...>
#
# Agents whose CLI is missing are skipped; the rest share one manifest pass.
ai_install() {
  local kind="$1"; shift
  local agent cli present=() lines item cmd failures=()

  for agent in "$@"; do
    cli=$(ai_agent_cli "$agent") || {
      echo "unknown agent: $agent — try: $(ai_agent_names)" >&2
      return 1
    }
    if is_executable "$cli"; then
      present+=("$agent")
    else
      echo "$agent: $cli is not installed, skipping $kind" >&2
    fi
  done
  ((${#present[@]})) || return 0

  lines=$(ai_manifest_lines "$kind" "${present[*]}")
  [[ "$lines" == *"pnpm "* ]] && { ai_ensure_pnpm || return 1; }

  if [[ "$kind" == skills && " ${present[*]} " == *" claude-code "* ]]; then
    # Claude Code must read a real directory here. A symlink to ai/skills
    # would make the skills CLI resolve through it and write into this repo.
    [[ -L "$HOME/.claude/skills" ]] && run rm "$HOME/.claude/skills"
    run mkdir -p "$HOME/.claude/skills"
  fi

  log "Installing $kind for ${present[*]}"
  while IFS=$'\x1f' read -r item cmd; do
    [[ -n "$cmd" ]] || continue
    echo "-- $item"
    if "$DRY_RUN"; then
      echo "+ $cmd"
    else
      eval "$cmd" < /dev/null || failures+=("$item")
    fi
  done <<<"$lines"

  [[ "$kind" == skills && " ${present[*]} " == *" claude-code "* ]] && ai_link_local_skills

  if ((${#failures[@]})); then
    echo "==> $kind that failed:" >&2
    printf '    %s\n' "${failures[@]}" >&2
    return 1
  fi
  return 0
}
