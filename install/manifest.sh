#!/usr/bin/env bash
# Manifest parser and installer-context emitter.
#
# This file is the SINGLE parser of the package manifests (install/topics/*)
# for the TUI flow: `bin/dot` sources it and `install_context_json` writes the
# versioned context JSON the TUI consumes via `--context <file>`. The topics
# files themselves stay plain Brewfile-style data read verbatim by
# `brew bundle` for headless installs — same bytes, no third copy.
#
# No jq: on a fresh Mac jq only exists after packages install, and the context
# is emitted before any install. All JSON escaping is pure Bash.

# "installed" pre-checks come from `brew list`. Snapshot the sets once per
# emitter run (two subprocesses) instead of one `brew info` probe per row; any
# failure (no brew yet, empty list) degrades to empty sets, i.e. nothing
# pre-checked. Tests stub a fake `brew` on PATH to control these.
MANIFEST_BREW=${MANIFEST_BREW:-brew}
_manifest_installed_snapshot() {
  MANIFEST_INSTALLED_FORMULAE="$("$MANIFEST_BREW" list --formula 2>/dev/null || true)"
  MANIFEST_INSTALLED_CASKS="$("$MANIFEST_BREW" list --cask 2>/dev/null || true)"
  MANIFEST_INSTALLED_DONE=true
}

_manifest_is_installed() {
  local id=$1 kind=$2
  local match=$id
  [[ "${MANIFEST_INSTALLED_DONE:-}" == true ]] || _manifest_installed_snapshot
  [[ "$kind" == tap || "$kind" == topic ]] && return 1
  # brew list reports tap formulae/casks by their SIMPLE name (opencode, castor).
  [[ "$kind" == brew || "$kind" == cask ]] && match=${id##*/}
  local haystack
  if [[ "$kind" == cask ]]; then
    haystack=$MANIFEST_INSTALLED_CASKS
  else
    haystack=$MANIFEST_INSTALLED_FORMULAE
  fi
  grep -qxF "$match" <<<"$haystack"
}

# Root used to locate install/topics. Derived from this file's location so the
# emitter works standalone (tests) and when sourced from bin/dot.
MANIFEST_ROOT=${MANIFEST_ROOT:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}
MANIFEST_TOPIC_DIR=${MANIFEST_TOPIC_DIR:-"$MANIFEST_ROOT/install/topics"}

# Link map source. Reuse the caller's copy when already loaded (bin/dot),
# otherwise load it from this repo so the emitter works standalone.
declare -F all_links >/dev/null 2>&1 || . "$MANIFEST_ROOT/install/links.sh"

# Escape a string for use inside a JSON double-quoted value. Handles the
# characters this data can actually contain: quotes, backslashes, tabs,
# newlines, carriage returns.
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  printf '%s' "$s"
}

