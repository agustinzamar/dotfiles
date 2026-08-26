#!/usr/bin/env bats

# Binary resolution order for bin/dot (dot-cli-bootstrap spec): 1. prebuilt
# binary, 2. Bun >= .bun-version builds from source, 3. actionable bootstrap
# guidance. The Go toolchain must never appear anywhere in this path.
#
# `dot tui` is gone (tui-default-install PR 3): the headless `--profile` path is
# what exercises the resolver here (run_dot_tui is shared, so the resolution
# order is covered identically), and the interactive path is covered by the
# TTY-guard and PTY tests at the bottom. The interactive launch needs the
# context JSON (ADR-5), so every resolver call below carries `--context`.
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
  # Path-first bun lookup only: this machine has a real bun at a known
  # location that would otherwise defeat the fake-bun stubs below.
  export DOT_RUNTIME_BUN_LOOKUP=path

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
# yet the TUI runs with its arguments passed through untouched. Headless
# --profile must also pass the context file (the TUI refuses to run without it).
@test "install --profile runs an existing dot-tui directly without any toolchain" {
  make_stub_binary
  run env PATH="$BASE_PATH" "$DOT" install --profile /tmp/p.json
  [ "$status" -eq 0 ]
  [[ "$output" == "TUI-STUB -apply -profile /tmp/p.json --context "* ]]
}

# Scenario: Local Bun builds from source as fallback — binary absent, Bun at
# the pinned minimum: resolver builds via bun install + bun build --compile,
# then launches the fresh binary. No Go anywhere.
@test "missing binary with sufficient bun builds from source then runs" {
  make_bun_stub "1.3.14"
  run env PATH="$SANDBOX:$BASE_PATH" "$DOT" install --profile /tmp/p.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"Building dot-tui"* ]]
  [[ "$output" == *"TUI-STUB -apply -profile /tmp/p.json"* ]]
  # The build actually produced the artifact where the resolver expects it.
  [ -x "$TUI_BIN" ]
}

# Below-minimum Bun must NOT take the source-build path: same guidance as no
# Bun at all, explicit non-zero failure.
@test "missing binary with too-old bun prints bootstrap guidance and fails" {
  make_bun_stub "1.0.0"
  run env PATH="$SANDBOX:$BASE_PATH" "$DOT" install --profile /tmp/p.json
  [ "$status" -ne 0 ]
  [[ "$output" != *"TUI-STUB"* ]]
  [[ "$output" != *"Building"* ]]
  [[ "$output" == *"remote-install.sh"* ]]
}

# Scenario: Neither binary nor Bun yields guidance — names the official
# bootstrap script, exits non-zero, never mentions Go.
@test "missing binary without bun prints bootstrap guidance and fails" {
  run env PATH="$BASE_PATH" "$DOT" install --profile /tmp/p.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"bootstrap"* ]]
  [[ "$output" == *"curl -fsSL https://raw.githubusercontent.com/agustinzamar/dotfiles/main/remote-install.sh | bash"* ]]
  ! grep -qiE '\bgo\b|go run' <<<"$output"
}

# Headless profile install forwards exactly -apply -profile <path> --context
# <file> (plus -dry-run in dry-run mode) through the resolver.
@test "install --profile forwards apply flags and the context through the resolver" {
  make_stub_binary
  run env PATH="$BASE_PATH" HOME="$(mktemp -d)" \
    "$DOT" install --profile /tmp/p.json --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-apply -profile /tmp/p.json"* ]]
  [[ "$output" == *"-dry-run"* ]]
  [[ "$output" == *"--context"* ]]
}

# Scenario: Piped stdin without flags. The TTY guard must fire before any
# provisioning, so a piped `curl | bash` dies in milliseconds instead of
# installing Homebrew or hanging. --dry-run keeps this test safe on the day the
# guard is missing (the old bare path would dry-run cleanly and exit 0).
@test "bare install under non-TTY stdin fails naming --all and --profile" {
  run env PATH="$BASE_PATH" "$DOT" install --dry-run </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"stdin is not a TTY"* ]]
  [[ "$output" == *"--all"* && "$output" == *"--profile"* ]]
}

# The TTY guard must not fire for the headless paths: a closed stdin with
# --profile still reaches the resolver (no TTY needed, no UI mounted).
@test "install --profile works without a TTY" {
  make_stub_binary
  run env PATH="$BASE_PATH" "$DOT" install --profile /tmp/p.json </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"TUI-STUB"* ]]
  [[ "$output" != *"stdin is not a TTY"* ]]
}

# Scenario: `dot tui` is hard-removed — an ordinary unknown command, no shim.
@test "dot tui is gone — an ordinary unknown command" {
  run env PATH="$BASE_PATH" "$DOT" tui
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a known command"* ]]
  ! grep -q 'sub_tui' "$DOT"
  ! grep -q 'TOP_COMMANDS=.* tui ' "$DOT"
}

# Scenario: Runtime bootstrap fails interactively (TTY present, but no bun and
# no prebuilt binary): exits non-zero naming the headless alternatives — never
# silent, never falls back to the old baseline. The bats harness has no TTY, so
# `script` allocates one to get past the TTY guard to the runtime bootstrap.
@test "interactive install with an unlaunchable runtime fails naming the headless flags" {
  run script -q /dev/null env PATH="$BASE_PATH" HOME="$(mktemp -d)" \
    "$DOT" install --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"TUI unavailable"* ]]
  [[ "$output" == *"--all"* && "$output" == *"--profile"* ]]
}