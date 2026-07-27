package manifest

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"gopkg.in/yaml.v3"
)

type Manifest struct {
	Vars       map[string]VarDef `yaml:"vars,omitempty"`
	Categories []Category        `yaml:"categories"`
	byID       map[string]*Node
}

type VarDef struct {
	Name        string `yaml:"-"`
	Description string `yaml:"description"`
	Why         string `yaml:"why"`
	Hint        string `yaml:"hint"`
}

type Category struct {
	ID    string `yaml:"id,omitempty"`
	Name  string `yaml:"name"`
	Nodes []Node `yaml:"nodes,omitempty"`
	Tools []Tool `yaml:"tools,omitempty"`
}

type Node struct {
	ID          string   `yaml:"id"`
	Name        string   `yaml:"name"`
	Description string   `yaml:"description,omitempty"`
	Default     bool     `yaml:"default"`
	Checked     bool     `yaml:"checked,omitempty"`
	Profiles    []string `yaml:"profiles,omitempty"`
	Requires    []string `yaml:"requires,omitempty"`
	Steps       []Step   `yaml:"steps,omitempty"`
	Setup       []string `yaml:"setup,omitempty"`
	Children    []Node   `yaml:"children,omitempty"`
	Category    string   `yaml:"-"`
	CategoryID  string   `yaml:"-"`
	ParentID    string   `yaml:"-"`
}

type NodeRef struct {
	Node       *Node
	CategoryID string
	Category   string
	ParentID   string
}

func (n Node) MatchesProfile(profile string) bool {
	if len(n.Profiles) == 0 {
		return true
	}
	for _, p := range n.Profiles {
		if p == profile {
			return true
		}
	}
	return false
}

var KnownWorkflows = map[string]bool{
	"git-identity":   true,
	"github-auth":    true,
	"signed-commits": true,
	"hunk-git-pager": true,
}

var KnownImplicitProviders = map[string]bool{
	"homebrew": true,
	"vscode":   true,
	"omz":      true,
}

type Step struct {
	Type      string            `yaml:"type"`
	Package   string            `yaml:"package,omitempty"`
	Repo      string            `yaml:"repo,omitempty"`
	Extension string            `yaml:"extension,omitempty"`
	From      string            `yaml:"from,omitempty"`
	To        string            `yaml:"to,omitempty"`
	Vars      []string          `yaml:"vars,omitempty"`
	Dest      string            `yaml:"dest,omitempty"`
	Depth     int               `yaml:"depth,omitempty"`
	Command   string            `yaml:"command,omitempty"`
	Env       map[string]string `yaml:"env,omitempty"`
	Skip      string            `yaml:"skip,omitempty"`
	Domain    string            `yaml:"domain,omitempty"`
	Key       string            `yaml:"key,omitempty"`
	Value     string            `yaml:"value,omitempty"`
	ValueType string            `yaml:"valueType,omitempty"`
	Needs     []string          `yaml:"needs,omitempty"`
	Provides  []string          `yaml:"provides,omitempty"`
}

type Tool struct {
	Category    string    `yaml:"-"`
	Name        string    `yaml:"name"`
	Description string    `yaml:"description"`
	Checked     bool      `yaml:"checked"`
	Profiles    []string  `yaml:"profiles,omitempty"`
	DependsOn   []string  `yaml:"depends_on,omitempty"`
	Steps       []Step    `yaml:"steps,omitempty"`
	Features    []Feature `yaml:"features,omitempty"`
}

type Feature struct {
	Name        string `yaml:"name"`
	Description string `yaml:"description,omitempty"`
	Checked     bool   `yaml:"checked"`
	Steps       []Step `yaml:"steps,omitempty"`
}

func (t Tool) MatchesProfile(profile string) bool {
	if len(t.Profiles) == 0 {
		return true
	}
	for _, p := range t.Profiles {
		if p == profile {
			return true
		}
	}
	return false
}

func (t Tool) CategoryName() string { return t.Category }

func Load(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m Manifest
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	for ci := range m.Categories {
		cat := &m.Categories[ci]
		if cat.ID == "" {
			cat.ID = cat.Name
		}
		hasExplicitNodes := len(cat.Nodes) > 0
		if hasExplicitNodes && len(cat.Tools) == 0 {
			m.Categories[ci].Tools = nodesToTools(cat.Nodes, cat.ID, cat.Name)
		} else if len(cat.Tools) > 0 && len(cat.Nodes) == 0 {
			m.Categories[ci].Nodes = toolsToNodes(cat.Tools, cat.ID, cat.Name)
		}
	}
	normalizeLegacyRequirements(m.Categories)
	if err := m.buildIndex(); err != nil {
		return nil, err
	}
	if err := m.Validate(); err != nil {
		return nil, err
	}
	return &m, nil
}

