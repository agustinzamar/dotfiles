#!/usr/bin/env bats
# Contract tests for install/links.sh: the OS-applicability column on the link
# map, the filtered (`all_links`) and unfiltered (`all_links_raw`) walks, and
# the platform-aware requirement gate.
#
# The sandbox (scratch HOME, curated PATH, `uname` stub, escape guard) lives in
# test/box.bash — read the safety note there before adding a test here.

load box

setup() { box_setup; }
teardown() { box_teardown; }

# Evaluate a snippet with the link map loaded inside the same box.
links_sh() {
  env -i \
    HOME="$SCRATCH_HOME" \
    PATH="$STUB_BIN:$REAL_BIN" \
    DOTFILES_DIR="$DOTFILES_DIR" \
    DRY_RUN=true \
    "$BASH" -c '
      set -u
      . "$DOTFILES_DIR/install/common.sh"
      . "$DOTFILES_DIR/install/components.sh"
      . "$DOTFILES_DIR/install/links.sh"
      eval "$1"' _ "$1"
}

# Walk a one-row fixture map whose requirement is `bat` through the real
# linker. _walk_links only applies the requirement gate to link_file, so the
# gate cannot be exercised with a recording stand-in.
requirement_walk() {
  links_sh '
    bat_row() { printf "%s\n" "batdemo|config/zsh/.zshrc|$HOME/.batdemo||shell|bat"; }
    _walk_links bat_row link_file'
}

# ---------------------------------------------------------------------------
# The OS column (task 3.1)
# ---------------------------------------------------------------------------

@test "exactly the macOS-only rows declare macos in the OS column" {
  box_family macos
  local declared expected
  declared=$(links_sh '_links_table' | awk -F'|' '$7 == "macos" { print $3 }' | sort)
  expected=$(printf '%s\n' \
    "$SCRATCH_HOME/Library/Application Support/Muxy/ghostty.conf" \
    "$SCRATCH_HOME/Library/Application Support/Code/User/settings.json" \
    "$SCRATCH_HOME/Library/Application Support/Code/User/keybindings.json" \
    "$SCRATCH_HOME/.config/linearmouse/linearmouse.json" \
    "$SCRATCH_HOME/.config/aerospace/aerospace.toml" \
    "$SCRATCH_HOME/.config/sketchybar" \
    "$SCRATCH_HOME/.config/yabai" \
    "$SCRATCH_HOME/.config/skhd" \
    "$SCRATCH_HOME/.config/borders/bordersrc" | sort)
  [ "$declared" = "$expected" ]
}

@test "portable rows carry no OS declaration" {
  box_family macos
  local portable
  portable=$(links_sh '_links_table' | awk -F'|' '$7 == "" { print $3 }')
  [[ "$portable" == *"$SCRATCH_HOME/.zshrc"* ]]
  [[ "$portable" == *"$SCRATCH_HOME/.config/tmux/tmux.conf"* ]]
  # A portable row may never target the macOS-only Library tree.
  ! grep -q '/Library/' <<<"$portable"
}

@test "all_links strips the OS column and keeps every row on macOS" {
  box_family macos
  local table filtered
  table=$(links_sh '_links_table')
  filtered=$(links_sh 'all_links')
  [ "$(wc -l <<<"$table")" -eq "$(wc -l <<<"$filtered")" ]
  # The six-field shape every positional reader (and the context JSON) expects.
  grep -qxF \
    "vscode|config/vscode/settings.json|$SCRATCH_HOME/Library/Application Support/Code/User/settings.json||vscode|code" \
    <<<"$filtered"
  # No emitted row may still carry a seventh field.
  run awk -F'|' 'NF > 6 { print; found = 1 } END { exit !found }' <<<"$filtered"
  [ "$status" -ne 0 ]
}

@test "all_links drops the macOS-only rows on debian" {
  box_family debian
  local filtered table
  filtered=$(links_sh 'all_links')
  table=$(links_sh '_links_table')
  ! grep -q '/Library/' <<<"$filtered"
  ! grep -q '^yabai|' <<<"$filtered"
  ! grep -q '^linearmouse|' <<<"$filtered"
  grep -q "^zsh|config/zsh/.zshrc|$SCRATCH_HOME/.zshrc|" <<<"$filtered"
  [ "$(wc -l <<<"$filtered")" -eq "$(($(wc -l <<<"$table") - 9))" ]
}

