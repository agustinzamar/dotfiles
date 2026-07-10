package manifest

import (
	"testing"
)

func TestLoad(t *testing.T) {
	m, err := Load("../../config/tools.yaml")
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}
	if len(m.Categories) == 0 {
		t.Fatal("expected categories, got none")
	}
	for _, cat := range m.Categories {
		if cat.Name == "" {
			t.Fatal("category has empty name")
		}
		for _, tool := range cat.Tools {
			if tool.Name == "" {
				t.Fatal("tool has empty name")
			}
			if tool.Category != cat.Name {
				t.Fatalf("tool %s category %q, expected %q", tool.Name, tool.Category, cat.Name)
			}
		}
	}
}
