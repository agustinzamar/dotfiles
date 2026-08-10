#!/bin/bash
# statusline-command.sh — Claude Code statusLine script
# Mirrors the p10k lean prompt: dir + git branch + model + context%
# Also preserves the caveman mode badge when active.

input=$(cat)

# --- directory (basename of cwd) ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
if [ -n "$cwd" ]; then
  dir=$(basename "$cwd")
  printf '\033[34m%s\033[0m' "$dir"
fi

# --- git branch + changes ---
if git --no-optional-locks -C "${cwd:-.}" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git --no-optional-locks -C "${cwd:-.}" symbolic-ref --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    printf ' \033[32m \033[0m\033[32m%s\033[0m' "$branch"
  fi

  # staged + unstaged line changes (+/-)
  diff_stat=$(git --no-optional-locks -C "${cwd:-.}" diff --numstat 2>/dev/null)
  staged_stat=$(git --no-optional-locks -C "${cwd:-.}" diff --cached --numstat 2>/dev/null)
  combined=$(printf '%s\n%s\n' "$diff_stat" "$staged_stat")
  if [ -n "$(echo "$combined" | tr -d '[:space:]')" ]; then
    added=$(echo "$combined" | awk 'NF>=2 {a+=$1} END {print a+0}')
    removed=$(echo "$combined" | awk 'NF>=2 {r+=$2} END {print r+0}')
    if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
      printf ' \033[32m+%d\033[0m\033[31m-%d\033[0m' "$added" "$removed"
    fi
  fi

  # untracked files (not counted by diff --numstat above)
  untracked=$(git --no-optional-locks -C "${cwd:-.}" ls-files --others --exclude-standard 2>/dev/null | grep -c .)
  if [ "${untracked:-0}" -gt 0 ]; then
    printf ' \033[33m?%d\033[0m' "$untracked"
  fi

  # pending push / pull (requires upstream set)
  upstream=$(git --no-optional-locks -C "${cwd:-.}" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [ -n "$upstream" ]; then
    ahead=$(git --no-optional-locks -C "${cwd:-.}" rev-list --count "@{upstream}..HEAD" 2>/dev/null)
    behind=$(git --no-optional-locks -C "${cwd:-.}" rev-list --count "HEAD..@{upstream}" 2>/dev/null)
    [ -z "$ahead" ] && ahead=0
    [ -z "$behind" ] && behind=0
    if [ "$ahead" -gt 0 ]; then
      printf ' \033[33m↑%d\033[0m' "$ahead"
    fi
    if [ "$behind" -gt 0 ]; then
      printf ' \033[33m↓%d\033[0m' "$behind"
    fi
  fi

  # --- PR number + status (cached; gh is slow) ---
  if command -v gh >/dev/null 2>&1 && [ -n "$branch" ]; then
    cache_key=$(printf '%s@%s' "$branch" "$cwd" | md5 -q 2>/dev/null || printf '%s@%s' "$branch" "$cwd" | md5sum | cut -d' ' -f1)
    cache_file="${TMPDIR:-/tmp}/cc-statusline-pr-${cache_key}"
    # refresh in background if cache missing or older than 60s
    refresh=0
    if [ ! -f "$cache_file" ]; then
      refresh=1
    else
      age=$(( $(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
      [ "$age" -gt 60 ] && refresh=1
    fi
    if [ "$refresh" -eq 1 ]; then
      ( cd "$cwd" 2>/dev/null || exit
        if gh pr view "$branch" --json number,state,reviewDecision,statusCheckRollup,url \
            -q '{n:.number,s:.state,r:.reviewDecision,u:.url,c:([.statusCheckRollup[]?.conclusion]|if any(.=="FAILURE") then "FAIL" elif all(.=="SUCCESS" or .==null or .=="NEUTRAL" or .=="SKIPPED") then "PASS" else "PEND" end)}' \
            > "$cache_file.tmp" 2>/dev/null; then
          mv "$cache_file.tmp" "$cache_file"
        else
          : > "$cache_file"; rm -f "$cache_file.tmp"
        fi ) >/dev/null 2>&1 &
    fi
    if [ -s "$cache_file" ]; then
      pr_num=$(jq -r '.n // empty' "$cache_file" 2>/dev/null)
      pr_state=$(jq -r '.s // empty' "$cache_file" 2>/dev/null)
      pr_review=$(jq -r '.r // empty' "$cache_file" 2>/dev/null)
      pr_ci=$(jq -r '.c // empty' "$cache_file" 2>/dev/null)
      pr_url=$(jq -r '.u // empty' "$cache_file" 2>/dev/null)
      if [ -n "$pr_num" ]; then
        case "$pr_state" in
          OPEN)   pr_color='\033[36m' ;;
          MERGED) pr_color='\033[35m' ;;
          CLOSED) pr_color='\033[31m' ;;
          *)      pr_color='\033[37m' ;;
        esac
        if [ -n "$pr_url" ]; then
          printf ' \033]8;;%s\a' "$pr_url"
          printf "${pr_color}\033[4mPR#%s\033[0m" "$pr_num"
          printf '\033]8;;\a'
        else
          printf " ${pr_color}PR#%s\033[0m" "$pr_num"
        fi
        case "$pr_review" in
          APPROVED)          printf ' \033[32m✓\033[0m' ;;
          CHANGES_REQUESTED) printf ' \033[31m✗\033[0m' ;;
          REVIEW_REQUIRED)   printf ' \033[33m◷\033[0m' ;;
        esac
        case "$pr_ci" in
          PASS) printf ' \033[32m●\033[0m' ;;
          FAIL) printf ' \033[31m●\033[0m' ;;
          PEND) printf ' \033[33m●\033[0m' ;;
        esac
      fi
    fi
  fi
fi

# --- model ---
model=$(echo "$input" | jq -r '.model.display_name // empty')
if [ -n "$model" ]; then
  printf '  \033[35m%s\033[0m' "$model"
fi

# --- effort level ---
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort" ]; then
  printf '  \033[33m[%s]\033[0m' "$effort"
fi

# --- context remaining ---
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
if [ -n "$remaining" ]; then
  remaining_int=$(printf '%.0f' "$remaining")
  if [ "$remaining_int" -lt 20 ]; then
    color='\033[31m'  # red when low
  elif [ "$remaining_int" -lt 50 ]; then
    color='\033[33m'  # yellow when medium
  else
    color='\033[36m'  # cyan when healthy
  fi
  printf "  ${color}ctx:%d%%\033[0m" "$remaining_int"
fi

# --- caveman badge (preserved from original statusline) ---
FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
  MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]')
  MODE=$(printf '%s' "$MODE" | tr -cd 'a-z0-9-')
  case "$MODE" in
    off|lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress)
      if [ -z "$MODE" ] || [ "$MODE" = "full" ]; then
        printf '  \033[38;5;172m[CAVEMAN]\033[0m'
      else
        SUFFIX=$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]')
        printf '  \033[38;5;172m[CAVEMAN:%s]\033[0m' "$SUFFIX"
      fi
      SAVINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-statusline-suffix"
      if [ "${CAVEMAN_STATUSLINE_SAVINGS:-1}" != "0" ] && [ -f "$SAVINGS_FILE" ] && [ ! -L "$SAVINGS_FILE" ]; then
        SAVINGS=$(head -c 64 "$SAVINGS_FILE" 2>/dev/null | tr -d '\000-\037')
        [ -n "$SAVINGS" ] && printf ' \033[38;5;172m%s\033[0m' "$SAVINGS"
      fi
      ;;
  esac
fi
