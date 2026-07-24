package manifest

import (
	"os"
	"path/filepath"
	"sort"

	"gopkg.in/yaml.v3"
)

type Manifest struct {
	Vars       map[string]VarDef `yaml:"vars,omitempty"`
	Categories []Category        `yaml:"categories"`
	byID       map[string]*Node
	validated  bool
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
	"git-identity":     true,
	"github-auth":      true,
	"signed-commits":   true,
	"hunk-git-pager":   true,
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
}

type Tool struct {
	Category    string     `yaml:"-"`
	Name        string     `yaml:"name"`
	Description string     `yaml:"description"`
	Checked     bool       `yaml:"checked"`
	Profiles    []string   `yaml:"profiles,omitempty"`
	DependsOn   []string   `yaml:"depends_on,omitempty"`
	Steps       []Step     `yaml:"steps,omitempty"`
	Features    []Feature  `yaml:"features,omitempty"`
}

type Feature struct {
	Name        string   `yaml:"name"`
	Description string   `yaml:"description,omitempty"`
	Checked     bool     `yaml:"checked"`
	Steps       []Step   `yaml:"steps,omitempty"`
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
		hasExplicitNodes := len(cat.Nodes) > 0
		if hasExplicitNodes && len(cat.Tools) == 0 {
			m.Categories[ci].Tools = nodesToTools(cat.Nodes, cat.ID, cat.Name)
			m.validated = true
		} else if len(cat.Tools) > 0 && len(cat.Nodes) == 0 {
			m.Categories[ci].Nodes = toolsToNodes(cat.Tools, cat.ID, cat.Name)
		}
	}
	if err := m.buildIndex(); err != nil {
		return nil, err
	}
	if err := m.Validate(); err != nil {
		return nil, err
	}
	return &m, nil
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
			Requires:    t.DependsOn,
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
	if !m.validated {
		return nil
	}
	for ci := range m.Categories {
		cat := &m.Categories[ci]
		if cat.ID == "" {
			return &ValidationError{NodeID: "<category>", Reason: "category id is empty"}
		}
		for ni := range cat.Nodes {
			if err := validateNode(cat, &cat.Nodes[ni], m.byID, map[string]bool{}); err != nil {
				return err
			}
		}
	}
	return nil
}

func validateNode(cat *Category, n *Node, byID map[string]*Node, path map[string]bool) error {
	if n.ID == "" {
		return &ValidationError{NodeID: cat.ID, Reason: "node id is empty"}
	}
	if n.Name == "" {
		return &ValidationError{NodeID: n.ID, Reason: "node name is empty"}
	}
	if _, ok := byID[n.ID]; !ok {
		return &ValidationError{NodeID: n.ID, Reason: "node not indexed"}
	}
	if path[n.ID] {
		return &ValidationError{NodeID: n.ID, Reason: "tree cycle detected"}
	}
	path[n.ID] = true
	for _, w := range n.Setup {
		if !KnownWorkflows[w] {
			return &ValidationError{NodeID: n.ID, Reason: "unknown workflow " + w}
		}
	}
	for _, req := range n.Requires {
		if _, ok := byID[req]; !ok {
			return &ValidationError{NodeID: n.ID, Reason: "requires unknown node " + req}
		}
		target, ok := byID[req]
		if !ok {
			continue
		}
		if err := validateRequires(cat, target, byID, map[string]bool{}); err != nil {
			return err
		}
	}
	for i := range n.Children {
		if err := validateNode(cat, &n.Children[i], byID, path); err != nil {
			return err
		}
	}
	delete(path, n.ID)
	return nil
}

func validateRequires(cat *Category, n *Node, byID map[string]*Node, path map[string]bool) error {
	if path[n.ID] {
		return &ValidationError{NodeID: n.ID, Reason: "requires cycle detected"}
	}
	path[n.ID] = true
	for _, req := range n.Requires {
		target, ok := byID[req]
		if !ok {
			continue
		}
		if err := validateRequires(cat, target, byID, path); err != nil {
			return err
		}
	}
	for i := range n.Children {
		if err := validateNode(cat, &n.Children[i], byID, map[string]bool{}); err != nil {
			return err
		}
	}
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