# Map a package id to its component area — the ids install/links.sh and
# components.sh already use. Explicit table over inferred magic: one place to
# review when a package or link token changes. Unknown ids fail (exit 1) so
# the drift-guard test catches renames.
area_for_package() {
  case "$1" in
  # Area tokens used directly as link components resolve to themselves.
  base | shell | git | terminal | vscode | ai | ai-herdr | claude | dev | media | desktop | system | desktop-*) echo "$1" ;;
  # --- System settings (dot dock / dot macos apply_defaults scripts) ---
  dock | macos) echo "system" ;;
  # --- Shell (locked block; also p10k/starship link component) ---
  fzf | zoxide | oh-my-posh | pay-respects | timescam/tap | powerlevel10k | starship) echo "shell" ;;
  # --- Git ---
  gh | lazygit | hunk) echo "git" ;;
  # --- Terminal / core CLI ---
  eza | fd | yazi | poppler | ripgrep | grip | watch | btop | procs | topgrade | dust | dockutil | mole | 7zip | bat | jq | jless | yq | unar | tmux | duti | ghostty | neovim | font-jetbrains-mono-nerd-font | duti-defaults | 'we"ird\name') echo "terminal" ;;
  # --- VS Code ---
  visual-studio-code | code) echo "vscode" ;;
  # --- AI ---
  opencode | anomalyco/tap/opencode | pi-coding-agent | claude-code@latest | codex | t3-code) echo "ai" ;;
  herdr) echo "ai-herdr" ;;
  # --- Dev ---
  make | go | node | python@3.14 | pnpm | bun | npm-check-updates | pipx | rust | shellcheck | shfmt | bats-core | act | sshpass | phpstorm | actionlint | swiftformat | mysql | mysql-client | postgresql | redis | sqlite | herd | orbstack | openusage | direnv) echo "dev" ;;
  # --- Desktop (subareas match links.sh component tokens) ---
  linearmouse) echo "desktop-linearmouse" ;;
  aerospace) echo "desktop-aerospace" ;;
  sketchybar) echo "desktop-sketchybar" ;;
  yabai) echo "desktop-yabai" ;;
  skhd) echo "desktop-skhd" ;;
  borders) echo "desktop-borders" ;;
  pearcleaner | google-chrome | firefox | brave-browser | discord | telegram | whatsapp | slack | raycast | finetune | typewhisper | rectangle | localsend | hyperkey | alt-tab | chatgpt | koekeishiya/formulae | FelixKratz/formulae | FelixKratz/JankyBorders) echo "desktop" ;;
  # --- Media ---
  ffmpeg | ffmpegthumbnailer | imagemagick | webp | spotify | stremio | vlc | stupside/tap/castor | castor) echo "media" ;;
  *) return 1 ;;
  esac
}

# Locked-block members: always installed, never a visible/toggleable TUI row
# (tui.tsx's LockedBlock renders only the pseudo-steps, no locked package —
# every id here is silent plumbing another visible tool depends on, never a
# real user decision). fzf: sub_zsh's post-install step only WIRES UP an
# already-installed fzf. zoxide/eza: the .zshrc aliases (z, ls) assume they
# exist. poppler: yazi's PDF-preview dependency.
manifest_is_locked() {
  case "$1" in
  fzf | zoxide | eza | poppler) return 0 ;;
  *) return 1 ;;
  esac
}

# Former forced-baseline tools: pre-checked in the TUI, still toggleable.
# tmux is a real preference (not everyone wants a multiplexer forced on); git
# and gh moved here from the locked block so they render under the Git
# category alongside lazygit/hunk instead of the inert always-on block.
manifest_is_default() {
  case "$1" in
  lazygit | hunk | yazi | neovim | ghostty | tmux | git | gh) return 0 ;;
  *) return 1 ;;
  esac
}

# Emit one TSV row (topic \t kind \t id) per installable unit.
#
# Regular topics: `brew "x"` / `cask "x"` / `tap "x"` lines; comments and
# blanks ignored (same tolerance as read_package_file). The special-installer
# topics `code` (VS Code extensions) and `duti` (default-file handlers) are
# not brew data: each becomes one delegating row applied via `dot install`.
package_rows() {
  local file topic line id kind
  for file in "$MANIFEST_TOPIC_DIR"/*; do
    topic=$(basename "$file")
    case "$topic" in
    code | duti) continue ;;
    esac
    while IFS= read -r line; do
      line=${line%%#*}
      line=${line#"${line%%[![:space:]]*}"} line=${line%"${line##*[![:space:]]}"}
      [[ -n "$line" ]] || continue
      if [[ "$line" =~ ^(brew|cask|tap)[[:space:]]+\"(.+)\"$ ]]; then
        kind=${BASH_REMATCH[1]}
        id=${BASH_REMATCH[2]}
        printf '%s\t%s\t%s\n' "$topic" "$kind" "$id"
      fi
    done <"$file"
  done
  # Special-installer topics: one delegating row each.
  printf 'code\ttopic\tcode\n'
  printf 'duti\ttopic\tduti-defaults\n'
  # System-level adopters that are not brew data: `dot dock` / `dot macos`
  # run apply_defaults for system/defaults/dock.sh and macos.sh.
  printf 'system\ttopic\tdock\n'
  printf 'system\ttopic\tmacos\n'
}

# Emit the link map verbatim (all_links then optional_links). manifest.sh adds
# no link data of its own — links.sh stays the single source.
link_rows() {
  all_links
  optional_links
}

# One JSON package row object.
# Display label: tap rows keep their full tap name (they ARE the tap); brew and
# cask rows from third-party taps render as the simple name after the last
# slash (anomalyco/tap/opencode -> opencode) so the selector lists real tools.
_manifest_label() {
  local id=$1 kind=$2
  if [[ "$kind" == tap ]]; then
    printf '%s' "$id"
  elif [[ "$kind" == topic ]]; then
    # Delegating rows get a human label; they now render as first-class
    # step-1 rows instead of being hidden away in a step-2 corner.
    case "$id" in
    code) printf 'VS Code extensions' ;;
    duti-defaults) printf 'Default file handlers' ;;
    dock) printf 'Dock defaults' ;;
    macos) printf 'macOS defaults' ;;
    *) printf '%s' "${id##*/}" ;;
    esac
  else
    printf '%s' "${id##*/}"
  fi
}

