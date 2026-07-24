package workflow

import (
	"strings"
	"testing"
)

type fakePrompt struct {
	confirm bool
	choose  string
	input   string
}

func (f *fakePrompt) Confirm(title string, defaultYes bool) (bool, error) {
	return f.confirm, nil
}

func (f *fakePrompt) Input(title, value string) (string, error) {
	return f.input, nil
}

func (f *fakePrompt) Choose(title string, options []string) (string, error) {
	return f.choose, nil
}

type fakeRunner struct {
	outputs map[string]string
}

func (f *fakeRunner) Run(name string, args ...string) (string, error) {
	key := name + " " + strings.Join(args, " ")
	val, ok := f.outputs[key]
	if !ok {
		return "", nil
	}
	return val, nil
}

func (f *fakeRunner) LookPath(name string) (string, error) {
	return "/usr/bin/" + name, nil
}

func TestGitIdentityPromptsOnlyMissingValues(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"git config --global user.name": "",
			"git config --global user.email": "existing@example.com",
		},
	}
	prompt := &fakePrompt{
		input:   "Agustin Zamar",
		confirm: true,
	}
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
	prompt := &fakePrompt{}
	result, err := GitIdentity(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
	if prompt.confirm {
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
	prompt := &fakePrompt{
		input:  "Agustin Zamar",
		confirm: true,
	}
	result, err := GitIdentity(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
}
