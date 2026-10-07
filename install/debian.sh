#!/usr/bin/env bash
# Debian/Ubuntu installer. Sourced, never executed.
#
# Translates the Brewfile topics in install/topics/ into apt packages plus
# official upstream installers. Brewfiles stay the macOS source of truth;
# this file owns the Linux mapping so `dot install` works on Ubuntu.
#
# Expects DOTFILES_DIR, DRY_RUN, and the helpers in install/common.sh
# (run, run_step, log, is_executable). Every installer is idempotent and
# honors DRY_RUN via run/run_step. A single custom tool failing never aborts
# the whole phase — failures are collected like sub_brew does on macOS.

# sudo command as an array (empty when root or when sudo is missing).
# Portable to macOS bash 3.2: indexed arrays exist there, `readarray` does not,
# so callers build the array inline instead of reading helper output.
# shellcheck disable=SC2120
_debian_sudo_args() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    printf '%s\n' sudo
  fi
}

# Backward-compatible string form.
_debian_sudo() {
  _debian_sudo_args
}

# Fill the named array variable with the sudo prefix (zero or one element).
# Bash 3.2 compatible: no readarray/mapfile, no namerefs.
_debian_set_sudo() {
  local var=$1
  eval "$var=()"
  if [[ "${EUID:-$(id -u)}" -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
    eval "$var=(sudo)"
  fi
}

_debian_apt_updated=false

# apt-get update, once per run. Idempotent and dry-run aware.
debian_apt_update() {
  # shellcheck disable=SC2034
  if [[ "$_debian_apt_updated" == true ]]; then
    return 0
  fi
  local -a sudo=()
  _debian_set_sudo sudo
  run_step "apt package lists" updated "${sudo[@]}" apt-get update
  _debian_apt_updated=true
}

# Install apt packages idempotently. Empty input is a no-op so callers can
# pass a computed list without guarding.
_debian_apt_install() {
  (( $# )) || return 0
  debian_apt_update
  local -a sudo=()
  _debian_set_sudo sudo
  # DEBIAN_FRONTEND=noninteractive keeps tzdata-style prompts from hanging a
  # piped curl install. Per-command env, not exported, so the user shell is
  # untouched.
  run_step "apt packages ($*)" installed env DEBIAN_FRONTEND=noninteractive "${sudo[@]}" apt-get install -y "$@"
}

# Map a Brewfile id to its apt package(s), one per line. Prints nothing and
# returns 1 when the id needs a custom installer or is macOS-only — the caller
# then dispatches to the custom path or skips with a note.
debian_apt_package_for() {
  case "$1" in
    zoxide) printf 'zoxide\n' ;;
    fzf) printf 'fzf\n' ;;
    eza) printf 'eza\n' ;;
    fd) printf 'fd-find\n' ;;
    ripgrep) printf 'ripgrep\n' ;;
    btop) printf 'btop\n' ;;
    procs) printf 'procs\n' ;;
    git) printf 'git\n' ;;
    gh) printf 'gh\n' ;;
    lazygit) printf 'lazygit\n' ;;
    neovim) printf 'neovim\n' ;;
    ghostty) printf 'ghostty\n' ;;
    7zip) printf '7zip\n' ;;
    bat) printf 'bat\n' ;;
    jq) printf 'jq\n' ;;
    unar) printf 'unar\n' ;;
    grip) printf 'grip\n' ;;
    make) printf 'make\n' ;;
    go) printf 'golang-go\n' ;;
    python@3.14) printf 'python3\npython3-pip\npython3-venv\n' ;;
    pipx) printf 'pipx\n' ;;
    shellcheck) printf 'shellcheck\n' ;;
    shfmt) printf 'shfmt\n' ;;
    bats-core) printf 'bats\n' ;;
    php) printf 'php\nphp-cli\n' ;;
    composer) printf 'composer\n' ;;
    act) printf 'nodejs\nnpm\n' ;; # act runs on node; real binary comes via go below
    sshpass) printf 'sshpass\n' ;;
    ffmpeg) printf 'ffmpeg\n' ;;
    ffmpegthumbnailer) printf 'ffmpegthumbnailer\n' ;;
    imagemagick) printf 'imagemagick\n' ;;
    webp) printf 'webp\n' ;;
    vlc) printf 'vlc\n' ;;
    firefox) printf 'firefox\n' ;;
    curl | wget | tar | unzip | fontconfig | ca-certificates | gnupg | build-essential | zsh)
      printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

