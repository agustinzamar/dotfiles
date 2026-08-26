#!/usr/bin/env bash
# Bootstrap a fresh machine in one line:
#
#   curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash
#
# Clones this repo to ~/dotfiles, tries a prebuilt dot-tui release binary, and
# runs the installer. config/zsh/.zshrc puts the CLI on PATH from $DOTFILES_DIR.
#
# Bare invocation (no flags) opens the INTERACTIVE installer and therefore needs
# a TTY: `dot install` refuses to run when stdin is not a terminal, so a piped
# run without flags dies immediately. Headless setups (scripts, SSH, CI) append
# a flag, which is passed through untouched via "$@" below:
#
#   .../remote-install.sh --all               full install, no interaction
#   .../remote-install.sh --profile <path>    apply a saved profile headlessly
#
# The "revert remote-install.sh to force --all" pin from the proposal remains
# available as a rollback if the fresh-VM interactive path needs to be frozen.

set -Eeuo pipefail

REPO_URL="https://github.com/agustinzamar/dotfiles"
TARGET="${DOTFILES_DIR:-$HOME/dotfiles}"

is_executable() { type "$1" >/dev/null 2>&1; }

if [[ -d "$TARGET/.git" ]]; then
  echo "==> $TARGET already exists, pulling"
  git -C "$TARGET" pull --ff-only
elif is_executable git; then
  echo "==> Cloning into $TARGET"
  git clone "$REPO_URL" "$TARGET"
else
  # git arrives with the Xcode command line tools, which `dot install` triggers
  # anyway. The tarball path covers the window before they are there.
  echo "==> No git yet, fetching a tarball into $TARGET"
  mkdir -p "$TARGET"
  if is_executable curl; then
    curl -fsSL "$REPO_URL/tarball/main" | tar -xz --strip-components=1 -C "$TARGET"
  elif is_executable wget; then
    wget -qO- "$REPO_URL/tarball/main" | tar -xz --strip-components=1 -C "$TARGET"
  else
    echo "No git, curl or wget available. Aborting." >&2
    exit 1
  fi
fi

# Best-effort prebuilt installer binary: any failure below is silent. bin/dot
# resolves the TUI itself (build from source with Bun, else guidance), so a
# missed download only costs a source build.
tui_asset=""
if [[ "$(uname -s)" == "Darwin" ]]; then
  case "$(uname -m)" in
    arm64) tui_asset="dot-tui-darwin-arm64" ;;
    x86_64) tui_asset="dot-tui-darwin-amd64" ;;
  esac
fi

if [[ -n "$tui_asset" && ! -x "$TARGET/bin/dot-tui" ]]; then
  echo "==> Fetching prebuilt dot-tui ($tui_asset)"
  if is_executable curl; then
    curl -fsSL -o "$TARGET/bin/dot-tui" \
      "$REPO_URL/releases/latest/download/$tui_asset" || rm -f "$TARGET/bin/dot-tui"
  elif is_executable wget; then
    wget -qO "$TARGET/bin/dot-tui" \
      "$REPO_URL/releases/latest/download/$tui_asset" || rm -f "$TARGET/bin/dot-tui"
  fi
  if [[ -f "$TARGET/bin/dot-tui" ]]; then
    chmod +x "$TARGET/bin/dot-tui" || rm -f "$TARGET/bin/dot-tui"
    # Drop downloads that cannot run here (wrong arch, truncated transfer);
    # the dry-run probe is side-effect free per the dot-cli-bootstrap flag
    # contract, and bin/dot then falls through to its source-build resolver.
    "$TARGET/bin/dot-tui" -profile "$TARGET/bin/.dot-tui-selfcheck" -dry-run \
      </dev/null >/dev/null 2>&1 || rm -f "$TARGET/bin/dot-tui"
  fi
fi

exec "$TARGET/bin/dot" install "$@"
