package workflow

import (
	"os/exec"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

type CommandRunner interface {
	Run(name string, args ...string) (string, error)
	LookPath(name string) (string, error)
}

type Prompt interface {
	Confirm(title string, defaultYes bool) (bool, error)
	Input(title, value string) (string, error)
	Choose(title string, options []string) (string, error)
}

type Result struct {
	Outcome     Outcome
	Reason      string
	Interactive *exec.Cmd
}

type Outcome string

const (
	OutcomeComplete Outcome = "complete"
	OutcomePending  Outcome = "pending"
	OutcomeFailed   Outcome = "failed"
)

type Handler func(Prompt, CommandRunner) (Result, error)

type Registry struct {
	handlers map[string]Handler
}

func NewRegistry() *Registry {
	return &Registry{handlers: map[string]Handler{}}
}

func (r *Registry) Register(name string, handler Handler) {
	r.handlers[name] = handler
}

func (r *Registry) Get(name string) (Handler, bool) {
	h, ok := r.handlers[name]
	return h, ok
}

var KnownHandlers = map[string]bool{
	"git-identity":   true,
	"github-auth":    true,
	"signed-commits": true,
	"hunk-git-pager": true,
}

type Runner struct {
	registry *Registry
}

func NewRunner(registry *Registry) *Runner {
	return &Runner{registry: registry}
}

func (r *Runner) Run(name string, prompt Prompt, runner CommandRunner) (Result, error) {
	handler, ok := r.registry.Get(name)
	if !ok {
		return Result{Outcome: OutcomeFailed, Reason: "unknown workflow " + name}, nil
	}
	return handler(prompt, runner)
}

func NodeSteps(node manifest.NodeRef) []manifest.Step {
	steps := node.Node.Steps
	for _, child := range node.Node.Children {
		steps = append(steps, child.Steps...)
	}
	return steps
}
