#!/usr/bin/env bash

# Static component baseline (no profile file): base/shell/git/terminal always
# on, everything else (incl. ai) opt-in via the caller.
component_selected() {
  case "$1" in
    base | shell | git | terminal) return 0 ;;
    *) return 1 ;;
  esac
}
