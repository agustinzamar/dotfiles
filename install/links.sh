#!/usr/bin/env bash
# Symlink map. Sourced by bin/dot.
#
# The map is data: one `name|source|target` triple per line, where source is
# relative to the repo root and name is how `dot link <name>` selects a config
# or a group. A name may appear more than once (ghostty serves two targets).
# link/unlink walk the same map, so a path is declared exactly once.

shell_links() {
	cat <<-EOF
		zsh|config/zsh/.zshrc|$HOME/.zshrc
		p10k|config/p10k/.p10k.zsh|$HOME/.p10k.zsh
	EOF
}

all_links() {
  shell_links
  cat <<-EOF
		ghostty|config/ghostty/config|$HOME/.config/ghostty/config
		ghostty|config/ghostty/config|$HOME/Library/Application Support/Muxy/ghostty.conf
		ghostty|config/ghostty/theme/catppuccin-frappe.conf|$HOME/.config/ghostty/themes/catppuccin-frappe.conf
		herdr|config/herdr/herder.toml|$HOME/.config/herdr/config.toml|app-writable
		tmux|config/tmux/tmux.conf|$HOME/.config/tmux/tmux.conf
		yazi|config/yazi/yazi.toml|$HOME/.config/yazi/yazi.toml
		yazi|config/yazi/keymap.toml|$HOME/.config/yazi/keymap.toml
		yazi|config/yazi/theme.toml|$HOME/.config/yazi/theme.toml
		linearmouse|config/linearmouse/linearmouse.json|$HOME/.config/linearmouse/linearmouse.json
		aerospace|config/aerospace/aerospace.toml|$HOME/.config/aerospace/aerospace.toml
		npm|config/npm/.npmrc|$HOME/.npmrc
		vscode|config/vscode/settings.json|$HOME/Library/Application Support/Code/User/settings.json
		vscode|config/vscode/keybindings.json|$HOME/Library/Application Support/Code/User/keybindings.json
		opencode|config/opencode/themes|$HOME/.config/opencode/themes
		opencode|ai/AGENTS.md|$HOME/.config/opencode/AGENTS.md
		hunk|config/hunk/config.toml|$HOME/.config/hunk/config.toml
		lazygit|config/lazygit/config.yml|$HOME/.config/lazygit/config.yml
		git|config/git/ignore|$HOME/.config/git/ignore
	EOF
}

# Every name `dot link <name>` accepts, space-separated.
link_names() {
  all_links | cut -d'|' -f1 | sort -u | paste -sd ' ' -
}

# _walk_links <map-function> <action-function> [name-filter]
_walk_links() {
  local map="$1" action="$2" filter="${3:-}" name source target mode
  while IFS='|' read -r name source target mode; do
    [[ -n "$source" ]] || continue
    [[ -z "$filter" || "$name" == "$filter" ]] || continue
    "$action" "$source" "$target" "$mode"
  done < <("$map")
}

link_shell() {
  _walk_links shell_links link_file
}

link_all() {
  _walk_links all_links link_file
}

# Link every target sharing a name (`ghostty` -> two rows). Unknown names fail
# loudly instead of silently doing nothing.
link_named() {
  local name="$1"
  if ! all_links | cut -d'|' -f1 | grep -qx "$name"; then
    echo "no such link: $name — try: $(link_names)" >&2
    return 1
  fi
  log "Linking $name"
  _walk_links all_links link_file "$name"
}

unlink_all() { _walk_links all_links unlink_file; }
