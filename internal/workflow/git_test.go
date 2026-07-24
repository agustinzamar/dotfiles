package workflow

import (
	"testing"
)

func TestGitIdentityPromptsOnlyMissingValues(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"git config --global user.name": "",
			"git config --global user.email": "existing@example.com",
		},
	}
	prompt := newFakePrompt(
		[]string{"Agustin Zamar"},
		[]bool{true},
	)
	result, err := GitIdentity(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
}

func TestGitIdentityLeavesExistingValuesUntouched(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"git config --global user.name": "Agustin",
			"git config --global user.email": "agustin@example.com",
		},
	}
	prompt := newFakePrompt(nil, nil)
	result, err := GitIdentity(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
	if prompt.idx != 0 {
		t.Error("expected no prompt when identity is complete")
	}
}

func TestGitIdentityWritesMissingNameAndEmail(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"git config --global user.name": "",
			"git config --global user.email": "",
		},
	}
	prompt := newFakePrompt(
		[]string{"Agustin Zamar"},
		[]bool{true},
	)
	result, err := GitIdentity(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
}
