package installer

var implicitStepNeeds = map[string][]string{
	"cask":       {"homebrew"},
	"tap":        {"homebrew"},
	"vscode":     {"vscode"},
	"omz-plugin": {"omz"},
}

var implicitStepProvides = map[string][]string{
	"brew": {"homebrew"},
	"cask": {"homebrew"},
}

type ProbeFunc func(tag string, item *Item) bool

type DepResolver struct {
	providesIndex map[string][]*Item
	neededBy      map[*Item][]*Item
	probeFunc     ProbeFunc
}

func NewDepResolver(items []*Item, probeFunc ProbeFunc) *DepResolver {
	dr := &DepResolver{
		providesIndex: map[string][]*Item{},
		neededBy:      map[*Item][]*Item{},
		probeFunc:     probeFunc,
	}
	for _, item := range items {
		dr.registerProvides(item)
	}
	for _, item := range items {
		dr.registerNeeds(item)
	}
	return dr
}

func (d *DepResolver) registerProvides(item *Item) {
	seen := map[string]bool{}
	for _, step := range item.Node.Node.Steps {
		for _, tag := range step.Provides {
			if !seen[tag] {
				d.providesIndex[tag] = append(d.providesIndex[tag], item)
				seen[tag] = true
			}
		}
		for _, tag := range implicitStepProvides[step.Type] {
			if !seen[tag] {
				d.providesIndex[tag] = append(d.providesIndex[tag], item)
				seen[tag] = true
			}
		}
	}
}

func (d *DepResolver) registerNeeds(item *Item) {
	for _, step := range item.Node.Node.Steps {
		seen := map[string]bool{}
		for _, need := range step.Needs {
			if seen[need] {
				continue
			}
			seen[need] = true
			for _, provider := range d.providesIndex[need] {
				d.neededBy[provider] = append(d.neededBy[provider], item)
			}
		}
	}
}

func (d *DepResolver) needsOf(item *Item) []string {
	seen := map[string]bool{}
	var result []string
	for _, step := range item.Node.Node.Steps {
		for _, need := range step.Needs {
			if !seen[need] {
				result = append(result, need)
				seen[need] = true
			}
		}
		for _, need := range implicitStepNeeds[step.Type] {
			if !seen[need] {
				result = append(result, need)
				seen[need] = true
			}
		}
	}
	return result
}

func (d *DepResolver) providersFor(tag string) []*Item {
	return d.providesIndex[tag]
}

func (d *DepResolver) satisfied(item *Item) bool {
	if d.probeFunc == nil {
		return false
	}
	for _, tag := range d.allProvides(item) {
		if d.probeFunc(tag, item) {
			return true
		}
	}
	return false
}

func (d *DepResolver) declined(item *Item) bool {
	return item.Decision == DecisionNo && item.Status == StatusDeclined
}

func (d *DepResolver) allProvides(item *Item) []string {
	seen := map[string]bool{}
	var result []string
	for _, step := range item.Node.Node.Steps {
		for _, tag := range step.Provides {
			if !seen[tag] {
				result = append(result, tag)
				seen[tag] = true
			}
		}
		for _, tag := range implicitStepProvides[step.Type] {
			if !seen[tag] {
				result = append(result, tag)
				seen[tag] = true
			}
		}
	}
	return result
}
