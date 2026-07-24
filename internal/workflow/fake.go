package workflow

import (
	"strings"
	"sync"
)

type fakePrompt struct {
	mu       sync.Mutex
	values   []string
	confirms []bool
	idx      int
}

func newFakePrompt(values []string, confirms []bool) *fakePrompt {
	return &fakePrompt{values: values, confirms: confirms}
}

func (f *fakePrompt) Confirm(title string, defaultYes bool) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.idx >= len(f.confirms) {
		return defaultYes, nil
	}
	v := f.confirms[f.idx]
	f.idx++
	return v, nil
}

func (f *fakePrompt) Input(title, value string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.idx >= len(f.values) {
		return "", nil
	}
	v := f.values[f.idx]
	f.idx++
	return v, nil
}

func (f *fakePrompt) Choose(title string, options []string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.idx >= len(f.values) {
		return "", nil
	}
	v := f.values[f.idx]
	f.idx++
	return v, nil
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
