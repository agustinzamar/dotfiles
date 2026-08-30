#!/usr/bin/env bash
# Symlink map. Sourced by bin/dot.
#
# The map is data: one row per line, where source is relative to the repo root
# and name is how `dot link <name>` selects a config or a group. A name may
# appear more than once (ghostty serves two targets). link/unlink walk the same
# map, so a path is declared exactly once.
#
#   name|source|target|mode|component|requirement|os
#
# The trailing `os` column declares the single OS family a row applies to; an
# empty or absent column means portable. Applicability is data on the row, never
# a branch in the walker.

# os_family/platform_binary live in install/platform.sh. bin/dot sources it
# first, but install/manifest.sh loads this file standalone, so guard-load it
# here the same way manifest.sh guard-loads this one.
LINKS_DIR=${LINKS_DIR:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"}
# shellcheck source=install/platform.sh
declare -F os_family >/dev/null 2>&1 || . "$LINKS_DIR/platform.sh"

# The map itself, OS column included. Never read directly outside this file:
# every consumer goes through all_links (filtered) or all_links_raw (not).
_links_table() {
  cat <<-EOF
		zsh|config/zsh/.zshrc|$HOME/.zshrc||shell
		p10k|config/p10k/.p10k.zsh|$HOME/.p10k.zsh||shell
		starship|config/starship|$HOME/.config/starship||shell
		ohmyposh|config/ohmyposh/theme.omp.json|$HOME/.config/oh-my-posh/theme.omp.json||shell
		ghostty|config/ghostty/config|$HOME/.config/ghostty/config||terminal
		ghostty|config/ghostty/config|$HOME/Library/Application Support/Muxy/ghostty.conf||terminal||macos
		herdr|config/herdr/herder.toml|$HOME/.config/herdr/config.toml|app-writable|ai-herdr
		tmux|config/tmux/tmux.conf|$HOME/.config/tmux/tmux.conf||terminal
		yazi|config/yazi/yazi.toml|$HOME/.config/yazi/yazi.toml||terminal
		yazi|config/yazi/keymap.toml|$HOME/.config/yazi/keymap.toml||terminal
		yazi|config/yazi/theme.toml|$HOME/.config/yazi/theme.toml||terminal
		linearmouse|config/linearmouse/linearmouse.json|$HOME/.config/linearmouse/linearmouse.json||desktop-linearmouse||macos
		aerospace|config/aerospace/aerospace.toml|$HOME/.config/aerospace/aerospace.toml||desktop-aerospace||macos
		sketchybar|config/sketchybar|$HOME/.config/sketchybar||desktop-sketchybar||macos
		yabai|config/yabai|$HOME/.config/yabai||desktop-yabai||macos
		skhd|config/skhd|$HOME/.config/skhd||desktop-skhd||macos
		borders|config/borders/bordersrc|$HOME/.config/borders/bordersrc||desktop-borders||macos
		vscode|config/vscode/settings.json|$HOME/Library/Application Support/Code/User/settings.json||vscode|code|macos
		vscode|config/vscode/keybindings.json|$HOME/Library/Application Support/Code/User/keybindings.json||vscode|code|macos
		hunk|config/hunk/config.toml|$HOME/.config/hunk/config.toml||git|hunk
		lazygit|config/lazygit/config.yml|$HOME/.config/lazygit/config.yml||git|lazygit
		git|config/git/ignore|$HOME/.config/git/ignore||git|git
		claude|config/claude/statusline-command.sh|$HOME/.claude/statusline-command.sh||ai|claude
	EOF
}

# _emit_links [family]
#
# Emits the map with the OS column stripped, so every positional reader (and
# the installer context JSON) keeps seeing the six-field row it always did.
# With a family, rows declaring a different one are dropped.
_emit_links() {
  local family=${1:-} row os
  local -a fields
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS='|' read -r -a fields <<<"$row"
    os=${fields[6]:-}
    if [[ -n "$family" && -n "$os" && "$os" != "$family" ]]; then
      [[ "${LINK_VERBOSE:-false}" == true ]] &&
        echo "skipping ${fields[0]}: does not apply to this OS ($family)" >&2
      continue
    fi
    printf '%s\n' "${row%|"$os"}"
  done < <(_links_table)
}

# The rows that apply to this machine. `dot link`, `dot doctor` and the
# installer context are all about what THIS host should have.
all_links() { _emit_links "$(os_family)"; }

# Every row, whatever the platform. `dot unlink` and `dot link <name>` must see
# a target that a previous platform (or a previous checkout) created.
all_links_raw() { _emit_links; }

# Opt-in links, in the same `name|source|target` shape. These are never walked
# by `dot link` / `dot link all`: each one hands an AI agent a file it reads on
# every run, so it stays a deliberate `dot link <name>`. `dot unlink` still
# cleans them up.
optional_links() {
  cat <<-EOF
	agents|ai/AGENTS.md|$HOME/.claude/CLAUDE.md|||ai
	agents|ai/AGENTS.md|$HOME/.agents/AGENTS.md|||ai
	agents|ai/AGENTS.md|$HOME/.config/opencode/AGENTS.md|||ai
	opencode|config/opencode/opencode.jsonc|$HOME/.config/opencode/opencode.jsonc|||ai
	agents|ai/rules/general.md|$HOME/.agents/rules/general.md|||ai
	agents|ai/rules/general.md|$HOME/.claude/rules/general.md|||ai
	EOF
}

# Every name `dot link <name>` accepts, space-separated. Unfiltered: `dot link
# yabai` must still be a recognised name on a host yabai will never run on.
link_names() {
  {
    all_links_raw
    optional_links
  } | cut -d'|' -f1 | sort -u | paste -sd ' ' -
}

# The subset that a bare `dot link` skips.
optional_link_names() {
  optional_links | cut -d'|' -f1 | sort -u | paste -sd ' ' -
}

# _walk_links <map-function> <action-function> [name-filter]
_walk_links() {
  local map="$1" action="$2" filter="${3:-}" name source target mode component requirement
  while IFS='|' read -r name source target mode component requirement; do
    [[ -n "$source" ]] || continue
    [[ -z "$filter" || "$name" == "$filter" ]] || continue
    if [[ "$action" == link_file && "${LINK_FORCE:-false}" != true && -n "$component" ]] && ! component_selected "$component"; then
      [[ "${LINK_VERBOSE:-false}" == true ]] && echo "skipping $name: component $component is not selected" >&2
      continue
    fi
    if [[ "$action" == link_file && "${LINK_FORCE:-false}" != true && -n "$requirement" ]] &&
      ! is_executable "$(platform_binary "$requirement")"; then
      [[ "${LINK_VERBOSE:-false}" == true ]] && echo "skipping $name: missing requirement $requirement" >&2
      continue
    fi
    "$action" "$source" "$target" "$mode"
  done < <("$map")
}

link_all() {
  _walk_links all_links link_file
}

# Link every target sharing a name (`ghostty` -> two rows). Unknown names fail
# loudly instead of silently doing nothing.
link_named() {
  local name="$1" map
  for map in all_links_raw optional_links; do
    if "$map" | cut -d'|' -f1 | grep -qx "$name"; then
      log "Linking $name"
      _walk_links "$map" link_file "$name"
      return 0
    fi
  done
  echo "no such link: $name — try: $(link_names)" >&2
  return 1
}

unlink_all() {
  _walk_links all_links_raw unlink_file
  _walk_links optional_links unlink_file
}
