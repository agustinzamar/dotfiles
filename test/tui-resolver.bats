#!/usr/bin/env bats

# Binary resolution order for bin/dot (dot-cli-bootstrap spec): 1. prebuilt
# binary, 2. Bun >= .bun-version builds from source, 3. actionable bootstrap
# guidance. The Go toolchain must never appear anywhere in this path.
#
# `dot tui` is gone (tui-default-install PR 3): the resolver is exercised by the
# interactive install path (run_interactive_install resolves the binary via
# dot_runtime_path, so the resolution order is covered), and the TTY guard and
# PTY tests at the bottom exercise the interactive launch. The interactive
# launch needs the context JSON (ADR-5), so every resolver call below carries
# --context.
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
  #
  # It leads with a `uname` stub reporting Darwin: `dot install` refuses to
  # install packages off macOS (test/doctor.bats), and these tests are about
  # the installer's binary-resolution contract, not about the host running the
  # suite. Declaring the platform keeps them asserting the same thing on both.
  mkdir -p "$SANDBOX/os"
  printf '#!/bin/sh\necho Darwin\n' >"$SANDBOX/os/uname"
  chmod +x "$SANDBOX/os/uname"
  BASE_PATH="$SANDBOX/os:/usr/bin:/bin"
  # Path-first bun lookup only: this machine has a real bun at a known
  # location that would otherwise defeat the fake-bun stubs below.
  export DOT_RUNTIME_BUN_LOOKUP=path

  if [ -e "$TUI_BIN" ]; then
    mv "$TUI_BIN" "$SANDBOX/saved-dot-tui"
  fi

      make_stub_binary() {
        cat >"$TUI_BIN" <<'EOF'
#!/bin/sh
case "$1" in
  --version) printf '%s\n' 'dot-tui-context-v12'; exit 0 ;;
esac
printf 'TUI-STUB %s\n' "$*"
EOF
        chmod +x "$TUI_BIN"
      }

      # A foreign/stale binary that does NOT speak the version contract.
      make_stale_binary() {
        cat >"$TUI_BIN" <<'EOF'
#!/bin/sh
printf 'OLD-TUI-STUB %s\n' "$*"
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
  printf '#!/bin/sh\ncase "$1" in\n--version) printf '"'"'%s\\n'"'"' "dot-tui-context-v12"; exit 0 ;;\nesac\nprintf '"'"'TUI-STUB %%s\\n'"'"' "\$*"\n' >"\$out"
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

# Scenario: Piped stdin without flags. The TTY guard must fire before any
# provisioning, so a piped `curl | bash` dies in milliseconds instead of
# installing Homebrew or hanging. --dry-run keeps this test safe on the day the
# guard is missing (the old bare path would dry-run cleanly and exit 0).
@test "bare install under non-TTY stdin fails naming --all and --profile" {
  run env PATH="$BASE_PATH" "$DOT" install --dry-run </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"stdin is not a TTY"* ]]
  [[ "$output" == *"--all"* ]]
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
#
# `script`'s argv is not portable. BSD/macOS takes the typescript file first
# and the command as trailing argv; util-linux takes the command as one string
# via -c and the file last, and rejects the BSD form outright ("unexpected
# number of arguments"), so the command never ran and the assertions below
# could not pass on Linux. Both branches run the same command and assert the
# same behaviour.
@test "interactive install with an unlaunchable runtime fails naming the headless flags" {
  local scratch_home
  scratch_home="$(mktemp -d)"
  if [[ "$(uname -s)" == Darwin ]]; then
    run script -q /dev/null env PATH="$BASE_PATH" HOME="$scratch_home" \
      "$DOT" install --dry-run
  else
    run script -qec "env PATH='$BASE_PATH' HOME='$scratch_home' '$DOT' install --dry-run" /dev/null
  fi
  [ "$status" -ne 0 ]
  [[ "$output" == *"TUI unavailable"* ]]
  [[ "$output" == *"--all"* ]]
}