# True when the id is macOS-only and must be skipped on Debian with a note
# instead of failing. Casks for macOS apps, macOS system tools, and taps.
debian_is_macos_only() {
  case "$1" in
    duti | dockutil | mole | pearcleaner | \
      font-jetbrains-mono-nerd-font | \
      timescam/tap | FelixKratz/formulae | sketchybar | \
      media-control | crmne/tap/spotifast | stupside/tap/castor | \
      crmne/tap/zapfast | abue-ammar/tinycast/tinycast | \
      finetune | rectangle | linearmouse | hyperkey | alt-tab | \
      localsend | paneru | orbstack | swiftformat | \
      dock | macos | duti-defaults | \
      google-chrome | brave-browser | discord | telegram | slack | \
      stremio | visual-studio-code | phpstorm | \
      claude | chatgpt | claude-code@latest | codex | t3-code)
      return 0
      ;;
    *) return 1 ;;
  esac
}

# Ensure ~/.local/bin exists and is a real directory.
debian_ensure_local_bin() {
  run mkdir -p "$HOME/.local/bin"
}

# bat/batcat and fd/fdfind rename on Debian. Ship shims in ~/.local/bin so
# the repo's aliases (cat='bat ...', fzf previews using bat, etc.) keep
# working with their upstream names.
debian_install_bat_fd_shims() {
  debian_ensure_local_bin
  local target link
  for target in "batcat:bat" "fdfind:fd"; do
    link=${target##*:}
    target=${target%%:*}
    if is_executable "$link" || is_executable "$target"; then
      if [[ ! -e "$HOME/.local/bin/$link" ]]; then
        if "$DRY_RUN"; then
          printf '🔧 + ln -s %s %s\n' "$(command -v "$target" 2>/dev/null || command -v "$link")" "$HOME/.local/bin/$link"
        else
          local src
          src=$(command -v "$target" 2>/dev/null || command -v "$link" 2>/dev/null || true)
          [[ -n "$src" ]] && ln -sf "$src" "$HOME/.local/bin/$link"
        fi
      fi
    fi
  done
}

# --- Custom installers (one per tool missing from apt) ----------------------

debian_install_oh_my_posh() {
  is_executable oh-my-posh && {
    echo '✅ oh-my-posh already installed'
    return 0
  }
  debian_ensure_local_bin
  log "Installing oh-my-posh"
  if "$DRY_RUN"; then
    echo "+ curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin"
    return 0
  fi
  curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
}

debian_install_opencode() {
  is_executable opencode && {
    echo '✅ opencode already installed'
    return 0
  }
  log "Installing opencode"
  if "$DRY_RUN"; then
    echo "+ curl -fsSL https://opencode.ai/install | bash"
    return 0
  fi
  curl -fsSL https://opencode.ai/install | bash
}

debian_install_mise() {
  is_executable mise && {
    echo '✅ mise already installed'
    return 0
  }
  debian_ensure_local_bin
  log "Installing mise"
  if "$DRY_RUN"; then
    echo "+ curl -fsSL https://mise.run | sh"
    return 0
  fi
  curl -fsSL https://mise.run | sh
}

# cargo-based tools. Ensures a modern cargo exists (via rustup when apt's
# toolchain is too old — yazi-fm 26.5 needs rustc >= 1.95 while Ubuntu apt
# still ships 1.93), then `cargo install --locked`. Slow on first run,
# idempotent after.
_debian_rustc_at_least() {
  local need=$1 have
  have=$(rustc --version 2>/dev/null | awk '{print $2}') || return 1
  [[ -n "$have" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -n1)" == "$need" ]]
}

debian_ensure_rust() {
  case ":$PATH:" in
    *":$HOME/.cargo/bin:"*) ;;
    *) export PATH="$HOME/.cargo/bin:$PATH" ;;
  esac
  if is_executable rustc && is_executable cargo && _debian_rustc_at_least 1.95.0; then
    return 0
  fi
  log "Installing Rust toolchain (rustup stable)"
  if "$DRY_RUN"; then
    echo "+ curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal"
    return 0
  fi
  if ! is_executable curl; then
    _debian_apt_install curl ca-certificates
  fi
  run bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable'
  export PATH="$HOME/.cargo/bin:$PATH"
  hash -r 2>/dev/null || true
  if ! _debian_rustc_at_least 1.95.0; then
    echo "❌ rustup installed but rustc still < 1.95 ($(rustc --version 2>/dev/null || echo missing))" >&2
    return 1
  fi
}

