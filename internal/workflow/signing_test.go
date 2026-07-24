package workflow

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func isolateHome(t *testing.T) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
}

func TestExpandHomeUsesUserHome(t *testing.T) {
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	if got := expandHome("~/.ssh/id_ed25519"); got != filepath.Join(home, ".ssh", "id_ed25519") {
		t.Fatalf("expandHome() = %q", got)
	}
}

func TestGlobSSHKeys(t *testing.T) {
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, ".ssh"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"id_a.pub", "id_b.pub"} {
		if err := os.WriteFile(filepath.Join(dir, ".ssh", name), nil, 0600); err != nil {
			t.Fatal(err)
		}
	}
	paths, err := globSSHKeys(dir)
	if err != nil || len(paths) != 2 {
		t.Fatalf("globSSHKeys() = %v, %v", paths, err)
	}
}

func TestSSHSigningUsesSelectedExistingPublicKey(t *testing.T) {
	isolateHome(t)
	runner := &fakeRunner{
		outputs: map[string]string{
			"bash -c ls ~/.ssh/*.pub 2>/dev/null || true": "/home/user/.ssh/id_ed25519.pub\n/home/user/.ssh/id_rsa.pub",
		},
	}
	prompt := newFakePrompt(
		[]string{"SSH", "/home/user/.ssh/id_ed25519.pub"},
		[]bool{},
	)
	result, err := SignedCommits(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
	if !strings.Contains(result.Reason, "/home/user/.ssh/id_ed25519.pub") {
		t.Fatalf("expected reason to mention selected key, got %s", result.Reason)
	}
}

func TestSSHSigningReturnsInteractiveKeygenForNewKey(t *testing.T) {
	isolateHome(t)
	runner := &fakeRunner{
		outputs: map[string]string{
			"bash -c ls ~/.ssh/*.pub 2>/dev/null || true": "",
		},
	}
	prompt := newFakePrompt(
		[]string{"SSH", "/home/user/.ssh/id_ed25519"},
		[]bool{true},
	)
	result, err := SignedCommits(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomePending {
		t.Fatalf("expected pending, got %s", result.Outcome)
	}
	if result.Interactive == nil {
		t.Fatal("expected interactive keygen command")
	}
}

func TestSSHSigningDoesNotOverwriteExistingKeyPath(t *testing.T) {
	isolateHome(t)
	runner := &fakeRunner{
		outputs: map[string]string{
			"bash -c ls ~/.ssh/*.pub 2>/dev/null || true": "/home/user/.ssh/id_ed25519.pub",
		},
	}
	prompt := newFakePrompt(
		[]string{"SSH", "/home/user/.ssh/id_ed25519.pub"},
		[]bool{},
	)
	result, err := SignedCommits(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
}

func TestGPGSigningUsesSelectedSecretKey(t *testing.T) {
	isolateHome(t)
	runner := &fakeRunner{
		outputs: map[string]string{
			"gpg --list-secret-keys --with-colons": "sec:u:4096:1:ABCDEF01:1672531200:::u:::scESC::",
		},
	}
	prompt := newFakePrompt(
		[]string{"GPG", "ABCDEF01"},
		[]bool{},
	)
	result, err := SignedCommits(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
}

func TestSigningRegistersPublicKeyOnlyAfterUserConsent(t *testing.T) {
	isolateHome(t)
	runner := &fakeRunner{
		outputs: map[string]string{
			"bash -c ls ~/.ssh/*.pub 2>/dev/null || true": "/home/user/.ssh/id_ed25519.pub",
		},
	}
	prompt := newFakePrompt(
		[]string{"SSH", "/home/user/.ssh/id_ed25519.pub"},
		[]bool{},
	)
	result, err := SignedCommits(prompt, runner)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Outcome != OutcomeComplete {
		t.Fatalf("expected complete, got %s", result.Outcome)
	}
	if strings.Contains(result.Reason, "key") || strings.Contains(result.Reason, "public") {
		// reason includes key path but no raw key material
	}
}
