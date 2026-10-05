#!/bin/bash
# Claude Code status line: dir | git branch | model | context | effort
# Nerd Font icons (same font as the oh-my-posh theme). Model, context and effort
# are colored by value: model family, context green->yellow->orange->red,
# effort low->max. Directory and branch stay neutral.

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
model_id=$(echo "$input" | jq -r '.model.id // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')

fg() { printf '\033[38;5;%sm' "$1"; }
GRAY=$'\033[90m'
BOLD=$'\033[1m'
RESET=$'\033[0m'
SEP="${GRAY} | ${RESET}"

GREEN=$(fg 78)
YELLOW=$(fg 220)
ORANGE=$(fg 208)
RED=$(fg 196)

# Nerd Font glyphs as UTF-8 bytes (bash 3.2 on macOS has no \u escapes)
ICON_DIR=$(printf '\xef\x81\xbb')      # U+F07B folder
ICON_BRANCH=$(printf '\xef\x90\x98')   # U+F418 git branch
ICON_MODEL=$(printf '\xef\x8b\x9b')    # U+F2DB microchip
ICON_CTX=$(printf '\xef\x83\xa4')      # U+F0E4 gauge
ICON_EFFORT=$(printf '\xef\x83\xa7')   # U+F0E7 bolt

out=""

# Current directory (last path component)
if [ -n "$cwd" ]; then
  out="${GRAY}${ICON_DIR}${RESET} $(basename "$cwd")"
fi

# Git branch (skip optional locks)
if [ -n "$cwd" ] && git --no-optional-locks -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null \
    || git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  [ -n "$branch" ] && out="${out}${SEP}${GRAY}${ICON_BRANCH}${RESET} ${branch}"
fi

# Model, colored by family
if [ -n "$model" ]; then
  case "$(printf '%s %s' "$model" "$model_id" | tr '[:upper:]' '[:lower:]')" in
    *fable*)  c=$(fg 213) ;; # pink
    *opus*)   c=$(fg 141) ;; # purple
    *sonnet*) c=$(fg 75) ;;  # blue
    *haiku*)  c=$(fg 79) ;;  # teal
    *)        c="" ;;
  esac
  out="${out}${SEP}${c}${ICON_MODEL} ${model}${RESET}"
fi

# Context usage: green < 40, yellow < 60, orange < 80, red otherwise
if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used")
  if [ "$pct" -ge 80 ]; then c="$RED"
  elif [ "$pct" -ge 60 ]; then c="$ORANGE"
  elif [ "$pct" -ge 40 ]; then c="$YELLOW"
  else c="$GREEN"; fi
  out="${out}${SEP}${c}${ICON_CTX} ${pct}%${RESET}"
fi

# Effort level (only present when the model supports it): low green -> max bold red
if [ -n "$effort" ]; then
  case "$effort" in
    low)    c="$GREEN" ;;
    medium) c="$YELLOW" ;;
    high)   c="$ORANGE" ;;
    xhigh)  c="$RED" ;;
    max)    c="${BOLD}${RED}" ;;
    *)      c="" ;;
  esac
  out="${out}${SEP}${c}${ICON_EFFORT} ${effort}${RESET}"
fi

printf '%s\n' "$out"
