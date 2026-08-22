#!/usr/bin/env bats

# Binary resolution order for bin/dot (dot-cli-bootstrap spec): 1. prebuilt
# binary, 2. Bun >= .bun-version builds from source, 3. actionable bootstrap
# guidance. The Go toolchain must never appear anywhere in this path.
#
# The real bin/dot-tui is a build artifact, so each test moves it aside and
# teardown restores it byte-for-byte.

setup() {
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOT="$DOTFILES_DIR/bin/dot"
  TUI_BIN="$DOTFILES_DIR/bin/dot-tui"
  SANDBOX="$(mktemp -d)"

  # A PATH that contains neither bun nor go unless a stub adds one. /usr/bin
  # and /bin keep dirname/sort/mktemp working inside bin/dot itself.
  BASE_PATH="/usr/bin:/bin"

  if [ -e "$TUI_BIN" ]; then
    mv "$TUI_BIN" "$SANDBOX/saved-dot-tui"
  fi

  make_stub_binary() {
    cat >"$TUI_BIN" <<'EOF'
#!/bin/sh
printf 'TUI-STUB %s\n' "$*"
EOF
    chmod +x "$TUI_BIN"
  }

  # A fake `bun` whose version comes from $FAKE_BUN_VERSION. `bun install` is a
  # no-op; `bun build --compile ... --outfile X` writes an executable that
  # announces its arguments, standing in for the compiled binary.
  make_bun_stub() {
    cat >"$SANDBOX/bun" <<EOF
#!/bin/sh
FAKE_BUN_VERSION='$1'
case "\$1" in
  --version) printf '%s\n' "\$FAKE_BUN_VERSION"; exit 0 ;;
esac
if [ "\$1" = "install" ]; then exit 0; fi
if [ "\$1" = "build" ]; then
  prev=""
  for a in "\$@"; do
    [ "\$prev" = "--outfile" ] && out="\$a"
    prev="\$a"
  done
  [ -n "\$out" ] || exit 1
  printf '#!/bin/sh\nprintf '"'"'TUI-STUB %%s\\n'"'"' "\$*"\n' >"\$out"
  chmod +x "\$out"
  exit 0
fi
exit 0
EOF
    chmod +x "$SANDBOX/bun"
  }
}

teardown() {
  rm -f "$TUI_BIN"
  if [ -f "$SANDBOX/saved-dot-tui" ]; then
    mv "$SANDBOX/saved-dot-tui" "$TUI_BIN"
  fi
  rm -rf "$SANDBOX"
}

# Scenario: Prebuilt binary used directly on a clean machine — no bun, no go,
# yet the TUI runs with its arguments passed through untouched.
@test "dot tui runs an existing dot-tui directly without any toolchain" {
  make_stub_binary
  run env PATH="$BASE_PATH" "$DOT" tui some-flag
  [ "$status" -eq 0 ]
  [[ "$output" == "TUI-STUB some-flag" ]]
}

# Scenario: Local Bun builds from source as fallback — binary absent, Bun at
# the pinned minimum: resolver builds via bun install + bun build --compile,
# then launches the fresh binary. No Go anywhere.
@test "missing binary with sufficient bun builds from source then runs" {
  make_bun_stub "1.3.14"
  run env PATH="$SANDBOX:$BASE_PATH" "$DOT" tui hello
  [ "$status" -eq 0 ]
  [[ "$output" == *"Building dot-tui"* ]]
  [[ "$output" == *"TUI-STUB hello"* ]]
  # The build actually produced the artifact where the resolver expects it.
  [ -x "$TUI_BIN" ]
}

# Below-minimum Bun must NOT take the source-build path: same guidance as no
# Bun at all, explicit non-zero failure.
@test "missing binary with too-old bun prints bootstrap guidance and fails" {
  make_bun_stub "1.0.0"
  run env PATH="$SANDBOX:$BASE_PATH" "$DOT" tui
  [ "$status" -ne 0 ]
  [[ "$output" != *"TUI-STUB"* ]]
  [[ "$output" != *"Building"* ]]
  [[ "$output" == *"remote-install.sh"* ]]
}

# Scenario: Neither binary nor Bun yields guidance — names the official
# bootstrap script, exits non-zero, never mentions Go.
@test "missing binary without bun prints bootstrap guidance and fails" {
  run env PATH="$BASE_PATH" "$DOT" tui
  [ "$status" -ne 0 ]
  [[ "$output" == *"bootstrap"* ]]
  [[ "$output" == *"curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash"* ]]
  ! grep -qiE '\bgo\b|go run' <<<"$output"
}

# Both TUI entry points must route through the resolver: profile installation
# forwards exactly -apply -profile <path> (plus -dry-run in dry-run mode).
@test "install --profile forwards apply flags through the resolver" {
  make_stub_binary
  run env PATH="$BASE_PATH" HOME="$(mktemp -d)" \
    "$DOT" install --profile /tmp/p.json --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == "TUI-STUB -apply -profile /tmp/p.json -dry-run" ]]
}