# Display categories for the selector grouping. The TUI groups by category,
# not by the source install/topics file, so related tools get shared headers
# (AI apps, browsers, window managers, utilities...) while still installing
# from their original topic files (`dot install <topic>` / brew bundle
# semantics are untouched). Unknown ids fall back to their topic.
manifest_category() {
  case "$1" in
  # --- System settings, file handlers and defaults scripts ---
  duti-defaults | dock | macos) echo "System" ;;
  # --- VS Code extensions (`code` delegates to dot install code) ---
  code) echo "Editors" ;;
  # --- AI agents and AI apps ---
  claude-code@latest | codex | t3-code | anomalyco/tap/opencode | pi-coding-agent | claude | chatgpt | herdr | openusage) echo "AI" ;;
  # --- Browsers ---
  google-chrome | firefox | brave-browser) echo "Browsers" ;;
  # --- Communication ---
  discord | telegram | whatsapp | slack) echo "Communication" ;;
  # --- Desktop / window managers (the tiling stack) ---
  yabai | skhd | sketchybar | aerospace | borders | koekeishiya/formulae | FelixKratz/formulae | FelixKratz/JankyBorders) echo "Desktop" ;;
  # --- Tweakers (input, window and bar tweaks) ---
  linearmouse | finetune | rectangle | hyperkey | alt-tab | typewhisper) echo "Tweakers" ;;
  # --- Utilities ---
  raycast | localsend | mole | pearcleaner | topgrade | dockutil | duti) echo "Utilities" ;;
  # --- Archives ---
  7zip | unar) echo "Archives" ;;
  # --- Monitoring ---
  btop | procs | watch) echo "Monitoring" ;;
  # --- Filesystem navigation (poppler previews yazi's PDFs; both eza and
  # poppler stay listed here for data consistency even though they're locked
  # and never rendered — see manifest_is_locked) ---
  eza | fd | dust | yazi | poppler) echo "Filesystem" ;;
  # --- Terminals: emulator/multiplexer/font, prompts (oh-my-posh is active;
  # starship/powerlevel10k are dormant alternatives — config exists but
  # .zshrc doesn't source them yet), command correction, and the locked
  # fzf/zoxide (never rendered, kept here for data consistency) ---
  ghostty | tmux | font-jetbrains-mono-nerd-font | oh-my-posh | starship | powerlevel10k | pay-respects | timescam/tap | fzf | zoxide) echo "Terminals" ;;
  # --- Text and search ---
  ripgrep | bat | jq | jless | yq | grip) echo "Text" ;;
  # --- Git and GitHub ---
  git | gh | lazygit | hunk) echo "Git" ;;
  # --- Editors and IDEs ---
  neovim | visual-studio-code | phpstorm) echo "Editors" ;;
  # --- Dev languages, runtimes and CLI tools (direnv: per-project env) ---
  make | go | node | python@3.14 | pnpm | bun | npm-check-updates | pipx | rust | bats-core | act | sshpass | direnv) echo "Dev" ;;
  # --- Linters and formatters ---
  shellcheck | shfmt | actionlint | swiftformat) echo "Linters" ;;
  # --- Local dev environments and service runtimes ---
  herd | orbstack) echo "Services" ;;
  # --- Databases ---
  mysql | mysql-client | postgresql | redis | sqlite) echo "Databases" ;;
  # --- Media processing ---
  ffmpeg | ffmpegthumbnailer | imagemagick | webp) echo "Media tools" ;;
  # --- Entertainment ---
  spotify | stremio | vlc | stupside/tap/castor) echo "Entertainment" ;;
  *) echo "pin-topic" ;;
  esac
}

