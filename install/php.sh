#!/usr/bin/env bash
# PHP extensions. Sourced directly by bin/dot.
#
# Homebrew's php formulae ship a base extension set, and neither redis nor
# imagick is in it. A Brewfile cannot express `pecl install`, and there is no
# formula for one extension built against Homebrew's php, so this phase builds
# the missing ones with pecl. The test is the loaded module list, which is what
# makes a second run a no-op.

# Extensions every PHP version on this machine should have.
_php_extensions=(redis imagick)

# Homebrew PHP formula names installed here, one per line.
_php_formulae_installed() {
  brew list --formula 2>/dev/null | grep -E '^php(@[0-9.]+)?$' || true
}

# pecl reads the answers for its optional features from stdin, so empty lines
# take the defaults (no extra serializer, no compression). A function rather
# than a pipeline so run_step can execute it directly.
_php_pecl_install() {
  local pecl_bin=$1 extension=$2
  printf '\n\n\n\n\n' | "$pecl_bin" install -f "$extension"
}

# Build every missing extension for every Homebrew PHP on this machine. A
# machine that already has them costs nothing: nothing is installed and no
# compile runs.
install_php_extensions() {
  local formula prefix php_bin pecl_bin extension failures=()

  if ! is_executable brew; then
    echo '✅ Skipping PHP extensions (Homebrew is not installed)'
    return 0
  fi

  local formulae
  formulae=$(_php_formulae_installed)
  if [[ -z "$formulae" ]]; then
    echo '✅ Skipping PHP extensions (no Homebrew PHP formula installed)'
    return 0
  fi

  while IFS= read -r formula; do
    prefix=$(brew --prefix "$formula" 2>/dev/null) || continue
    php_bin="$prefix/bin/php"
    pecl_bin="$prefix/bin/pecl"
    [[ -x "$php_bin" && -x "$pecl_bin" ]] || continue

    local modules
    if ! modules=$("$php_bin" -m 2>/dev/null); then
      printf '❌ %s: could not list its loaded modules\n' "$formula" >&2
      failures+=("$formula:modules")
      continue
    fi

    for extension in "${_php_extensions[@]}"; do
      # A here-string, never a pipe: `grep -q` exits the moment it matches, and
      # under bin/dot's `set -o pipefail` the SIGPIPE that gives `php -m` would
      # make a module that IS loaded look absent, rebuilding it every run.
      if grep -qix "$extension" <<<"$modules"; then
        echo "✅ $formula: $extension already loaded"
        continue
      fi
      # pecl reads the answers for its optional features from stdin, so the call
      # goes through a helper. run_step cannot print that faithfully (it would
      # show the helper's name), so the dry run prints the pecl command itself.
      if "$DRY_RUN"; then
        printf '🔧 + pecl install -f %s for %s\n' "$extension" "$formula"
        continue
      fi

      # A build takes minutes, so it gets the progress reporting run_step gives
      # long steps; its output only matters when it fails.
      run_step "$formula $extension" installed _php_pecl_install "$pecl_bin" "$extension" ||
        failures+=("$formula:$extension")
    done
  done <<<"$formulae"

  if ((${#failures[@]})); then
    printf '\n❌ PHP extensions failed: %s\n' "${failures[*]}" >&2
    return 1
  fi

  return 0
}