@test "all_links_raw keeps every row on debian and still strips the OS column" {
  box_family debian
  local raw table
  raw=$(links_sh 'all_links_raw')
  table=$(links_sh '_links_table')
  [ "$(wc -l <<<"$raw")" -eq "$(wc -l <<<"$table")" ]
  # The OS token is gone; the trailing field is this row's empty requirement.
  grep -qxF "yabai|config/yabai|$SCRATCH_HOME/.config/yabai||desktop-yabai|" <<<"$raw"
  ! grep -q 'macos' <<<"$raw"
  run awk -F'|' 'NF > 6 { print; found = 1 } END { exit !found }' <<<"$raw"
  [ "$status" -ne 0 ]
}

@test "link <name> still resolves a macOS-only name on debian" {
  box_family debian
  run dot_cli link yabai --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"config/yabai"* ]]
}

# The set of names a user may type is the same everywhere, so help must keep
# advertising the ones a bare `dot link` skips on this host.
@test "help still advertises a macOS-only link name on debian" {
  box_family debian
  run dot_cli help
  [ "$status" -eq 0 ]
  [[ "$output" == *"yabai"* ]]
  [[ "$output" == *"linearmouse"* ]]
}

# ---------------------------------------------------------------------------
# dot link on a non-macOS host (task 3.2)
# ---------------------------------------------------------------------------

@test "dot link on debian links the portable configs and creates no Library tree" {
  box_family debian
  run dot_cli link --all
  [ "$status" -eq 0 ]
  [ "$(readlink "$SCRATCH_HOME/.zshrc")" = "$DOTFILES_DIR/config/zsh/.zshrc" ]
  [ "$(readlink "$SCRATCH_HOME/.config/tmux/tmux.conf")" = "$DOTFILES_DIR/config/tmux/tmux.conf" ]
  [ ! -e "$SCRATCH_HOME/Library" ]
  [ ! -e "$SCRATCH_HOME/.config/yabai" ]
}

@test "LINK_VERBOSE states why each inapplicable row was skipped" {
  box_family debian
  LINK_VERBOSE=true run dot_cli link --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping vscode: does not apply to this OS (debian)"* ]]
  [[ "$output" == *"skipping yabai: does not apply to this OS (debian)"* ]]
}

@test "a second dot link on debian changes nothing and makes no backup" {
  box_family debian
  dot_cli link --all
  run dot_cli link --all
  [ "$status" -eq 0 ]
  [ "$(readlink "$SCRATCH_HOME/.zshrc")" = "$DOTFILES_DIR/config/zsh/.zshrc" ]
  [ ! -e "$SCRATCH_HOME/.dotfiles-backup" ]
}

@test "dot link on macOS still links the Library targets" {
  box_family macos
  run dot_cli link --all
  [ "$status" -eq 0 ]
  [ "$(readlink "$SCRATCH_HOME/Library/Application Support/Code/User/settings.json")" \
    = "$DOTFILES_DIR/config/vscode/settings.json" ]
  [ "$(readlink "$SCRATCH_HOME/.config/yabai")" = "$DOTFILES_DIR/config/yabai" ]
}

# ---------------------------------------------------------------------------
# dot unlink ignores OS applicability (task 3.3)
# ---------------------------------------------------------------------------

@test "dot unlink removes a macOS-only target on debian" {
  box_family debian
  local target="$SCRATCH_HOME/Library/Application Support/Code/User/settings.json"
  mkdir -p "$(dirname "$target")"
  ln -s "$DOTFILES_DIR/config/vscode/settings.json" "$target"
  run dot_cli unlink
  [ "$status" -eq 0 ]
  [ ! -L "$target" ]
  [ ! -e "$target" ]
}

# ---------------------------------------------------------------------------
# The requirement gate resolves platform binary names (task 3.4)
# ---------------------------------------------------------------------------

@test "a debian-renamed binary satisfies the requirement" {
  box_family debian
  stub batcat 'exit 0'
  run requirement_walk
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s"* ]]
  [[ "$output" == *".batdemo"* ]]
}

@test "the row is skipped when neither the tool nor its debian name is present" {
  box_family debian
  run requirement_walk
  [ "$status" -eq 0 ]
  [[ "$output" != *"ln -s"* ]]
}

@test "on macOS the requirement keeps the tool's own name" {
  box_family macos
  stub bat 'exit 0'
  run requirement_walk
  [ "$status" -eq 0 ]
  [[ "$output" == *"ln -s"* ]]
}

@test "the debian rename does not leak onto macOS" {
  box_family macos
  stub batcat 'exit 0'
  run requirement_walk
  [ "$status" -eq 0 ]
  [[ "$output" != *"ln -s"* ]]
}
