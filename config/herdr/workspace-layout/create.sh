#!/bin/sh
set -e

TABS="Servers Agents Hunk LazyGit Playground"

H="${HERDR_BIN_PATH:-herdr}"

WS=$($H workspace create --focus | sed -n 's/.*"workspace_id": *"\([^"]*\)".*/\1/p')
FIRST=$($H tab list --workspace "$WS" | sed -n 's/.*"tab_id": *"\([^"]*\)".*/\1/p' | head -1)

set -- $TABS
$H tab rename "$FIRST" "$1"
shift
for name in "$@"; do
  $H tab create --workspace "$WS" --label "$name"
done
