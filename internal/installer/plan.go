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
	ID         string
	Name       string
	ParentID   string
	Node       manifest.NodeRef
	PromptOnly bool
	Decision   Decision
	Status     Status
	Reason     string
	prompted   bool
}

type Planner struct {
	profile  string
	selected func(*manifest.Node) bool
	items    []*Item
	queue    []*Item
	history  []*Item
	byID     map[string]*Item
}

func NewPlanner(m *manifest.Manifest, profile string) *Planner {
	return newPlanner(m, profile, nil)
}

func NewBasicPlanner(m *manifest.Manifest, profile string) *Planner {
	return newPlanner(m, profile, func(node *manifest.Node) bool { return node.Basic })
}

func NewMacOSPlanner(m *manifest.Manifest, profile string) *Planner {
	return newPlanner(m, profile, func(node *manifest.Node) bool { return node.MacOS })
}

func newPlanner(m *manifest.Manifest, profile string, selected func(*manifest.Node) bool) *Planner {
	p := &Planner{
		profile:  profile,
		selected: selected,
		byID:     map[string]*Item{},
	}
	for ci := range m.Categories {
		cat := &m.Categories[ci]
		categoryID := "category:" + cat.ID
		start := len(p.items)
		for ni := range cat.Nodes {
			p.addNode(cat, &cat.Nodes[ni], categoryID, false)
		}
		if len(p.items) == start {
			continue
		}
		category := &Item{
			ID:         categoryID,
			Name:       cat.Name,
			Node:       manifest.NodeRef{Node: &manifest.Node{ID: categoryID, Name: cat.Name}, CategoryID: cat.ID, Category: cat.Name},
			PromptOnly: true,
			Decision:   DecisionYes,
			Status:     StatusPlanned,
		}
		p.items = append(p.items, nil)
		copy(p.items[start+1:], p.items[start:])
		p.items[start] = category
		p.byID[category.ID] = category
	}
	p.rebuildQueue()
	return p
}

func (p *Planner) addNode(cat *manifest.Category, node *manifest.Node, parentID string, selectedParent bool) {
	if !node.MatchesProfile(p.profile) {
		return
	}
	includeSubtree := selectedParent || p.selected == nil || p.selected(node)
	if p.selected != nil && !includeSubtree && !hasSelectedDescendant(node, p.selected) {
		return
	}
	item := &Item{
		ID:         node.ID,
		Name:       node.Name,
		ParentID:   parentID,
		Node:       manifest.NodeRef{Node: node, CategoryID: cat.ID, Category: cat.Name, ParentID: parentID},
		PromptOnly: len(node.Steps) == 0 && len(node.Setup) == 0 && len(node.Children) > 0,
		Status:     StatusPlanned,
	}
	if node.Default {
		item.Decision = DecisionYes
	}
	p.items = append(p.items, item)
	p.byID[item.ID] = item
	for i := range node.Children {
		p.addNode(cat, &node.Children[i], node.ID, includeSubtree)
	}
}

func hasSelectedDescendant(node *manifest.Node, selected func(*manifest.Node) bool) bool {
	for i := range node.Children {
		if selected(&node.Children[i]) || hasSelectedDescendant(&node.Children[i], selected) {
			return true
		}
	}
	return false
}

func (p *Planner) SetAll(decision Decision) {
	for _, item := range p.items {
		if item.Status == StatusPlanned {
			item.Decision = decision
		}
	}
	p.rebuildQueue()
}

func (p *Planner) rebuildQueue() {
	p.queue = nil
	for i := range p.items {
		item := p.items[i]
		if item.Status == StatusPlanned && !item.prompted {
			p.queue = append(p.queue, item)
		}
	}
}

func (p *Planner) dependencyState(item *Item) (pending bool, blockedBy *Item) {
	if parent, ok := p.byID[item.ParentID]; ok {
		switch parent.Status {
		case StatusDeclined, StatusSkippedDependency:
			return false, parent
		case StatusFailed:
			pending = true
		case StatusPlanned:
			if !parent.prompted || parent.Decision != DecisionYes {
				pending = true
			}
		}
	}
	for _, req := range item.Node.Node.Requires {
		dep, ok := p.byID[req]
		if !ok {
			continue
		}
		switch dep.Status {
		case StatusDeclined, StatusSkippedDependency:
			return false, dep
		case StatusPlanned, StatusFailed:
			if !dep.PromptOnly || dep.Decision != DecisionYes {
				pending = true
			}
		}
	}
	return pending, nil
}

func (p *Planner) hasDeclinedDependency(item *Item) bool {
	_, blocked := p.dependencyState(item)
	return blocked != nil
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
	for remaining := len(p.queue); remaining > 0; remaining-- {
		item := p.queue[0]
		p.queue = p.queue[1:]
		if item.Status != StatusPlanned || item.prompted {
			continue
		}
		pending, blocked := p.dependencyState(item)
		if blocked != nil {
			item.Status = StatusSkippedDependency
			item.Reason = "requires " + blocked.Name
			p.markDescendantsSkipped(item)
			continue
		}
		if pending {
			p.queue = append(p.queue, item)
			continue
		}
		item.prompted = true
		return item
	}
	return nil
}

func (p *Planner) Retry(id string) bool {
	item, ok := p.byID[id]
	if !ok || item.Status != StatusFailed {
		return false
	}
	item.Status = StatusPlanned
	item.Reason = ""
	item.Decision = DecisionYes
	return true
}

func (p *Planner) SkipFailed(id string) bool {
	item, ok := p.byID[id]
	if !ok || item.Status != StatusFailed {
		return false
	}
	item.Status = StatusDeclined
	item.Decision = DecisionNo
	item.Reason = "skipped after failure"
	p.markDescendantsSkipped(item)
	p.rebuildQueue()
	return true
}

func (p *Planner) ItemCompleted(id string) {
	var related, rest []*Item
	for _, item := range p.queue {
		isRelated := item.ParentID == id
		if !isRelated {
			for _, req := range item.Node.Node.Requires {
				if req == id {
					isRelated = true
					break
				}
			}
		}
		if isRelated {
			related = append(related, item)
		} else {
			rest = append(rest, item)
		}
	}
	p.queue = append(related, rest...)
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
		if item.PromptOnly || item.Status != StatusPlanned {
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

func (p *Planner) Summary() []Item {
	out := make([]Item, 0, len(p.items))
	for _, item := range p.items {
		if !item.PromptOnly {
			out = append(out, *item)
		}
	}
	return out
}

func (p *Planner) History() []Item {
	out := make([]Item, len(p.history))
	for i, item := range p.history {
		out[i] = *item
	}
	return out
}

var ErrBackNotAllowed = errors.New("back not allowed: item already executed")
