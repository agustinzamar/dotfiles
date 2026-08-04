#!/usr/bin/env bats

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MUXY="$DOTFILES_DIR/install/muxy.sh"
}

_muxy_common_setup() {
  local repo
  repo="$(mktemp -d)"
  mkdir -p "$repo/install"
  cp "$DOTFILES_DIR/install/common.sh" "$repo/install/common.sh"
  printf '%s' "$repo"
}

@test "muxy with no arguments prints usage" {
  run "$MUXY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "muxy help prints usage" {
  run "$MUXY" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"export"* ]]
  [[ "$output" == *"import"* ]]
}

@test "muxy export writes muxy config export to the repo config" {
  local stub repo
  stub="$(mktemp -d)"
  repo="$(_muxy_common_setup)"
  mkdir -p "$repo/config/muxy"
  cat >"$stub/muxy" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$MUXY_LOG"
printf '{"mock":true}\n'
EOF
  chmod +x "$stub/muxy"

  MUXY_LOG="$stub/log" PATH="$stub:$PATH" DOTFILES_DIR="$repo" run "$MUXY" export
  [ "$status" -eq 0 ]
  [ -f "$repo/config/muxy/settings.json" ]
  [[ "$(cat "$repo/config/muxy/settings.json")" == *'"mock":true'* ]]
  grep -q '^config export$' "$stub/log"
}

@test "muxy export dry-run prints the command and does not write the file" {
  local stub repo
  stub="$(mktemp -d)"
  repo="$(_muxy_common_setup)"
  mkdir -p "$repo/config/muxy"
  cat >"$stub/muxy" <<'EOF'
#!/bin/sh
exit 99
EOF
  chmod +x "$stub/muxy"

  PATH="$stub:$PATH" DOTFILES_DIR="$repo" run "$MUXY" export --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$repo/config/muxy/settings.json" ]
  [[ "$output" == *"+ muxy config export"* ]]
}

@test "muxy import requires an exported config" {
  local stub repo
  stub="$(mktemp -d)"
  repo="$(_muxy_common_setup)"
  cat >"$stub/muxy" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$stub/muxy"

  PATH="$stub:$PATH" DOTFILES_DIR="$repo" run "$MUXY" import
  [ "$status" -ne 0 ]
  [[ "$output" == *"export"* ]]
}

@test "muxy import applies the repo config via muxy config import" {
  local stub repo
  stub="$(mktemp -d)"
  repo="$(_muxy_common_setup)"
  mkdir -p "$repo/config/muxy"
  printf '{"mock":true}\n' >"$repo/config/muxy/settings.json"
  cat >"$stub/muxy" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$MUXY_LOG"
exit 0
EOF
  chmod +x "$stub/muxy"

  MUXY_LOG="$stub/log" PATH="$stub:$PATH" DOTFILES_DIR="$repo" run "$MUXY" import
  [ "$status" -eq 0 ]
  grep -q "^config import $repo/config/muxy/settings.json\$" "$stub/log"
}

@test "muxy import dry-run prints the command and does not call muxy" {
  local stub repo
  stub="$(mktemp -d)"
  repo="$(_muxy_common_setup)"
  mkdir -p "$repo/config/muxy"
  printf '{"mock":true}\n' >"$repo/config/muxy/settings.json"
  cat >"$stub/muxy" <<'EOF'
#!/bin/sh
exit 99
EOF
  chmod +x "$stub/muxy"

  PATH="$stub:$PATH" DOTFILES_DIR="$repo" run "$MUXY" import --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"+ muxy config import"* ]]
}

@test "muxy reports when muxy is not installed" {
  local repo
  repo="$(_muxy_common_setup)"
  # Exclude /usr/local/bin where the real muxy may live.
  PATH="/usr/bin:/bin" DOTFILES_DIR="$repo" run "$MUXY" export
  [ "$status" -ne 0 ]
  [[ "$output" == *"install Muxy first"* ]]
}

@test "muxy unknown command exits 1" {
  run "$MUXY" definitely-not-a-command
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}
