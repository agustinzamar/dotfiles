#!/usr/bin/env bats

load box

setup() {
  box_setup
  REPO="$SCRATCH/repositories/example repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgsign=false commit --allow-empty -qm initial
  stub rex 'printf "%s\n" "$@" > "$HOME/rex-args"; exit "${REX_EXIT:-0}"'
  cd "$REPO"
}

teardown() {
  box_teardown
}

worktree_cli() {
  env -i HOME="$SCRATCH_HOME" PATH="$STUB_BIN:$REAL_BIN" \
    GIT_CONFIG_GLOBAL="$SCRATCH_HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    REX_EXIT="${REX_EXIT:-0}" "$DOTFILES_DIR/bin/rex-worktree" "$@"
}

@test "creates a new branch and opens its shared worktree in Rex from a subdirectory" {
  mkdir subdirectory
  cd subdirectory
  run worktree_cli feature/login
  [ "$status" -eq 0 ]
  destination="$SCRATCH_HOME/Worktrees/example repo/feature/login"
  [ -f "$destination/.git" ]
  [ "$(git -C "$destination" branch --show-current)" = feature/login ]
  [ "$(git -C "$destination" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse HEAD)" ]
  [ "$(cat "$SCRATCH_HOME/rex-args")" = "$(printf '%s\n' new 'example repo-feature/login' -c "$destination")" ]
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "uses the original repository name when called from a linked worktree" {
  git worktree add -qb other "$SCRATCH/other-checkout"
  cd "$SCRATCH/other-checkout"
  run worktree_cli next-feature
  [ "$status" -eq 0 ]
  [ -f "$SCRATCH_HOME/Worktrees/example repo/next-feature/.git" ]
}

@test "help succeeds without creating a worktree or Rex session" {
  run worktree_cli --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: rex-worktree <branch>"* ]]
  [ ! -e "$SCRATCH_HOME/Worktrees" ]
  [ ! -e "$SCRATCH_HOME/rex-args" ]
}

@test "rejects missing arguments, extra arguments, and invalid branch names without mutation" {
  before="$(git show-ref)"
  for args in '' '--unknown' '../escape'; do
    run worktree_cli $args
    [ "$status" -ne 0 ]
  done
  run worktree_cli feature extra
  [ "$status" -ne 0 ]
  [ "$(git show-ref)" = "$before" ]
  [ ! -e "$SCRATCH_HOME/Worktrees" ]
  [ ! -e "$SCRATCH_HOME/rex-args" ]
}

@test "rejects execution outside a Git repository" {
  cd "$SCRATCH_HOME"
  run worktree_cli feature
  [ "$status" -ne 0 ]
  [ ! -e "$SCRATCH_HOME/Worktrees" ]
  [ ! -e "$SCRATCH_HOME/rex-args" ]
}

@test "checks Rex availability before creating a branch or worktree" {
  rm "$STUB_BIN/rex"
  run worktree_cli feature
  [ "$status" -ne 0 ]
  [[ "$output" == *"rex is required"* ]]
  [ ! -e "$SCRATCH_HOME/Worktrees" ]
  ! git show-ref --verify --quiet refs/heads/feature
}

@test "Git failure does not open Rex or overwrite an existing destination" {
  git branch existing
  run worktree_cli existing
  [ "$status" -ne 0 ]
  [ ! -e "$SCRATCH_HOME/rex-args" ]
  destination="$SCRATCH_HOME/Worktrees/example repo/collision"
  mkdir -p "$destination"
  printf 'keep\n' >"$destination/marker"
  run worktree_cli collision
  [ "$status" -ne 0 ]
  [ "$(cat "$destination/marker")" = keep ]
  [ ! -e "$SCRATCH_HOME/rex-args" ]
  ! git show-ref --verify --quiet refs/heads/collision
}

@test "Rex failure preserves the new worktree and returns its exit status" {
  REX_EXIT=7
  run worktree_cli feature
  [ "$status" -eq 7 ]
  [ -f "$SCRATCH_HOME/Worktrees/example repo/feature/.git" ]
  git show-ref --verify --quiet refs/heads/feature
  [[ "$output" == *"Worktree kept at"* ]]
}
