# Installer Execute Specification

## Purpose

Define how the planned task list runs sequentially through a shell runner, how failures
block dependent work while independent work continues, and how per-task results roll up
into per-component outcomes for reporting.

## Requirements

### Requirement: Shell Command Runner

Each task operation MUST run through `sh -c <operation>` with `HOMEBREW_NO_AUTO_UPDATE`
and `HOMEBREW_NO_ENV_HINTS` set in the child environment, capturing combined stdout and
stderr as output. Execution MUST support cancellation: once cancellation is observed,
remaining tasks SHALL be recorded as skipped with reason "cancelled" rather than run.

#### Scenario: Task runs via sh and captures combined output

- GIVEN a task whose operation writes to both stdout and stderr
- WHEN the task executes through the shell runner
- THEN the runner invokes `sh -c` with the operation string
- AND the result output contains text from both streams
- AND the environment passed to the child includes
  `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_ENV_HINTS=1`

#### Scenario: Cancellation skips remaining tasks

- GIVEN an execution in progress when cancellation is requested
- WHEN the runner observes cancellation before a subsequent task
- THEN that task is recorded with status "skipped" and output "cancelled"
- AND its operation is never executed

### Requirement: Sequential Execution With Progress Callback

Execution MUST process tasks strictly sequentially in plan order. A progress callback,
when provided, MUST fire before each task's command runs (but not for tasks skipped due
to dependency failure or cancellation).

#### Scenario: Progress fires before each executed task

- GIVEN three executable tasks T1, T2, T3 and a progress callback
- WHEN execution completes
- THEN the callback fired exactly three times, once before each task ran
- AND no progress event fired for any skipped or failed-before-run task

### Requirement: Failure Blocks Dependents Only

A failed task MUST mark its component failed. Any later task whose dependencies include
a failed component MUST be skipped with status "skipped" and output "dependency failed".
Tasks without failed dependencies MUST still run even after unrelated failures.

#### Scenario: Dependent task skipped after dependency failure

- GIVEN component X depends on D, D's first task fails
- WHEN execution reaches X's tasks
- THEN X's tasks are recorded with status "skipped" and output "dependency failed"
- AND X's commands are never executed

#### Scenario: Independent components continue after failure

- GIVEN selected components D and Y with no dependency relationship, D fails first
- WHEN execution completes
- THEN Y's tasks were executed and reported their real outcome
- AND execution did not abort after D's failure

### Requirement: Per-Task Result Record

Every task MUST yield exactly one result carrying the task, a status of either
"installed" (command succeeded) or "failed" (non-zero exit), captured output, and start/
finish timestamps. A result MUST exist even for skipped tasks.

#### Scenario: Success and failure statuses

- GIVEN one task whose command exits 0 and one whose command exits non-zero
- WHEN both execute
- THEN the first result has status "installed"
- AND the second has status "failed", with its captured output preserved

### Requirement: Per-Component Result Summary

Results MUST be aggregated per component id preserving first-appearance order:
a single failed task makes the whole component "failed"; otherwise, if any task was
skipped, the component is "skipped" with that skip reason; only when every task ran and
succeeded is the component "installed". Failed aggregation SHALL collect all failed-task
output for the component, separating multiple outputs with newlines. Components with no
planned tasks produce no summary entry.

#### Scenario: One failed command fails the whole component

- GIVEN a component with two commands where the second fails
- WHEN results are summarized
- THEN the component reports status "failed"
- AND the summary output contains at least the failing command's captured output

#### Scenario: All tasks installed means component installed

- GIVEN a component whose every planned task succeeded
- WHEN results are summarized
- THEN the component reports status "installed"

#### Scenario: Skipped-only component reports skip reason

- GIVEN a component whose tasks were all skipped with "dependency failed"
- WHEN results are summarized
- THEN the component reports status "skipped" with output "dependency failed"

#### Scenario: Multiple failures concatenate outputs

- GIVEN two different components each with a failing command
- WHEN results are summarized
- THEN each component's summary carries its own failed output
- AND neither component's output contains the other's
