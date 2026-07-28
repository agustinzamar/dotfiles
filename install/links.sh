#!/usr/bin/env bash
# Symlink map. Sourced by bin/dot.
#
# The map is data: one `source|target` pair per line, where source is relative
# to the repo root. link/unlink both walk the same list, so a path is declared
# exactly once.

shell_links() {
  cat <<-EOF
		config/zsh/.zshrc|$HOME/.zshrc
		config/p10k/.p10k.zsh|$HOME/.p10k.zsh
		home/.exports|$HOME/.dotfiles-home/.exports
	EOF

  local file rel
  for file in "$DOTFILES_DIR"/home/aliases/*.zsh "$DOTFILES_DIR"/home/functions/*.zsh; do
    [[ -e "$file" ]] || continue
    rel=${file#"$DOTFILES_DIR"/}
    printf '%s|%s\n' "$rel" "$HOME/.dotfiles-home/${rel#home/}"
  done
}

all_links() {
  shell_links
  cat <<-EOF
		config/ghostty/config|$HOME/.config/ghostty/config
		config/tmux/tmux.conf|$HOME/.config/tmux/tmux.conf
		config/yazi/yazi.toml|$HOME/.config/yazi/yazi.toml
		config/yazi/keymap.toml|$HOME/.config/yazi/keymap.toml
		config/yazi/theme.toml|$HOME/.config/yazi/theme.toml
		config/ghostty/config|$HOME/Library/Application Support/Muxy/ghostty.conf
		config/npm/.npmrc|$HOME/.npmrc
		config/herd/herd.json|$HOME/Library/Application Support/Herd/config/herd.json
		config/vscode/settings.json|$HOME/Library/Application Support/Code/User/settings.json
		config/vscode/keybindings.json|$HOME/Library/Application Support/Code/User/keybindings.json
		config/claude/settings.json|$HOME/.claude/settings.json
		config/opencode/skills|$HOME/.claude/skills
		config/opencode/agents|$HOME/.claude/agents
		config/opencode/opencode.json|$HOME/.config/opencode/opencode.json
		config/opencode/AGENTS.md|$HOME/.config/opencode/AGENTS.md
		config/opencode/plugins|$HOME/.config/opencode/plugins
		config/opencode/skills|$HOME/.config/opencode/skills
		config/opencode/themes|$HOME/.config/opencode/themes
		config/opencode/agents|$HOME/.config/opencode/agents
		config/opencode/commands|$HOME/.config/opencode/commands
		config/hunk/config.toml|$HOME/.config/hunk/config.toml
	EOF
}

# _walk_links <map-function> <action-function>
_walk_links() {
  local source target
  while IFS='|' read -r source target; do
    [[ -n "$source" ]] || continue
    "$2" "$source" "$target"
  done < <("$1")
}

link_shell() { _walk_links shell_links link_file; }
link_all() { _walk_links all_links link_file; }
unlink_all() { _walk_links all_links unlink_file; }
