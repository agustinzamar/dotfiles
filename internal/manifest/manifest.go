package manifest

import (
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type Manifest struct {
	Categories []Category `yaml:"categories"`
}

type Category struct {
	Name  string `yaml:"name"`
	Tools []Tool `yaml:"tools"`
}

type Tool struct {
	Category    string `yaml:"-"`
	Name        string `yaml:"name"`
	Description string `yaml:"description"`
	Checked     bool   `yaml:"checked"`
	Steps       []Step `yaml:"steps"`
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
}

func Load(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m Manifest
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	for i := range m.Categories {
		for j := range m.Categories[i].Tools {
			m.Categories[i].Tools[j].Category = m.Categories[i].Name
		}
	}
	return &m, nil
}

func (t Tool) CategoryName() string { return t.Category }

func DotfilesDir() string {
	if cwd, err := os.Getwd(); err == nil {
		dir := cwd
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
	}
	home, _ := os.UserHomeDir()
	return home + "/.dotfiles"
}