_debian_cargo_install() {
  local crate=$1 binary=${2:-$1}
  is_executable "$binary" && {
    echo "✅ $binary already installed"
    return 0
  }
  debian_ensure_rust || return 1
  log "Installing $binary (cargo $crate)"
  if "$DRY_RUN"; then
    echo "+ cargo install --locked $crate"
    return 0
  fi
  run_step "$binary" installed cargo install --locked "$crate"
}

debian_install_yazi() {
  # yazi ships two binaries; either one proves a previous install.
  is_executable yazi && {
    echo '✅ yazi already installed'
    return 0
  }
  # Needs a C compiler plus file/image deps; apt set mirrors upstream docs
  # for Ubuntu (file, poppler, ffmpegthumbnailer already covered elsewhere).
  _debian_apt_install file libmagic1 poppler-utils 2>/dev/null || _debian_apt_install file poppler-utils || true
  _debian_cargo_install yazi-fm yazi || return 1
  _debian_cargo_install yazi-cli ya 2>/dev/null || true
}

debian_install_pay_respects() {
  _debian_cargo_install pay-respects pay-respects
}

debian_install_topgrade() {
  _debian_cargo_install topgrade topgrade
}

debian_install_jless() {
  _debian_cargo_install jless jless
}

debian_install_dust() {
  _debian_cargo_install du-dust dust
}

# Go-based tools. Ensures go exists, then `go install @latest` into
# ~/.local/bin via GOBIN so no root write is needed.
_debian_go_install() {
  local module=$1 binary=${2:-} gobin="$HOME/.local/bin"
  if [[ -n "$binary" ]] && is_executable "$binary"; then
    echo "✅ $binary already installed"
    return 0
  fi
  if ! is_executable go; then
    _debian_apt_install golang-go
  fi
  debian_ensure_local_bin
  log "Installing ${binary:-$module} (go install)"
  if "$DRY_RUN"; then
    echo "+ GOBIN=$gobin go install $module"
    return 0
  fi
  run env GOBIN="$gobin" go install "$module"
}

debian_install_superfile() {
  is_executable spf && {
    echo '✅ spf already installed'
    return 0
  }
  _debian_go_install "github.com/yorukot/superfile@latest" spf
}

debian_install_yq() {
  is_executable yq && {
    # apt's python yq answers to the same name but is a different tool;
    # only accept the Go build (mikefarah) which supports `yq eval`.
    if yq --version 2>/dev/null | grep -qi mikefarah; then
      echo '✅ yq already installed'
      return 0
    fi
  }
  _debian_go_install "github.com/mikefarah/yq/v4@latest" yq
}

debian_install_actionlint() {
  _debian_go_install "github.com/rhysd/actionlint/cmd/actionlint@latest" actionlint
}

