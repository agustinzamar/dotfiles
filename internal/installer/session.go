package installer

import (
	"errors"
	"sort"
	"time"

	"github.com/agustinzamar/dotfiles/internal/executor"
	"github.com/agustinzamar/dotfiles/internal/lock"
	"github.com/agustinzamar/dotfiles/internal/manifest"
	"github.com/agustinzamar/dotfiles/internal/snapshot"
)

type StepRunner interface {
	Run(step manifest.Step, dotfilesDir string, vars map[string]string, dryRun bool) executor.Result
}

type Result struct {
	ItemID string
	Status Status
	Reason string
	Error  error
}

type Session struct {
	dotfilesDir string
	vars        map[string]string
	dryRun      bool
	planner     *Planner
	runner      StepRunner
	lockPath    string
	locked      bool
	results     map[string]Result
	changed     bool
}

func NewSession(planner *Planner, runner StepRunner, dotfilesDir string, vars map[string]string, dryRun bool, lockPath string) *Session {
	return &Session{
		planner:     planner,
		runner:      runner,
		dotfilesDir: dotfilesDir,
		vars:        vars,
		dryRun:      dryRun,
		lockPath:    lockPath,
		results:     map[string]Result{},
	}
}

func (s *Session) Planner() *Planner {
	return s.planner
}

func (s *Session) DryRun() bool {
	return s.dryRun
}

func (s *Session) LockPath() string {
	return s.lockPath
}

func (s *Session) Execute(itemID string) Result {
	if s.lockPath != "" && !s.dryRun && !s.locked {
		lk := lock.New(s.lockPath)
		if err := lk.Acquire(); err != nil {
			return Result{ItemID: itemID, Status: StatusFailed, Error: err}
		}
		s.locked = true
	}

	if !s.dryRun {
		executor.ResetSnapshots()
	}

	item, ok := s.planner.byID[itemID]
	if !ok {
		return Result{ItemID: itemID, Status: StatusFailed, Error: errors.New("unknown item")}
	}
	if item.Status != StatusPlanned || item.Decision != DecisionYes {
		return Result{ItemID: itemID, Status: item.Status}
	}

	var lastResult executor.Result
	installed := false
	hasFailure := false

	for _, step := range item.Node.Node.Steps {
		r := s.runner.Run(step, s.dotfilesDir, s.vars, s.dryRun)
		lastResult = r
		if r.Status == "error" {
			hasFailure = true
			break
		}
		if r.Status == "installed" || r.Status == "would-install" {
			installed = true
		}
		if r.Status != "skipped" && r.Status != "would-skip" {
			s.changed = true
		}
	}

	status := StatusAlreadyPresent
	if hasFailure {
		item.Status = StatusFailed
		status = StatusFailed
	} else if s.dryRun {
		if installed || lastResult.Status == "would-skip" {
			item.Status = StatusWouldInstall
			status = StatusWouldInstall
		} else {
			item.Status = StatusAlreadyPresent
			status = StatusAlreadyPresent
		}
	} else {
		if installed {
			item.Status = StatusInstalled
			status = StatusInstalled
		} else {
			item.Status = StatusAlreadyPresent
			status = StatusAlreadyPresent
		}
	}

	result := Result{ItemID: itemID, Status: status, Reason: lastResult.Msg}
	s.results[itemID] = result
	return result
}

func (s *Session) ExecuteSteps(itemID string) Result {
	if s.lockPath != "" && !s.dryRun && !s.locked {
		lk := lock.New(s.lockPath)
		if err := lk.Acquire(); err != nil {
			return Result{ItemID: itemID, Status: StatusFailed, Error: err}
		}
		s.locked = true
	}

	if !s.dryRun {
		executor.ResetSnapshots()
	}

	item, ok := s.planner.byID[itemID]
	if !ok {
		return Result{ItemID: itemID, Status: StatusFailed, Error: errors.New("unknown item")}
	}
	if item.Status != StatusPlanned || item.Decision != DecisionYes {
		return Result{ItemID: itemID, Status: item.Status}
	}

	var lastResult executor.Result
	installed := false
	hasFailure := false

	// Run parent node steps AND all accepted children's steps
	runNodeSteps := func(node manifest.Node) {
		for _, step := range node.Steps {
			r := s.runner.Run(step, s.dotfilesDir, s.vars, s.dryRun)
			lastResult = r
			if r.Status == "error" {
				hasFailure = true
				return
			}
			if r.Status == "installed" || r.Status == "would-install" {
				installed = true
			}
			if r.Status != "skipped" && r.Status != "would-skip" {
				s.changed = true
			}
		}
	}

	runNodeSteps(*item.Node.Node)

	if !hasFailure && len(item.Node.Node.Children) > 0 {
		for _, child := range item.Node.Node.Children {
			childItem, ok := s.planner.byID[child.ID]
			if !ok {
				continue
			}
			if childItem.Decision != DecisionYes || childItem.Status != StatusPlanned {
				continue
			}
			if declinedDep := s.planner.hasDeclinedDependency(childItem); declinedDep {
				continue
			}
			runNodeSteps(*childItem.Node.Node)
			if hasFailure {
				break
			}
		}
	}

	status := StatusAlreadyPresent
	if hasFailure {
		item.Status = StatusFailed
		status = StatusFailed
	} else if s.dryRun {
		if installed || lastResult.Status == "would-skip" {
			item.Status = StatusWouldInstall
			status = StatusWouldInstall
		} else {
			item.Status = StatusAlreadyPresent
			status = StatusAlreadyPresent
		}
	} else {
		if installed {
			item.Status = StatusInstalled
			status = StatusInstalled
		} else {
			item.Status = StatusAlreadyPresent
			status = StatusAlreadyPresent
		}
	}

	result := Result{ItemID: itemID, Status: status, Reason: lastResult.Msg}
	s.results[itemID] = result
	return result
}

func (s *Session) Results() []Result {
	out := make([]Result, 0, len(s.results))
	for _, r := range s.results {
		out = append(out, r)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ItemID < out[j].ItemID })
	return out
}

func (s *Session) Close() error {
	if !s.locked || s.lockPath == "" {
		return nil
	}
	var closeErr error
	if s.changed && !s.dryRun {
		entries := executor.SnapshotEntries()
		if len(entries) > 0 {
			ts := time.Now().Format("20060102T150405")
			sm := &snapshot.Manifest{Timestamp: ts, Entries: entries}
			if err := snapshot.SaveManifest(sm, s.dotfilesDir); err != nil {
				closeErr = errors.Join(closeErr, err)
			}
			if err := snapshot.PruneSnapshots(s.dotfilesDir, 5); err != nil {
				closeErr = errors.Join(closeErr, err)
			}
		}
	}
	lk := lock.New(s.lockPath)
	if err := lk.Release(); err != nil {
		closeErr = errors.Join(closeErr, err)
	}
	s.locked = false
	return closeErr
}
