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

#!/usr/bin/env bash
# Bootstrap a fresh machine in one line (macOS or Ubuntu):
#
#   curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash -s -- --all
#
# Clones this repo to ~/dotfiles and runs the installer.
# config/zsh/.zshrc puts the CLI on PATH from $DOTFILES_DIR.
#
# Ubuntu: installs zsh, oh-my-posh, opencode, git and the terminal tools
# through apt plus official upstream installers (see install/debian.sh).
# macOS: installs through Homebrew (Xcode CLT bootstrapped by `dot install`).
#
# Bare invocation (no flags) opens the INTERACTIVE installer and therefore needs
# a TTY: `dot install` refuses to run when stdin is not a terminal, so a piped
# run without flags dies immediately. Fresh machines and headless setups
# (scripts, SSH, CI) append a flag, which is passed through untouched via "$@"
# below:
#
#   .../remote-install.sh --all               full install, no interaction

set -Eeuo pipefail

REPO_URL="https://github.com/agustinzamar/dotfiles"
TARGET="${DOTFILES_DIR:-$HOME/dotfiles}"

is_executable() { type "$1" >/dev/null 2>&1; }

# On Debian/Ubuntu a missing git/curl can be fixed with apt when sudo is
# available; on macOS git arrives with the Xcode CLT which `dot install`
# triggers anyway. Try the cheap fix before falling back to the tarball.
if ! is_executable git && [[ "$(uname -s)" == "Linux" ]] && is_executable apt-get; then
  echo "==> git not found, trying apt-get"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    apt-get update && apt-get install -y git curl ca-certificates || true
  elif is_executable sudo; then
    sudo apt-get update && sudo apt-get install -y git curl ca-certificates || true
  fi
fi

if [[ -d "$TARGET/.git" ]]; then
  echo "==> $TARGET already exists, pulling"
  git -C "$TARGET" pull --ff-only
elif is_executable git; then
  echo "==> Cloning into $TARGET"
  git clone "$REPO_URL" "$TARGET"
else
  # git arrives with the Xcode command line tools on macOS (which
  # `dot install` triggers anyway) or via apt on Debian (attempted above).
  # The tarball path covers the window before either is there.
  echo "==> No git yet, fetching a tarball into $TARGET"
  echo "    (Debian/Ubuntu without git: sudo apt-get install -y git curl)"
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
elif [[ "$(uname -s)" == "Linux" ]]; then
  case "$(uname -m)" in
    x86_64) tui_asset="dot-tui-linux-amd64" ;;
    aarch64 | arm64) tui_asset="dot-tui-linux-arm64" ;;
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
    # the --version probe is side-effect free, and bin/dot then falls through
    # to its source-build resolver.
    "$TARGET/bin/dot-tui" --version \
      </dev/null >/dev/null 2>&1 || rm -f "$TARGET/bin/dot-tui"
  fi
fi

exec "$TARGET/bin/dot" install "$@"