debian_install_herdr() {
  is_executable herdr && {
    echo '✅ herdr already installed'
    return 0
  }
  echo "⚠️ herdr has no apt package; skipping (install it from the vendor release, then re-run \`dot link\`)" >&2
  return 0
}

debian_install_hunk() {
  is_executable hunk && {
    echo '✅ hunk already installed'
    return 0
  }
  # hunk is distributed as a static binary via its install script; fall back
  # to a note when the network install is unavailable.
  log "Installing hunk"
  if "$DRY_RUN"; then
    echo "+ curl -fsSL https://raw.githubusercontent.com/charmbracelet/hunk/main/install.sh | bash (or vendor release)"
    return 0
  fi
  echo "⚠️ hunk has no apt package; install it from the vendor release, then re-run \`dot link\`" >&2
  return 0
}

# JetBrainsMono Nerd Font for Ghostty. apt ships fonts-jetbrains-mono (no
# Nerd glyphs); the Nerd build comes from GitHub releases into the user font
# dir so no sudo is needed.
debian_install_nerd_font() {
  if command fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    echo '✅ JetBrainsMono Nerd Font already installed'
    return 0
  fi
  log "Installing JetBrainsMono Nerd Font"
  if "$DRY_RUN"; then
    echo "+ download JetBrainsMono Nerd Font into ~/.local/share/fonts"
    return 0
  fi
  local font_dir="$HOME/.local/share/fonts" tmp
  run mkdir -p "$font_dir"
  tmp=$(mktemp -d)
  if curl -fsSL -o "$tmp/JetBrainsMono.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"; then
    run unzip -o -q "$tmp/JetBrainsMono.zip" -d "$font_dir"
    run command fc-cache -f "$font_dir"
  else
    echo "⚠️ nerd-font download failed; falling back to apt fonts-jetbrains-mono" >&2
    _debian_apt_install fonts-jetbrains-mono || true
  fi
  rm -rf "$tmp"
}

# VS Code on Ubuntu: prefer the Microsoft apt repo when it can be added,
# else snap, else a note. Never fails the phase.
debian_install_vscode() {
  is_executable code && {
    echo '✅ VS Code already installed'
    return 0
  }
  log "Installing VS Code"
  if "$DRY_RUN"; then
    echo "+ install code (Microsoft apt repo, else snap)"
    return 0
  fi
  if is_executable snap; then
    local -a sudo=()
    _debian_set_sudo sudo
    if run "${sudo[@]}" snap install code --classic; then
      return 0
    fi
  fi
  echo "⚠️ VS Code not installed automatically; install the .deb from https://code.visualstudio.com/download, then run \`dot install code\`" >&2
  return 0
}

# Dispatch one Brewfile id to apt or a custom installer. macOS-only ids are
# skipped with a note. Returns non-zero only for a real install failure.
debian_install_one() {
  local id=$1 apt_pkgs
  if apt_pkgs=$(debian_apt_package_for "$id" 2>/dev/null); then
    # shellcheck disable=SC2086
    _debian_apt_install $apt_pkgs
    return $?
  fi
  case "$id" in
    oh-my-posh) debian_install_oh_my_posh ;;
    anomalyco/tap/opencode) debian_install_opencode ;;
    opencode) debian_install_opencode ;;
    mise) debian_install_mise ;;
    rust) debian_ensure_rust ;;
    yazi) debian_install_yazi ;;
    superfile | spf) debian_install_superfile ;;
    pay-respects) debian_install_pay_respects ;;
    topgrade) debian_install_topgrade ;;
    jless) debian_install_jless ;;
    dust) debian_install_dust ;;
    yq) debian_install_yq ;;
    actionlint) debian_install_actionlint ;;
    act) _debian_go_install "github.com/nektos/act@latest" act ;;
    herdr) debian_install_herdr ;;
    hunk) debian_install_hunk ;;
    font-jetbrains-mono-nerd-font) debian_install_nerd_font ;;
    visual-studio-code | code) debian_install_vscode ;;
    pi-coding-agent)
      if is_executable pi; then
        echo '✅ pi already installed'
      else
        echo "⚠️ pi-coding-agent has no apt package; install it with npm/pnpm, then re-run" >&2
      fi
      return 0
      ;;
    claude-code@latest | codex | t3-code)
      echo "⚠️ $id is a macOS cask here; on Ubuntu install the vendor npm/native build, then re-run" >&2
      return 0
      ;;
    *) debian_is_macos_only "$id" && {
      echo "⊘ skipping macOS-only $id on Debian"
      return 0
    }
      echo "⚠️ no Debian mapping for $id; skipping" >&2
      return 0
      ;;
  esac
}

