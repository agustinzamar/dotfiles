#!/usr/bin/env bash
# Lean server bootstrap: installs zsh + oh-my-posh and links a minimal,
# self-contained zsh config. No Homebrew, TUI, zinit, or macOS-specific setup.
#
#   curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install-server.sh | bash
#
# Pin a ref with: DOTFILES_REF=develop curl ... | bash

set -euo pipefail

REPO="agustinzamar/dotfiles"
REF="${DOTFILES_REF:-main}"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${REF}"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d%H%M%S)"

ZSHRC_SRC="config/zsh/.zshrc.server"
THEME_SRC="config/ohmyposh/theme.omp.json"
ZSHRC_TARGET="$HOME/.zshrc"
THEME_TARGET="$HOME/.config/oh-my-posh/theme.omp.json"
OMP_BIN_DIR="$HOME/.local/bin"

log()  { printf '%s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
else
  SUDO="$(command -v sudo || true)"
  [[ -n "$SUDO" ]] || warn "not root and sudo missing; package installs may fail"
fi

detect_pkg() {
  for pm in apt-get dnf yum pacman apk; do
    command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return; }
  done
  echo ""
}

install_zsh() {
  local pm="$1"
  case "$pm" in
    apt-get) $SUDO apt-get update -y && $SUDO apt-get install -y zsh ;;
    dnf)     $SUDO dnf install -y zsh ;;
    yum)     $SUDO yum install -y zsh ;;
    pacman)  $SUDO pacman -S --noconfirm zsh ;;
    apk)     $SUDO apk add zsh ;;
    *) warn "no supported package manager; install zsh manually"; return 1 ;;
  esac
}

install_oh_my_posh() {
  mkdir -p "$OMP_BIN_DIR"
  curl -fSL --max-time 180 --progress-bar https://ohmyposh.dev/install.sh -o /tmp/omp-install.sh
  if command -v timeout >/dev/null 2>&1; then
    timeout 300 bash /tmp/omp-install.sh -d "$OMP_BIN_DIR"
  else
    bash /tmp/omp-install.sh -d "$OMP_BIN_DIR"
  fi
}

backup_if_exists() {
  local target="$1"
  if [[ -e "$target" && ! -L "$target" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -a "$target" "$BACKUP_DIR/$(basename "$target")"
    log "backed up $target -> $BACKUP_DIR/$(basename "$target")"
  fi
}

fetch() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  curl -fSL --max-time 60 --progress-bar "$url" -o "$out"
}

maybe_chsh() {
  local zsh_bin omp
  zsh_bin="$(command -v zsh || true)"
  [[ -n "$zsh_bin" ]] || return 0
  [[ -t 1 ]] || return 0
  [[ "$SHELL" != "$zsh_bin" ]] || return 0
  omp="$(command -v oh-my-posh || true)"
  [[ -n "$omp" ]] || omp="$OMP_BIN_DIR/oh-my-posh"
  printf 'Set zsh (%s) as your default shell? [y/N] ' "$zsh_bin"
  local ans; read -r ans
  case "$ans" in
    y|Y) $SUDO chsh -s "$zsh_bin" "${USER:-$(id -un)}" ;;
    *) log "leaving default shell unchanged" ;;
  esac
}

main() {
  log "dotfiles server install (ref: $REF)"

  if ! command -v zsh >/dev/null 2>&1; then
    log "installing zsh"
    install_zsh "$(detect_pkg)"
  else
    log "zsh already present"
  fi

  if ! command -v "$OMP_BIN_DIR/oh-my-posh" >/dev/null 2>&1 && ! command -v oh-my-posh >/dev/null 2>&1; then
    log "installing oh-my-posh"
    if ! install_oh_my_posh; then
      warn "oh-my-posh install failed; prompt will be skipped until it is installed"
    fi
  else
    log "oh-my-posh already present"
  fi

  backup_if_exists "$ZSHRC_TARGET"
  backup_if_exists "$THEME_TARGET"

  log "downloading server zshrc -> $ZSHRC_TARGET"
  fetch "$BASE_URL/$ZSHRC_SRC" "$ZSHRC_TARGET"
  log "downloading oh-my-posh theme -> $THEME_TARGET"
  fetch "$BASE_URL/$THEME_SRC" "$THEME_TARGET"

  maybe_chsh

  log "done. start a new shell: zsh"
}

main "$@"
