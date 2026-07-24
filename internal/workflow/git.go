package workflow

import (
	"strings"
)

func GitIdentity(p Prompt, r CommandRunner) (Result, error) {
	name, _ := r.Run("git", "config", "--global", "user.name")
	email, _ := r.Run("git", "config", "--global", "user.email")

	var missing []string
	if strings.TrimSpace(name) == "" {
		missing = append(missing, "name")
	}
	if strings.TrimSpace(email) == "" {
		missing = append(missing, "email")
	}
	if len(missing) == 0 {
		return Result{Outcome: OutcomeComplete, Reason: "git identity already set"}, nil
	}

	answers := make(map[string]string)
	for _, field := range missing {
		val, err := p.Input("Git "+field, "")
		if err != nil {
			return Result{Outcome: OutcomeFailed, Reason: "prompt failed for " + field}, err
		}
		answers[field] = val
	}

	confirmed, err := p.Confirm("Write git config globally?", true)
	if err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
	}
	if !confirmed {
		return Result{Outcome: OutcomePending, Reason: "git identity not configured"}, nil
	}

	for field, val := range answers {
		key := "user." + field
		if _, err := r.Run("git", "config", "--global", key, val); err != nil {
			return Result{Outcome: OutcomeFailed, Reason: "git config failed for " + key}, err
		}
	}
	return Result{Outcome: OutcomeComplete, Reason: "git identity configured"}, nil
}
