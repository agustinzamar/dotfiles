package workflow

import (
	"os/exec"
	"strings"
)

func SignedCommits(p Prompt, r CommandRunner) (Result, error) {
	method, err := p.Choose("Signed commits method", []string{"SSH", "GPG"})
	if err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
	}
	if method == "" {
		return Result{Outcome: OutcomePending, Reason: "signed commits not configured"}, nil
	}

	if method == "SSH" {
		return configureSSHSigning(p, r)
	}
	return configureGPGSigning(p, r)
}

func configureSSHSigning(p Prompt, r CommandRunner) (Result, error) {
	out, _ := r.Run("bash", "-c", "ls ~/.ssh/*.pub 2>/dev/null || true")
	keys := []string{}
	if out != "" {
		for _, line := range strings.Split(out, "\n") {
			line = strings.TrimSpace(line)
			if line != "" {
				keys = append(keys, line)
			}
		}
	}

	var keyPath string
	if len(keys) > 0 {
		choice, err := p.Choose("Select SSH key", keys)
		if err != nil {
			return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
		}
		keyPath = choice
	}

	if keyPath == "" {
		ok, err := p.Confirm("Generate new ed25519 SSH key?", true)
		if err != nil {
			return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
		}
		if !ok {
			return Result{Outcome: OutcomePending, Reason: "ssh key not provided"}, nil
		}

		path, err := p.Input("Key path", "~/.ssh/id_ed25519")
		if err != nil {
			return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
		}
		if path == "" {
			return Result{Outcome: OutcomePending, Reason: "ssh key path empty"}, nil
		}
		cmd := exec.Command("ssh-keygen", "-t", "ed25519", "-f", strings.Replace(path, "~", homeDir(), 1), "-N", "")
		return Result{Outcome: OutcomePending, Reason: "SSH key generation required", Interactive: cmd}, nil
	}

	if _, err := r.Run("git", "config", "--global", "gpg.format", "ssh"); err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "gpg.format ssh failed"}, err
	}
	if _, err := r.Run("git", "config", "--global", "user.signingkey", keyPath); err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "user.signingkey failed"}, err
	}
	if _, err := r.Run("git", "config", "--global", "commit.gpgsign", "true"); err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "commit.gpgsign failed"}, err
	}
	return Result{Outcome: OutcomeComplete, Reason: "SSH signing configured for " + keyPath}, nil
}

func homeDir() string {
	return "~"
}

func configureGPGSigning(p Prompt, r CommandRunner) (Result, error) {
	out, _ := r.Run("gpg", "--list-secret-keys", "--with-colons")
	if out == "" {
		ok, err := p.Confirm("Generate new GPG key?", true)
		if err != nil {
			return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
		}
		if !ok {
			return Result{Outcome: OutcomePending, Reason: "GPG key not generated"}, nil
		}
		cmd := exec.Command("gpg", "--full-generate-key")
		return Result{Outcome: OutcomePending, Reason: "GPG key generation required", Interactive: cmd}, nil
	}

	keys := extractGPGKeyIDs(out)
	if len(keys) == 0 {
		return Result{Outcome: OutcomePending, Reason: "no GPG secret keys found"}, nil
	}

	choice, err := p.Choose("Select GPG key", keys)
	if err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "prompt failed"}, err
	}
	if choice == "" {
		return Result{Outcome: OutcomePending, Reason: "GPG key not selected"}, nil
	}

	if _, err := r.Run("git", "config", "--global", "user.signingkey", choice); err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "user.signingkey failed"}, err
	}
	if _, err := r.Run("git", "config", "--global", "commit.gpgsign", "true"); err != nil {
		return Result{Outcome: OutcomeFailed, Reason: "commit.gpgsign failed"}, err
	}
	return Result{Outcome: OutcomeComplete, Reason: "GPG signing configured for " + choice}, nil
}

func extractGPGKeyIDs(out string) []string {
	ids := []string{}
	seen := map[string]bool{}
	for _, line := range strings.Split(out, "\n") {
		parts := strings.Split(line, ":")
		if len(parts) > 0 && parts[0] == "sec" && len(parts) > 4 {
			id := parts[4]
			if !seen[id] {
				ids = append(ids, id)
				seen[id] = true
			}
		}
	}
	return ids
}
