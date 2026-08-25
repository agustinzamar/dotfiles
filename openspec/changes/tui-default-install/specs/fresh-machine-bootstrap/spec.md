# fresh-machine-bootstrap Specification

## Purpose

Define the bootstrap behavior that keeps the interactive `dot install` working
on a brand-new Mac where no TUI runtime exists yet: runtime provisioning after
Homebrew bootstrap, headless flag pass-through from `remote-install.sh`, and
loud failure when the TUI cannot launch.

## Requirements

### Requirement: Bare install bootstraps the TUI runtime first

On a machine missing the TUI runtime (bun), bare `dot install` MUST provision
it before launching the TUI, after Homebrew itself is bootstrapped. The
runtime bootstrap step MUST NOT be skipped silently.

#### Scenario: Fresh Mac with only Xcode CLT tooling

- GIVEN a new Mac with no bun installed but Xcode CLT/git/curl present
- WHEN the user runs bare `dot install`
- THEN Homebrew is bootstrapped if needed, bun is brew-installed if missing, and the TUI then launches

#### Scenario: Runtime already present skips re-bootstrap

- GIVEN bun is already executable on PATH
- WHEN bare `dot install` runs
- THEN the runtime bootstrap step is a no-op and the TUI launches directly

### Requirement: remote-install.sh passes through headless flags

`remote-install.sh` MUST pass through `--all` and `--profile <name>` (and other
arguments it forwards via `"$@"`) so scripted fresh-machine setups reach the
headless paths instead of the TUI.

#### Scenario: CI script requests headless install

- GIVEN a fresh machine running the remote installer over SSH without a TTY
- WHEN the script is invoked with `--all` (or `--profile <name>`)
- THEN `bin/dot install` receives the same flags and completes headlessly

### Requirement: Unlaunchable TUI fails loudly

If the TUI cannot launch (runtime bootstrap failed or stdin is not a TTY),
bare `dot install` MUST fail loudly with guidance to the headless flags. It
MUST NOT hang, fall back to the old baseline silently, or exit zero.

#### Scenario: Runtime bootstrap fails

- GIVEN bun cannot be installed (e.g. brew failure) and stdin is not interactive
- WHEN bare `dot install` runs
- THEN it exits non-zero with an error naming the headless alternatives
