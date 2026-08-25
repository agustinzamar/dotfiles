#!/usr/bin/env bats

# Fresh-machine bootstrap (dot-cli-bootstrap resolution step 1, ADR-5):
# remote-install.sh tries a best-effort prebuilt dot-tui download between the
# clone and `exec bin/dot install`. Any failure is silent — the flow falls into
# bin/dot's resolver, which builds from source or prints guidance.

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_DIR/remote-install.sh"
  SANDBOX="$(mktemp -d)"
  TARGET="$SANDBOX/target"
  STUBS="$SANDBOX/stubs"
  URL_LOG="$SANDBOX/urls.log"

  mkdir -p "$TARGET/bin" "$TARGET/.git" "$STUBS"

  # The stub `dot` proves the script reached its final exec line.
  cat >"$TARGET/bin/dot" <<'EOF'
#!/bin/sh
printf 'DOT-STUB %s\n' "$*"
EOF
  chmod +x "$TARGET/bin/dot"

  # The sandbox target looks cloned, so the script takes the pull branch; the
  # stub git makes that a no-op instead of a network call.
  printf '#!/bin/sh\nexit 0\n' >"$STUBS/git"
  chmod +x "$STUBS/git"

  # Downloader stubs keyed by $CURL_MODE: good serves a working stand-in
  # binary, garbage serves a file that cannot execute, fail simulates a
  # network/server error. Every requested URL is appended to $URL_LOG.
  make_downloader() { # $1 = command name (curl|wget), $2 = mode
    cat >"$STUBS/$1" <<EOF
#!/bin/sh
mode='$2'
out=""
prev=""
for a in "\$@"; do
  case "\$prev" in
    -o|-O|*-o|*-O|*-qO|*-Oq) out="\$a" ;;
  esac
  prev="\$a"
done
[ -n "\${URL_LOG:-}" ] && printf '%s\n' "\$*" >>"\$URL_LOG"
case "\$mode" in
  good)
    printf '#!/bin/sh\nprintf '"'"'TUI-STUB %%s\\n'"'"' "\$*"\n' >"\$out"
    ;;
  garbage)
    printf 'this is not a runnable program\n' >"\$out"
    ;;
  fail)
    exit 22
    ;;
esac
exit 0
EOF
    chmod +x "$STUBS/$1"
  }

  # Only meaningful on macOS — the download targets darwin assets.
  if [ "$(uname -s)" != "Darwin" ]; then
    skip "release-binary download targets darwin assets"
  fi

  # A PATH without any system downloader, so the wget branch is reachable.
  make_no_curl_path() {
    local d="$SANDBOX/nodownloader" tool src
    mkdir -p "$d"
    for tool in sh bash env uname mktemp grep dirname cat chmod rm sed awk; do
      src="$(command -v "$tool" 2>/dev/null)" && ln -sf "$src" "$d/$tool"
    done
    NO_CURL_PATH="$STUBS:$d"
  }
}

teardown() {
  rm -rf "$SANDBOX"
}

run_bootstrap() { # arguments become the script's "$@"
  run env PATH="$STUBS:/usr/bin:/bin" DOTFILES_DIR="$TARGET" URL_LOG="$URL_LOG" \
    bash "$SCRIPT" "$@"
}

@test "bootstrap downloads the matching release binary and continues to install" {
  case "$(uname -m)" in
    arm64) asset="dot-tui-darwin-arm64" ;;
    x86_64) asset="dot-tui-darwin-amd64" ;;
    *) skip "unsupported arch: $(uname -m)" ;;
  esac
  make_downloader curl good
  run_bootstrap
  [ "$status" -eq 0 ]
  grep -q "releases/latest/download/$asset" "$URL_LOG"
  [ -x "$TARGET/bin/dot-tui" ]
  [[ "$output" == *"DOT-STUB install"* ]]
}

@test "the same download works over wget when curl is absent" {
  make_downloader wget good
  make_no_curl_path
  run env PATH="$NO_CURL_PATH" DOTFILES_DIR="$TARGET" URL_LOG="$URL_LOG" \
    bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "dot-tui-darwin-" "$URL_LOG"
  [ -x "$TARGET/bin/dot-tui" ]
  [[ "$output" == *"DOT-STUB install"* ]]
}

@test "a failed download does not abort bootstrap" {
  make_downloader curl fail
  run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -e "$TARGET/bin/dot-tui" ]
  [[ "$output" == *"DOT-STUB install"* ]]
}

@test "a downloaded binary that cannot execute is dropped and bootstrap continues" {
  make_downloader curl garbage
  run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -e "$TARGET/bin/dot-tui" ]
  [[ "$output" == *"DOT-STUB install"* ]]
}

@test "an existing dot-tui is kept and never re-downloaded" {
  printf '#!/bin/sh\nprintf '"'"'existing\\n'"'"'\n' >"$TARGET/bin/dot-tui"
  chmod +x "$TARGET/bin/dot-tui"
  make_downloader curl fail # would fail loudly if contacted
  run_bootstrap
  [ "$status" -eq 0 ]
  [ ! -f "$URL_LOG" ]
  grep -q existing "$TARGET/bin/dot-tui"
  [[ "$output" == *"DOT-STUB install"* ]]
}
