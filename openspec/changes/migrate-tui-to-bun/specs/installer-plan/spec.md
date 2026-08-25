# Installer Plan Specification

## Purpose

Define how the installer turns a loaded profile plus a detected environment into an
ordered task list and skip list, without executing anything. Planning is pure: it MUST
depend only on the profile selection, the applied set, and environment detection
results.

## Requirements

### Requirement: Environment Detection

The planner SHALL detect tool availability by resolving each command name
(`brew`, `xcode-select`, `git`, `gh`, `code`, `php`, `composer`, `opencode`) on `PATH`,
equivalent to Go's `exec.LookPath`. Detection MUST record a boolean per command name
and MUST NOT execute the commands.

#### Scenario: Detection reports presence without running tools

- GIVEN an environment where `brew` resolves on PATH and `gh` does not
- WHEN the environment is detected
- THEN the detection result maps `brew` to true and `gh` to false
- AND no side effects from running brew or gh occur

### Requirement: Dependency-Ordered Task Planning (DFS)

Planning MUST emit tasks only for components that are enabled in the profile AND not in
the applied set. Selected components MUST be emitted in dependency order via depth-first
traversal over manifest order: each selected component's dependencies are visited before
the component itself, each component is added at most once, and components are never
added twice. Every planned task MUST carry its component's id, label, operation
(the command string), and dependencies.

#### Scenario: Selected components planned in DFS dependency order

- GIVEN a profile enabling component X whose dependencies include component D,
  with neither applied
- WHEN the plan is built
- THEN all of D's tasks appear before all of X's tasks
- AND every task carries its own component id, label, command, and dependency list

#### Scenario: Each selected component appears once despite shared dependencies

- GIVEN two selected components X and Y that both depend on D
- WHEN the plan is built
- THEN D's tasks appear exactly once, before both X's and Y's tasks

#### Scenario: Unselected components produce no tasks

- GIVEN a profile where some component is false
- WHEN the plan is built
- THEN no task references the unselected component id

### Requirement: Applied Components Produce No Tasks

Components present in the applied set MUST be excluded from planning even when enabled
in the profile.

#### Scenario: Applied component skipped during planning

- GIVEN a profile enabling `ai` and an applied set containing `ai`
- WHEN the plan is built
- THEN no task has component id `ai`

### Requirement: xcode-select Skip Rule

The exact command `xcode-select --install` MUST be omitted from the plan whenever
`xcode-select` is detected on PATH. Other commands of the same component MUST still be
planned. When `xcode-select` is absent, the command MUST be planned normally.

#### Scenario: Command skipped when xcode-select already installed

- GIVEN the plan includes the `base` component and `xcode-select` is on PATH
- WHEN the plan is built
- THEN no task has operation exactly `xcode-select --install`
- AND the other `base` commands are still present as tasks

#### Scenario: Command kept when xcode-select missing

- GIVEN the plan includes the `base` component and `xcode-select` is not on PATH
- WHEN the plan is built
- THEN a task with operation `xcode-select --install` exists for `base`

### Requirement: Homebrew Skip Rule

Any command whose first token is `brew` (i.e. it begins with `brew` followed by a space) MUST be skipped, together with ALL remaining commands
of that component, whenever `brew` is not detected on PATH. Each such skip MUST be
reported as a skip entry carrying the component id and the exact reason string
"Homebrew is not installed".

#### Scenario: Brew-dependent component fully skipped without brew

- GIVEN a selected component whose first command is a brew-prefixed command
  and `brew` is absent from PATH
- WHEN the plan is built
- THEN no task of that component exists
- AND one skip entry names that component id with reason "Homebrew is not installed"

#### Scenario: Brew commands planned normally when brew present

- GIVEN the same component selection but `brew` present on PATH
- WHEN the plan is built
- THEN the component's commands all become tasks and no skip entry is produced
