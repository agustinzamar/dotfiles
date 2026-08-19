#!/usr/bin/env bash
# Symlink map. Sourced by bin/dot.
#
# The map is data: one `name|source|target` triple per line, where source is
# relative to the repo root and name is how `dot link <name>` selects a config
# or a group. A name may appear more than once (ghostty serves two targets).
# link/unlink walk the same map, so a path is declared exactly once.

all_links() {
  cat <<-EOF
		zsh|config/zsh/.zshrc|$HOME/.zshrc||shell
		p10k|config/p10k/.p10k.zsh|$HOME/.p10k.zsh||shell
		ghostty|config/ghostty/config|$HOME/.config/ghostty/config||terminal
		ghostty|config/ghostty/config|$HOME/Library/Application Support/Muxy/ghostty.conf||terminal
		ghostty|config/ghostty/theme/catppuccin-macchiato.conf|$HOME/.config/ghostty/themes/catppuccin-macchiato.conf||terminal
		herdr|config/herdr/herder.toml|$HOME/.config/herdr/config.toml|app-writable|ai-herdr
		tmux|config/tmux/tmux.conf|$HOME/.config/tmux/tmux.conf||terminal
		yazi|config/yazi/yazi.toml|$HOME/.config/yazi/yazi.toml||terminal
		yazi|config/yazi/keymap.toml|$HOME/.config/yazi/keymap.toml||terminal
		yazi|config/yazi/theme.toml|$HOME/.config/yazi/theme.toml||terminal
		linearmouse|config/linearmouse/linearmouse.json|$HOME/.config/linearmouse/linearmouse.json||desktop-linearmouse
		aerospace|config/aerospace/aerospace.toml|$HOME/.config/aerospace/aerospace.toml||desktop-aerospace
		sketchybar|config/sketchybar|$HOME/.config/sketchybar||desktop-sketchybar
		borders|config/borders/bordersrc|$HOME/.config/borders/bordersrc||desktop-borders
		npm|config/npm/.npmrc|$HOME/.npmrc||dev
		vscode|config/vscode/settings.json|$HOME/Library/Application Support/Code/User/settings.json||vscode|code
		vscode|config/vscode/keybindings.json|$HOME/Library/Application Support/Code/User/keybindings.json||vscode|code
		opencode|config/opencode/themes|$HOME/.config/opencode/themes||ai|opencode
		hunk|config/hunk/config.toml|$HOME/.config/hunk/config.toml||git|hunk
		lazygit|config/lazygit/config.yml|$HOME/.config/lazygit/config.yml||git|lazygit
		git|config/git/ignore|$HOME/.config/git/ignore||git|git
		claude|config/claude/statusline-command.sh|$HOME/.claude/statusline-command.sh||ai|claude
	EOF
}

# Opt-in links, in the same `name|source|target` shape. These are never walked
# by `dot link` / `dot link all`: each one hands an AI agent a file it reads on
# every run, so it stays a deliberate `dot link <name>`. `dot unlink` still
# cleans them up.
optional_links() {
  cat <<-EOF
		agents|ai/AGENTS.md|$HOME/.claude/CLAUDE.md|||ai
		agents|ai/AGENTS.md|$HOME/.agents/AGENTS.md|||ai
		agents|ai/AGENTS.md|$HOME/.config/opencode/AGENTS.md|||ai
	EOF
}

# Every name `dot link <name>` accepts, space-separated.
link_names() {
  {
    all_links
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
		if [[ "$action" == link_file && "${LINK_FORCE:-false}" != true && -n "$requirement" ]] && ! is_executable "$requirement"; then
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
  for map in all_links optional_links; do
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
  _walk_links all_links unlink_file
  _walk_links optional_links unlink_file
}
