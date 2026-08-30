#!/usr/bin/env bash
# OS platform detection. Sourced, never executed.
#
# Deliberately separate from remote-install-server.sh's detect_pkg: that script
# runs as `curl | bash` with no checkout, so it cannot source this file, and it
# recognises five managers where this one is a closed set the repo can support.

# Cached: every platform-conditional branch calls os_family, and the answer
# cannot change inside a single run.
_OS_FAMILY=""

# macos|debian|arch|unknown on stdout. Always exits 0, so callers can branch on
# the token without guarding — an unrecognised host degrades, it does not abort.
os_family() {
  if [[ -n "${_OS_FAMILY:-}" ]]; then
    printf '%s\n' "$_OS_FAMILY"
    return 0
  fi

  local family=unknown
  case "$(uname -s 2>/dev/null || true)" in
    Darwin) family=macos ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        family=debian
      elif command -v pacman >/dev/null 2>&1; then
        # ASSUMPTION: unverified. No Arch host and no hosted Arch runner is
        # available, so this branch is exercised by a PATH stub only.
        family=arch
      fi
      ;;
  esac

  _OS_FAMILY=$family
  printf '%s\n' "$_OS_FAMILY"
}

# The package manager binary name, or nothing plus a non-zero status. Absence is
# reported explicitly: assuming Homebrew is what wrote `!/bin/gh` into the git
# config on hosts that never had it.
os_pkg_manager() {
  local pm
  for pm in brew apt-get pacman; do
    if command -v "$pm" >/dev/null 2>&1; then
      printf '%s\n' "$pm"
      return 0
    fi
  done
  return 1
}

# The name a tool is installed under on this OS family. Debian ships two of the
# tools this repo requires under different binary names; everywhere else, and
# for every other tool, this is the identity.
platform_binary() {
  local name=$1
  if [[ "$(os_family)" == debian ]]; then
    case "$name" in
      bat) name=batcat ;;
      fd) name=fdfind ;;
    esac
  fi
  printf '%s\n' "$name"
}
