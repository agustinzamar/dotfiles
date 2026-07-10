package config

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

var varsCachePath string

func init() {
	home, _ := os.UserHomeDir()
	varsCachePath = filepath.Join(home, ".dotfiles-custom", "vars.json")
}

func GetVars() map[string]string {
	vars := map[string]string{}
	data, _ := os.ReadFile(varsCachePath)
	json.Unmarshal(data, &vars)
	return vars
}

func PromptMissing(needed []string) error {
	vars := GetVars()
	for _, key := range needed {
		if vars[key] != "" {
			continue
		}
		fmt.Printf("%s: ", key)
		reader := bufio.NewReader(os.Stdin)
		val, _ := reader.ReadString('\n')
		vars[key] = strings.TrimSpace(val)
		if err := SaveVars(vars); err != nil {
			return err
		}
	}
	return nil
}

func SaveVars(vars map[string]string) error {
	os.MkdirAll(filepath.Dir(varsCachePath), 0755)
	data, _ := json.MarshalIndent(vars, "", "  ")
	if err := os.WriteFile(varsCachePath, data, 0600); err != nil {
		return err
	}
	return os.Chmod(varsCachePath, 0600)
}

func Render(tmplStr string, vars map[string]string) (string, error) {
	tmpl, err := template.New("config").Parse(tmplStr)
	if err != nil {
		return "", err
	}
	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, vars); err != nil {
		return "", err
	}
	return buf.String(), nil
}
