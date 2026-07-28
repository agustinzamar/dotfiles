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
		system/.exports|$HOME/.dotfiles-home/.exports
	EOF

  # completions/ holds zsh completion functions, which are named `_command`
  # rather than *.zsh, so it needs its own glob.
  local file rel
  for file in "$DOTFILES_DIR"/system/aliases/*.zsh \
    "$DOTFILES_DIR"/system/functions/*.zsh \
    "$DOTFILES_DIR"/system/env/*.zsh \
    "$DOTFILES_DIR"/system/completions/_*; do
    [[ -e "$file" ]] || continue
    rel=${file#"$DOTFILES_DIR"/}
    printf '%s|%s\n' "$rel" "$HOME/.dotfiles-home/${rel#system/}"
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
		config/opencode/opencode.json|$HOME/.config/opencode/opencode.json
		config/opencode/AGENTS.md|$HOME/.config/opencode/AGENTS.md
		config/opencode/themes|$HOME/.config/opencode/themes
		config/hunk/config.toml|$HOME/.config/hunk/config.toml
		config/git/ignore|$HOME/.config/git/ignore
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

# The shell files are globbed, not listed, so renaming one leaves the old
# symlink behind pointing at a source that no longer exists. Zsh still matches
# it and fails to source it on every prompt, so sweep those after linking.
#
# Any dangling link here is ours: link_file creates every entry under
# .dotfiles-home and nothing else writes there. Matching on the target path
# would miss the stale ones, which point through ~/.dotfiles or at a previous
# clone rather than at $DOTFILES_DIR.
prune_shell_links() {
  local link
  for link in "$HOME"/.dotfiles-home/aliases/* \
    "$HOME"/.dotfiles-home/functions/* \
    "$HOME"/.dotfiles-home/env/* \
    "$HOME"/.dotfiles-home/completions/*; do
    [[ -L "$link" && ! -e "$link" ]] && run rm "$link"
  done
  return 0
}

link_shell() {
  _walk_links shell_links link_file
  prune_shell_links
}

link_all() {
  _walk_links all_links link_file
  prune_shell_links
}

unlink_all() { _walk_links all_links unlink_file; }