_manifest_package_json() {
  local topic=$1 kind=$2 id=$3 locked=false default=false installed=false
  manifest_is_locked "$id" && locked=true
  manifest_is_default "$id" && default=true
  _manifest_is_installed "$id" "$kind" && installed=true
  local area label category
  area=$(area_for_package "$id") || {
    echo "manifest: no area mapping for package '$id'" >&2
    return 1
  }
  label=$(_manifest_label "$id" "$kind")
  category=$(manifest_category "$id")
  [[ "$category" == pin-topic ]] && category=$topic
  printf '{"id":"%s","label":"%s","topic":"%s","category":"%s","kind":"%s","area":"%s","locked":%s,"default":%s,"installed":%s}' \
    "$(json_escape "$id")" "$(json_escape "$label")" "$(json_escape "$topic")" "$(json_escape "$category")" "$(json_escape "$kind")" \
    "$(json_escape "$area")" "$locked" "$default" "$installed"
}

# Write the versioned installer context JSON to <file>.
install_context_json() {
  local out=$1
  # Each emission re-snapshots the installed sets (bats tests swap brew stubs).
  unset MANIFEST_INSTALLED_DONE MANIFEST_INSTALLED_FORMULAE MANIFEST_INSTALLED_CASKS
  if [[ ! -d "$MANIFEST_TOPIC_DIR" ]]; then
    echo "manifest: topics directory not readable: $MANIFEST_TOPIC_DIR" >&2
    return 1
  fi

  local topic kind id pkg pkgs=()
  while IFS=$'\t' read -r topic kind id; do
    pkg=$(_manifest_package_json "$topic" "$kind" "$id") || return 1
    pkgs+=("$pkg")
  done < <(package_rows)

  # Group link rows by name (multi-target names collapse into one entry),
  # preserving first-seen order. Parallel arrays instead of associative
  # arrays: /usr/bin/env bash may be macOS bash 3.2 on a fresh machine.
  local names=() optional_flags=() components=() requirements=() rowblobs=()
  local map map_name optional name source target mode component requirement i found
  for map_name in all optional; do
    if [[ "$map_name" == all ]]; then
      map=all_links optional=false
    else
      map=optional_links optional=true
    fi
    while IFS='|' read -r name source target mode component requirement; do
      [[ -n "$source" ]] || continue
      found=-1
      for i in "${!names[@]}"; do
        [[ "${names[$i]}" == "$name" ]] && {
          found=$i
          break
        }
      done
      if [[ "$found" -eq -1 ]]; then
        names+=("$name")
        optional_flags+=("$optional")
        components+=("$component")
        requirements+=("$requirement")
        rowblobs+=("")
        found=$((${#names[@]} - 1))
      fi
      rowblobs[found]+="${rowblobs[found]:+,}$(printf '{"source":"%s","target":"%s","mode":"%s"}' \
        "$(json_escape "$source")" "$(json_escape "$target")" "$(json_escape "$mode")")"
    done < <("$map")
  done

  local links=() name_json
  for i in "${!names[@]}"; do
    name_json=$(printf '{"name":"%s","optional":%s,"component":"%s","requirement":"%s","rows":[%s]}' \
      "$(json_escape "${names[$i]}")" "${optional_flags[$i]}" \
      "$(json_escape "${components[$i]}")" "$(json_escape "${requirements[$i]}")" \
      "${rowblobs[$i]}")
    links+=("$name_json")
  done

  {
    printf '{"version":1,"locked":["base","shell"],"packages":[%s],"links":[%s]}' \
      "$(
        IFS=,
        printf '%s' "${pkgs[*]}"
      )" \
      "$(
        IFS=,
        printf '%s' "${links[*]}"
      )"
  } >"$out"
}
