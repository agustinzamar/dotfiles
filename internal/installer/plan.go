package installer

import (
	"errors"

	"github.com/agustinzamar/dotfiles/internal/manifest"
)

type Decision int

const (
	DecisionUnset Decision = iota
	DecisionYes
	DecisionNo
)

type Status string

const (
	StatusPlanned           Status = "planned"
	StatusDeclined          Status = "declined"
	StatusSkippedDependency Status = "skipped-dependency"
	StatusInstalled         Status = "installed"
	StatusAlreadyPresent    Status = "already-present"
	StatusPendingSetup      Status = "pending-setup"
	StatusFailed            Status = "failed"
	StatusWouldInstall      Status = "would-install"
)

type Item struct {
	ID       string
	Name     string
	ParentID string
	Node     manifest.NodeRef
	Decision Decision
	Status   Status
	Reason   string
	prompted bool
}

type Planner struct {
	profile string
	items   []*Item
	queue   []*Item
	history []*Item
	byID    map[string]*Item
}

func NewPlanner(m *manifest.Manifest, profile string) *Planner {
	p := &Planner{
		profile: profile,
		byID:    map[string]*Item{},
	}
	m.Walk(func(ref manifest.NodeRef) error {
		if !ref.Node.MatchesProfile(profile) {
			return nil
		}
		item := &Item{
			ID:       ref.Node.ID,
			Name:     ref.Node.Name,
			ParentID: ref.ParentID,
			Node:     ref,
			Status:   StatusPlanned,
		}
		if ref.Node.Default {
			item.Decision = DecisionYes
		}
		p.items = append(p.items, item)
		p.byID[item.ID] = item
		return nil
	})
	p.sortItems()
	p.rebuildQueue()
	return p
}

func (p *Planner) sortItems() {
}

func (p *Planner) rebuildQueue() {
	p.queue = nil
	for i := range p.items {
		item := p.items[i]
		if item.Status == StatusPlanned && !item.prompted && !p.hasDeclinedDependency(item) {
			p.queue = append(p.queue, item)
		}
	}
}

func (p *Planner) hasDeclinedDependency(item *Item) bool {
	for _, req := range item.Node.Node.Requires {
		dep, ok := p.byID[req]
		if !ok {
			continue
		}
		if dep.Decision == DecisionNo && dep.Status == StatusDeclined {
			return true
		}
		if dep.Status == StatusSkippedDependency {
			return true
		}
	}
	return false
}

func (p *Planner) markDescendantsSkipped(item *Item) {
	for _, candidate := range p.items {
		if candidate.ParentID == item.ID && candidate.Status == StatusPlanned {
			candidate.Status = StatusSkippedDependency
			candidate.Reason = "requires " + item.Name
			p.markDescendantsSkipped(candidate)
		}
	}
}

func (p *Planner) Next() *Item {
	for len(p.queue) > 0 {
		item := p.queue[0]
		p.queue = p.queue[1:]
		if item.Status == StatusPlanned && !item.prompted && !p.hasDeclinedDependency(item) {
			item.prompted = true
			return item
		}
	}
	return nil
}

func (p *Planner) Answer(id string, decision Decision) {
	item, ok := p.byID[id]
	if !ok {
		return
	}
	if item.Status != StatusPlanned {
		return
	}
	item.Decision = decision
	p.history = append(p.history, item)
	if decision == DecisionNo {
		item.Status = StatusDeclined
		p.markDescendantsSkipped(item)
	}
	p.rebuildQueue()
}

func (p *Planner) Back() *Item {
	for i := len(p.history) - 1; i >= 0; i-- {
		item := p.history[i]
		if item.Status != StatusPlanned {
			continue
		}
		item.Decision = DecisionUnset
		item.prompted = false
		p.history = p.history[:i]
		p.rebuildQueue()
		return item
	}
	return nil
}

func (p *Planner) SetGroupDefault(id string, decision Decision) {
	item, ok := p.byID[id]
	if !ok {
		return
	}
	if item.Status != StatusPlanned {
		return
	}
	if item.Node.Node.Children == nil || len(item.Node.Node.Children) == 0 {
		return
	}
	for _, candidate := range p.items {
		if candidate.ParentID == id {
			if candidate.Decision == DecisionUnset {
				candidate.Decision = decision
			}
		}
	}
}

func (p *Planner) Summary() []Item {
	out := make([]Item, len(p.items))
	for i, item := range p.items {
		out[i] = *item
	}
	return out
}

var ErrBackNotAllowed = errors.New("back not allowed: item already executed")
