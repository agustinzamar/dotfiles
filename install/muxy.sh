#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Manage Muxy config via the upcoming CLI export/import commands.
#
# `muxy config export` and `muxy config import` are not yet released; this
# script is ready for them. The exported config omits sensitive information
# (device tokens, approved devices, etc.), so the exported snapshot can be
# committed without leaking secrets.
#
# Usage: muxy export [--dry-run]
#        muxy import [--dry-run]
set -Eeuo pipefail

BIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export DOTFILES_DIR=${DOTFILES_DIR:-$(cd -- "$BIN_DIR/.." && pwd -P)}

# --dry-run is global, mirroring bin/dot.
DRY_RUN=false
args=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) args+=("$arg") ;;
  esac
done
export DRY_RUN
set -- ${args[@]+"${args[@]}"}

# shellcheck source=../install/common.sh
. "$DOTFILES_DIR/install/common.sh"

REPO_CONFIG="$DOTFILES_DIR/config/muxy/settings.json"

muxy_help() {
  cat <<EOF
Usage: $(basename "$0") <command> [--dry-run]

Commands:
   export   Write a non-sensitive Muxy config export to:
            $REPO_CONFIG
   import   Apply the exported config to Muxy via \`muxy config import\`
   help     Show this help message

Export the live Muxy config when the CLI supports it, then commit the
exported file. Import applies the repo's exported config to Muxy.
EOF
}

_muxy_require_cli() {
  command -v muxy >/dev/null 2>&1 || {
    echo "muxy: install Muxy first" >&2
    return 1
  }
}

sub_muxy_export() {
  _muxy_require_cli
  log "Exporting Muxy config (non-sensitive) to config/muxy/settings.json"
  run mkdir -p "$(dirname "$REPO_CONFIG")"
  if "$DRY_RUN"; then
    printf '+ muxy config export > %q\n' "$REPO_CONFIG"
  else
    run muxy config export >"$REPO_CONFIG"
  fi
}

sub_muxy_import() {
  _muxy_require_cli
  [[ -f "$REPO_CONFIG" ]] || {
    echo "muxy: no exported config at $REPO_CONFIG — run '$(basename "$0") export' first" >&2
    return 1
  }
  log "Importing Muxy config from config/muxy/settings.json"
  run muxy config import "$REPO_CONFIG"
}

COMMAND_NAME=${1:-}
shift 2>/dev/null || true
case "$COMMAND_NAME" in
  "" | -h | --help | help)
    muxy_help
    ;;
  export)
    sub_muxy_export "$@"
    ;;
  import)
    sub_muxy_import "$@"
    ;;
  *)
    echo "muxy: unknown command '$COMMAND_NAME'" >&2
    muxy_help >&2
    exit 1
    ;;
esac
