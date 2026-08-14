#!/usr/bin/env bash

DOT_PROFILE=${DOT_PROFILE:-${XDG_CONFIG_HOME:-$HOME/.config}/dot/profile.json}

component_default_selected() {
  case "$1" in
    base | shell | git | hunk | terminal) return 0 ;;
    *) return 1 ;;
  esac
}

component_selected() {
  local id="$1"
  if [[ -f "$DOT_PROFILE" ]] && is_executable jq; then
    jq -e --arg id "$id" '.components[$id] == true' "$DOT_PROFILE" >/dev/null 2>&1
    return
  fi
  component_default_selected "$id"
}
