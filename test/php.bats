#!/usr/bin/env bats

# install/php.sh builds the extensions Homebrew's php leaves out (redis,
# imagick). A stub Homebrew, a stub php and a stub pecl keep these tests off the
# real machine's PHP: nothing here compiles or installs anything.

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  export REPO_ROOT
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dot-php.XXXXXX")"
  STUB_BIN="$TEST_ROOT/bin"
  PECL_LOG="$TEST_ROOT/pecl.log"
  mkdir -p "$STUB_BIN"
  export TEST_ROOT STUB_BIN PECL_LOG
  # One formula name per line, as the stub `brew list --formula` prints them.
  export BREW_PHP_FORMULAE=""

  # Reports only the formulae the test declared, and a prefix per formula.
  cat >"$STUB_BIN/brew" <<'EOF'
#!/usr/bin/env bash
case "$1" in
list) printf '%s\n' "${BREW_PHP_FORMULAE:-}" | grep -v '^$' || true ;;
--prefix) printf '%s\n' "$TEST_ROOT/prefix-$2" ;;
esac
EOF
  chmod +x "$STUB_BIN/brew"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

# provide_php <formula> <space-separated modules the stub php reports>
provide_php() {
  local formula=$1 modules=$2
  local dir="$TEST_ROOT/prefix-$formula/bin"
  mkdir -p "$dir"
  cat >"$dir/php" <<EOF
#!/usr/bin/env bash
printf '%s\n' $modules
EOF
  # The pecl stub records the call and whether it received stdin: pecl prompts
  # for optional features there, so a caller that forgets the answers pipe would
  # hang a real build instead of failing it.
  cat >"$dir/pecl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$PECL_LOG"
if read -r _; then
  printf 'stdin: yes\n' >>"$PECL_LOG"
else
  printf 'stdin: no\n' >>"$PECL_LOG"
fi
exit 0
EOF
  chmod +x "$dir/php" "$dir/pecl"
}

# Mirrors bin/dot's own shell options. `pipefail` is load-bearing here: the
# loaded-module check used to be a `php -m | grep -q` pipeline, which pipefail
# turns into a failure (grep exits early, php -m gets SIGPIPE), so this harness
# would not have caught an extension being rebuilt on every run.
run_phase() {
  run env DOTFILES_DIR="$REPO_ROOT" DRY_RUN="${DRY_RUN:-false}" \
    PATH="$STUB_BIN:$PATH" \
    bash -c 'set -Eeuo pipefail; . "$REPO_ROOT/install/common.sh"; . "$REPO_ROOT/install/php.sh"; install_php_extensions'
}

@test "no Homebrew PHP installed: skips without calling pecl" {
  run_phase

  [ "$status" -eq 0 ]
  [[ "$output" == *"no Homebrew PHP formula"* ]]
  [ ! -f "$PECL_LOG" ]
}

@test "an extension already loaded is not rebuilt" {
  provide_php "php@8.5" "redis imagick zip"
  export BREW_PHP_FORMULAE="php@8.5"

  run_phase

  [ "$status" -eq 0 ]
  [[ "$output" == *"php@8.5: redis already loaded"* ]]
  [[ "$output" == *"php@8.5: imagick already loaded"* ]]
  [ ! -f "$PECL_LOG" ]
}

@test "a missing extension is installed for the version that lacks it" {
  provide_php "php@8.5" "zip"
  export BREW_PHP_FORMULAE="php@8.5"

  run_phase

  [ "$status" -eq 0 ]
  grep -q 'install -f redis' "$PECL_LOG"
  grep -q 'install -f imagick' "$PECL_LOG"
  # Empty answers must reach pecl, or a real build waits on a prompt forever.
  [ "$(grep -c 'stdin: yes' "$PECL_LOG")" -eq 2 ]
}

@test "each version is handled on its own" {
  provide_php "php@8.2" "zip"
  provide_php "php@8.5" "redis imagick"
  export BREW_PHP_FORMULAE="php@8.2
php@8.5"

  run_phase

  [ "$status" -eq 0 ]
  [ "$(grep -c 'install -f' "$PECL_LOG")" -eq 2 ]
  [[ "$output" == *"php@8.5: redis already loaded"* ]]
}

@test "dry run prints the installs and installs nothing" {
  provide_php "php@8.5" "zip"
  export BREW_PHP_FORMULAE="php@8.5"
  export DRY_RUN=true

  run_phase

  [ "$status" -eq 0 ]
  [[ "$output" == *"pecl install -f redis for php@8.5"* ]]
  [ ! -f "$PECL_LOG" ]
}

@test "a failing build is reported and fails the phase" {
  provide_php "php@8.5" "zip"
  export BREW_PHP_FORMULAE="php@8.5"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$TEST_ROOT/prefix-php@8.5/bin/pecl"
  chmod +x "$TEST_ROOT/prefix-php@8.5/bin/pecl"

  run_phase

  [ "$status" -ne 0 ]
  [[ "$output" == *"PHP extensions failed: php@8.5:redis"* ]]
}