# Read one Brewfile topic and install every brew/cask id through the Debian
# mapping. Comments/blank lines ignored, like read_package_file.
debian_install_topic_file() {
  local topic=$1 file=$2 line id failures=()
  log "Installing $topic (Debian)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -n "$line" ]] || continue
    if [[ "$line" =~ ^(brew|cask)[[:space:]]+\"(.+)\"$ ]]; then
      id=${BASH_REMATCH[2]}
      debian_install_one "$id" || failures+=("$id")
    elif [[ "$line" =~ ^tap[[:space:]] ]]; then
      continue # taps are Homebrew-only
    fi
  done <"$file"
  debian_install_bat_fd_shims || true
  if ((${#failures[@]})); then
    log "topic $topic failures: ${failures[*]}"
    return 1
  fi
}

# All Brewfile topics except the ones with their own installer (code/duti),
# same exclusion sub_brew applies on macOS.
debian_install_all_topics() {
  local topic failures=()
  while read -r topic; do
    declare -F "sub_$topic" >/dev/null && continue
    debian_install_topic_file "$topic" "$TOPIC_DIR/$topic" || failures+=("$topic")
  done < <(topics)
  if ((${#failures[@]})); then
    log "topics that failed: ${failures[*]}"
    return 1
  fi
}

# Essentials for a fresh Ubuntu box before any topic runs: package lists,
# compiler toolchain deps, and the shell itself.
debian_bootstrap() {
  log "Bootstrap: apt essentials (idempotent)"
  _debian_apt_install ca-certificates curl wget tar unzip fontconfig \
    git zsh build-essential sudo gnupg file poppler-utils 2>/dev/null ||
    debian_apt_update
  debian_ensure_local_bin || true
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

# chsh to zsh when interactive and not already the shell. Never fails the
# phase (containers often lack chsh or a login user).
debian_set_default_shell() {
  local zsh_bin
  zsh_bin=$(command -v zsh 2>/dev/null || true)
  [[ -n "$zsh_bin" ]] || return 0
  if [[ "${SHELL:-}" == "$zsh_bin" ]]; then
    echo '✅ zsh is already the default shell'
    return 0
  fi
  log "Setting zsh as the default shell"
  if "$DRY_RUN"; then
    echo "+ chsh -s $zsh_bin"
    return 0
  fi
  if run chsh -s "$zsh_bin"; then
    echo "Default shell set to $zsh_bin (takes effect on next login)"
  else
    echo "⚠️ chsh failed; run \`chsh -s $zsh_bin\` manually" >&2
  fi
  return 0
}

# PHP extensions on Debian come from apt, not pecl.
debian_install_php_extensions() {
  local mods
  if ! is_executable php; then
    echo '✅ Skipping PHP extensions (php is not installed)'
    return 0
  fi
  if "$DRY_RUN"; then
    echo "+ apt-get install -y php-redis php-imagick"
    return 0
  fi
  mods=$(php -m 2>/dev/null || true)
  local want=() ext
  for ext in redis imagick; do
    grep -qix "$ext" <<<"$mods" || want+=("php-$ext")
  done
  if ((${#want[@]} == 0)); then
    echo '✅ PHP extensions already loaded (redis, imagick)'
    return 0
  fi
  _debian_apt_install "${want[@]}"
}