func normalizeLegacyRequirements(categories []Category) {
	byName := map[string]string{}
	var collect func([]Node)
	collect = func(nodes []Node) {
		for i := range nodes {
			byName[nodes[i].Name] = nodes[i].ID
			collect(nodes[i].Children)
		}
	}
	for _, category := range categories {
		collect(category.Nodes)
	}
	var normalize func([]Node)
	normalize = func(nodes []Node) {
		for i := range nodes {
			for j, requirement := range nodes[i].Requires {
				if id, ok := byName[requirement]; ok {
					nodes[i].Requires[j] = id
				}
			}
			normalize(nodes[i].Children)
		}
	}
	for i := range categories {
		normalize(categories[i].Nodes)
	}
}

func nodesToTools(nodes []Node, categoryID, category string) []Tool {
	tools := make([]Tool, 0, len(nodes))
	for i := range nodes {
		n := &nodes[i]
		n.Category = category
		n.CategoryID = categoryID
		tools = append(tools, Tool{
			Category:    category,
			Name:        n.Name,
			Description: n.Description,
			Checked:     n.Checked,
			Profiles:    n.Profiles,
			DependsOn:   n.Requires,
			Steps:       n.Steps,
		})
	}
	return tools
}

func toolsToNodes(tools []Tool, categoryID, category string) []Node {
	nodes := make([]Node, 0, len(tools))
	ids := make(map[string]string, len(tools))
	for _, t := range tools {
		ids[t.Name] = categoryID + "-" + t.Name
	}
	for i := range tools {
		t := &tools[i]
		n := Node{
			ID:          categoryID + "-" + t.Name,
			Category:    category,
			CategoryID:  categoryID,
			Name:        t.Name,
			Description: t.Description,
			Checked:     t.Checked,
			Profiles:    t.Profiles,
			Requires:    translateRequirements(t.DependsOn, ids),
			Steps:       t.Steps,
		}
		if t.Checked {
			n.Default = true
		}
		for j := range t.Features {
			f := t.Features[j]
			child := Node{
				ID:          categoryID + "-" + t.Name + "-" + f.Name,
				Name:        f.Name,
				Description: f.Description,
				Checked:     f.Checked,
				Steps:       f.Steps,
				ParentID:    n.ID,
			}
			if f.Checked {
				child.Default = true
			}
			n.Children = append(n.Children, child)
		}
		nodes = append(nodes, n)
	}
	return nodes
}

func translateRequirements(requirements []string, ids map[string]string) []string {
	translated := make([]string, len(requirements))
	for i, requirement := range requirements {
		if id, ok := ids[requirement]; ok {
			translated[i] = id
		} else {
			translated[i] = requirement
		}
	}
	return translated
}

func (m *Manifest) Node(id string) (*Node, *Category, bool) {
	n, ok := m.byID[id]
	if !ok {
		return nil, nil, false
	}
	for i := range m.Categories {
		if m.Categories[i].ID == n.CategoryID {
			return n, &m.Categories[i], true
		}
	}
	return n, nil, true
}

func (m *Manifest) Walk(fn func(NodeRef) error) error {
	for ci := range m.Categories {
		cat := &m.Categories[ci]
		for ni := range cat.Nodes {
			if err := walkNode(cat, &cat.Nodes[ni], fn); err != nil {
				return err
			}
		}
	}
	return nil
}

func walkNode(cat *Category, n *Node, fn func(NodeRef) error) error {
	if err := fn(NodeRef{Node: n, CategoryID: cat.ID, Category: cat.Name, ParentID: n.ParentID}); err != nil {
		return err
	}
	for i := range n.Children {
		child := &n.Children[i]
		child.Category = cat.Name
		child.CategoryID = cat.ID
		child.ParentID = n.ID
		if err := walkNode(cat, child, fn); err != nil {
			return err
		}
	}
	return nil
}

func (m *Manifest) buildIndex() error {
	m.byID = map[string]*Node{}
	for ci := range m.Categories {
		cat := &m.Categories[ci]
		if cat.ID == "" {
			cat.ID = cat.Name
		}
		for ni := range cat.Nodes {
			if err := indexNode(cat, &cat.Nodes[ni], m.byID); err != nil {
				return err
			}
		}
	}
	return nil
}

func indexNode(cat *Category, n *Node, byID map[string]*Node) error {
	if n.ID == "" {
		n.ID = n.Name
	}
	if _, ok := byID[n.ID]; ok {
		return &DuplicateIDError{CategoryID: cat.ID, NodeID: n.ID}
	}
	n.Category = cat.Name
	n.CategoryID = cat.ID
	byID[n.ID] = n
	if n.Default {
		n.Checked = true
	}
	for i := range n.Children {
		child := &n.Children[i]
		child.ParentID = n.ID
		if err := indexNode(cat, child, byID); err != nil {
			return err
		}
	}
	return nil
}

type DuplicateIDError struct {
	CategoryID string
	NodeID     string
}

