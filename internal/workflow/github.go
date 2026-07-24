package workflow

import (
	"os/exec"
	"strings"
)

func GitHubAuth(p Prompt, r CommandRunner) (Result, error) {
	ghOut, ghErr := r.Run("gh", "auth", "status")
	if ghErr == nil && strings.Contains(ghOut, "Logged in") {
		ok, err := p.Confirm("Configure Git credential helper?", true)
		if err != nil {
			return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
		}
		if ok {
			if out, err := r.Run("gh", "auth", "setup-git"); err != nil {
				return Result{Outcome: OutcomeFailed, Reason: "gh auth setup-git failed: " + out}, err
			}
			return Result{Outcome: OutcomeComplete, Reason: "GitHub credential helper configured"}, nil
		}
		return Result{Outcome: OutcomeComplete, Reason: "GitHub already authenticated"}, nil
	}

	ok, err := p.Confirm("Authenticate with GitHub?", true)
	if err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
	}
	if !ok {
		return Result{Outcome: OutcomePending, Reason: "GitHub authentication skipped"}, nil
	}

	cmd := exec.Command("gh", "auth", "login")
	return Result{Outcome: OutcomePending, Reason: "GitHub authentication required", Interactive: cmd}, nil
}
