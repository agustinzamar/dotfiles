package workflow

import (
	"strings"
	"testing"
)

func TestGitHubAuthSkipsLoginWhenStatusSucceeds(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"gh auth status": "Logged in to github.com",
		},
	}
	prompt := newFakePrompt(nil, nil)
	result, err := GitHubAuth(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
}

func TestGitHubAuthReturnsInteractiveLoginWhenUnauthenticated(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"gh auth status": "You are not logged in",
		},
	}
	prompt := newFakePrompt(nil, []bool{true})
	result, err := GitHubAuth(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomePending {
		t.Fatalf("expected pending, got %s", result.Outcome)
	}
	if result.Interactive == nil {
		t.Fatal("expected interactive command when not authenticated")
	}
	if !strings.Contains(result.Interactive.String(), "gh auth login") {
		t.Fatalf("expected gh auth login command, got %s", result.Interactive.String())
	}
}

func TestGitHubAuthRunsSetupGitOnlyAfterVerifiedLogin(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"gh auth status":   "Logged in to github.com",
			"gh auth setup-git": "Git credentials configured",
		},
	}
	prompt := newFakePrompt(nil, []bool{true})
	result, err := GitHubAuth(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
	if !strings.Contains(result.Reason, "credential helper") {
		t.Fatalf("expected setup-git success, got %s", result.Reason)
	}
}

func TestGitHubAuthNeverIncludesCommandOutputInResult(t *testing.T) {
	runner := &fakeRunner{
		outputs: map[string]string{
			"gh auth status": "Logged in to github.com",
		},
	}
	prompt := newFakePrompt(nil, nil)
	result, err := GitHubAuth(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Contains(result.Reason, "Logged in") {
		t.Fatalf("reason should not include gh output: %s", result.Reason)
	}
}
