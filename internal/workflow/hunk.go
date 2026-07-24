package workflow

import (
	"strings"
)

func HunkGitPager(p Prompt, r CommandRunner) (Result, error) {
	_, err := r.LookPath("hunk")
	if err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "hunk is not installed"}, nil
	}

	ok, err := p.Confirm("Use Hunk as Git pager?", true)
	if err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
	}
	if !ok {
		return Result{Outcome: OutcomePending, Reason: "Hunk pager not configured"}, nil
	}

	if _, err := r.Run("git", "config", "--global", "core.pager", "hunk pager"); err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "core.pager failed"}, err
	}
	return Result{Outcome: OutcomeComplete, Reason: "Hunk configured as Git pager"}, nil
}

func IsHunkAvailable(r CommandRunner) bool {
	_, err := r.LookPath("hunk")
	return err == nil
}

func WriteHunkPager(r CommandRunner) (Result, error) {
	_, err := r.Run("git", "config", "--global", "core.pager", "hunk pager")
	if err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "core.pager failed"}, err
	}
	return Result{Outcome: OutcomeComplete, Reason: "Hunk configured as Git pager"}, nil
}

func ParseSigningKeyID(val string) string {
	val = strings.TrimSpace(val)
	if val == "" {
		return ""
	}
	return val
}