func (e *DuplicateIDError) Error() string {
	return "duplicate node id " + e.NodeID + " in category " + e.CategoryID
}

func (m *Manifest) Validate() error {
	if m.byID == nil {
		if err := m.buildIndex(); err != nil {
			return err
		}
	}
	providedTags := m.allProvidedTags()
	for _, cat := range m.Categories {
		if cat.ID == "" {
			return &ValidationError{NodeID: "<category>", Reason: "category has empty ID"}
		}
		for _, n := range cat.Nodes {
			if err := m.validateNode(cat, n, map[string]bool{}, providedTags); err != nil {
				return err
			}
		}
	}
	return nil
}

func (m *Manifest) allProvidedTags() map[string]bool {
	tags := map[string]bool{}
	for _, cat := range m.Categories {
		for _, n := range cat.Nodes {
			for _, step := range n.Steps {
				for _, p := range step.Provides {
					tags[p] = true
				}
			}
		}
	}
	return tags
}

func (m *Manifest) validateNode(cat Category, n Node, path map[string]bool, providedTags map[string]bool) error {
	if n.ID == "" {
		return &ValidationError{NodeID: cat.ID, Reason: "node id is empty"}
	}
	if n.Name == "" {
		return &ValidationError{NodeID: n.ID, Reason: "node name is empty"}
	}
	if _, exists := m.byID[n.ID]; !exists {
		return &ValidationError{NodeID: n.ID, Reason: "node not indexed"}
	}
	if path[n.ID] {
		return &ValidationError{NodeID: n.ID, Reason: "tree cycle detected"}
	}
	for _, w := range n.Setup {
		if !KnownWorkflows[w] {
			return &ValidationError{NodeID: n.ID, Reason: "unknown workflow " + w}
		}
	}

	// Validate needs tags
	for _, step := range n.Steps {
		for _, need := range step.Needs {
			if KnownImplicitProviders[need] {
				continue
			}
			if _, exists := m.byID[need]; exists {
				continue
			}
			if providedTags[need] {
				continue
			}
			return &ValidationError{
				NodeID: n.ID,
				Reason: fmt.Sprintf("needs tag %q has no provider in manifest and is not a known implicit provider", need),
			}
		}
	}

	// Note: `n.Requires` is still populated by `toolsToNodes()` during
	// the Phase 2 transition. Do NOT reject it here — only warn.
	// Strict rejection comes in Phase 2 after tools.yaml migration.

	path[n.ID] = true
	for _, child := range n.Children {
		child.CategoryID = cat.ID
		child.Category = cat.Name
		child.ParentID = n.ID
		if err := m.validateNode(cat, child, path, providedTags); err != nil {
			return err
		}
	}
	for _, req := range n.Requires {
		if req == n.ID {
			return &ValidationError{NodeID: n.ID, Reason: fmt.Sprintf("node requires itself: %s", n.ID)}
		}
		if path[req] {
			return &ValidationError{NodeID: n.ID, Reason: "requires cycle detected"}
		}
		target, exists := m.byID[req]
		if !exists {
			return &ValidationError{NodeID: n.ID, Reason: fmt.Sprintf("requires unknown node: %s", req)}
		}
		if err := m.validateNode(cat, *target, path, providedTags); err != nil {
			return err
		}
	}
	delete(path, n.ID)
	return nil
}

type ValidationError struct {
	NodeID string
	Reason string
}

func (e *ValidationError) Error() string {
	return "node " + e.NodeID + ": " + e.Reason
}

func DotfilesDir() string {
	if dir := os.Getenv("DOTFILES_HOME"); dir != "" {
		return dir
	}
	if exe, err := os.Executable(); err == nil {
		if dir := resolveDotfilesDir(filepath.Dir(exe)); dir != "" {
			return dir
		}
	}
	if cwd, err := os.Getwd(); err == nil {
		if dir := resolveDotfilesDir(cwd); dir != "" {
			return dir
		}
	}
	home, _ := os.UserHomeDir()
	for _, d := range []string{
		home + "/.dotfiles",
		home + "/Documents/repos/dotfiles",
	} {
		if _, err := os.Stat(filepath.Join(d, "config", "tools.yaml")); err == nil {
			return d
		}
	}
	return home + "/.dotfiles"
}

func resolveDotfilesDir(start string) string {
	dir := start
	for range 6 {
		if _, err := os.Stat(filepath.Join(dir, "config", "tools.yaml")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return ""
}

var _ sort.Interface = (*Category)(nil)

func (c Category) Len() int      { return len(c.Nodes) }
func (c Category) Swap(i, j int) { c.Nodes[i], c.Nodes[j] = c.Nodes[j], c.Nodes[i] }
func (c Category) Less(i, j int) bool {
	if c.Nodes[i].Default != c.Nodes[j].Default {
		return c.Nodes[i].Default
	}
	return c.Nodes[i].Name < c.Nodes[j].Name
}
