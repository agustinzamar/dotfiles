package installer

import (
	"testing"

	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/manifest"
)

type fakeStepRunner struct {
	results []executor.Result
}

func (f *fakeStepRunner) Run(step manifest.Step, dotfilesDir string, vars map[string]string, dryRun bool) executor.Result {
	r := f.results[0]
	f.results = f.results[1:]
	return r
}

func plannerWithNode(id, name string, step manifest.Step) *Planner {
	m := &manifest.Manifest{
		Categories: []manifest.Category{
			{
				ID:   "test",
				Name: "Test",
				Nodes: []manifest.Node{
					{ID: id, Name: name, Steps: []manifest.Step{step}},
				},
			},
		},
	}
	return NewPlanner(m, "")
}

func TestSessionExecutesAcceptedNodeImmediately(t *testing.T) {
	p := plannerWithNode("node", "Node", manifest.Step{Type: "run", Command: "echo hi"})
	_ = p.Next()
	p.Answer("node", DecisionYes)
	runner := &fakeStepRunner{
		results: []executor.Result{{Status: "installed", Msg: "ok"}},
	}
	lockPath := t.TempDir() + "/.lock"
	s := NewSession(p, runner, "/tmp", nil, false, lockPath)
	result := s.Execute("node")
	s.Close()
	if result.Status != StatusInstalled {
		t.Fatalf("expected installed, got %s", result.Status)
	}
	if p.byID["node"].Status != StatusInstalled {
		t.Fatalf("expected planner node marked installed, got %s", p.byID["node"].Status)
	}
}

func TestSessionMapsSkippedToAlreadyPresent(t *testing.T) {
	p := plannerWithNode("node", "Node", manifest.Step{Type: "run", Command: "echo hi"})
	_ = p.Next()
	p.Answer("node", DecisionYes)
	runner := &fakeStepRunner{
		results: []executor.Result{{Status: "skipped", Msg: "already"}},
	}
	lockPath := t.TempDir() + "/.lock"
	s := NewSession(p, runner, "/tmp", nil, false, lockPath)
	result := s.Execute("node")
	s.Close()
	if result.Status != StatusAlreadyPresent {
		t.Fatalf("expected already-present, got %s", result.Status)
	}
}

func TestSessionRecordsStepFailureWithoutExecutingNextNode(t *testing.T) {
	p := plannerWithNode("node", "Node", manifest.Step{Type: "run", Command: "echo hi"})
	_ = p.Next()
	p.Answer("node", DecisionYes)
	runner := &fakeStepRunner{
		results: []executor.Result{{Status: "error", Msg: "boom"}},
	}
	lockPath := t.TempDir() + "/.lock"
	s := NewSession(p, runner, "/tmp", nil, false, lockPath)
	result := s.Execute("node")
	s.Close()
	if result.Status != StatusFailed {
		t.Fatalf("expected failed, got %s", result.Status)
	}
}

func TestSessionDryRunUsesWouldInstall(t *testing.T) {
	p := plannerWithNode("node", "Node", manifest.Step{Type: "run", Command: "echo hi"})
	_ = p.Next()
	p.Answer("node", DecisionYes)
	runner := &fakeStepRunner{
		results: []executor.Result{{Status: "would-install", Msg: "would"}},
	}
	lockPath := t.TempDir() + "/.lock"
	s := NewSession(p, runner, "/tmp", nil, true, lockPath)
	result := s.Execute("node")
	s.Close()
	if result.Status != StatusWouldInstall {
		t.Fatalf("expected would-install, got %s", result.Status)
	}
}

func TestSessionAcquiresAndReleasesOneLock(t *testing.T) {
	p := plannerWithNode("node", "Node", manifest.Step{Type: "run", Command: "echo hi"})
	runner := &fakeStepRunner{
		results: []executor.Result{{Status: "installed", Msg: "ok"}},
	}
	lockPath := t.TempDir() + "/.lock"
	s := NewSession(p, runner, t.TempDir(), nil, false, lockPath)
	s.Execute("node")
	if !s.locked {
		t.Fatal("expected session to be locked")
	}
	if err := s.Close(); err != nil {
		t.Fatalf("expected no error on close, got %v", err)
	}
	if s.locked {
		t.Fatal("expected session to be unlocked after close")
	}
}
