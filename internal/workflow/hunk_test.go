package workflow

import (
	"errors"
	"strings"
	"testing"
)

type lookPathFailRunner struct{}

func (lookPathFailRunner) Run(name string, args ...string) (string, error) { return "", nil }
func (lookPathFailRunner) LookPath(name string) (string, error) { return "", errors.New("not found") }

func TestHunkPagerRefusesWhenHunkIsUnavailable(t *testing.T) {
	runner := lookPathFailRunner{}
	prompt := newFakePrompt(nil, nil)
	result, err := HunkGitPager(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeFailed {
		t.Fatalf("expected failed, got %s", result.Outcome)
	}
}

func TestHunkPagerConfiguresOnlyAfterAcceptance(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"git config --global core.pager": "",
		},
	}
	prompt := newFakePrompt(nil, []bool{true})
	result, err := HunkGitPager(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
	if !strings.Contains(result.Reason, "Hunk configured") {
		t.Fatalf("expected Hunk configured reason, got %s", result.Reason)
	}
}

func TestHunkConfigAndPagerAreSeparateLeaves(t *testing.T) {
	if !IsHunkAvailable(&fakeRunner{}) {
		return
	}
	if r, _ := WriteHunkPager(&fakeRunner{}); r.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", r.Outcome)
	}
}
