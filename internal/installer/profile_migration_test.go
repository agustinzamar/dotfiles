package installer

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestMigrateProfileDataMapsLegacyComponents(t *testing.T) {
	profile, changed, err := MigrateProfileData(Profile{Components: map[string]bool{
		"base":          true,
		"communication": true,
		"desktop":       false,
		"media":         true,
		"databases":     true,
	}})
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("migration did not report a change")
	}
	for _, id := range []string{
		"communication-discord", "communication-telegram", "communication-whatsapp", "communication-slack",
		"media-tools", "media-spotify", "media-stremio", "media-vlc", "media-castor",
		"service-mysql", "service-postgresql", "service-redis", "service-sqlite",
	} {
		if !profile.Components[id] {
			t.Fatalf("migrated component %q is not selected", id)
		}
	}
	if profile.Components["desktop-chrome"] || profile.Components["communication"] || profile.Components["desktop"] || profile.Components["media"] || profile.Components["databases"] {
		t.Fatal("legacy component state remains or false desktop was enabled")
	}
}

func TestMigrateProfileDataIsIdempotent(t *testing.T) {
	profile, _, err := MigrateProfileData(Profile{Components: map[string]bool{"communication": true}})
	if err != nil {
		t.Fatal(err)
	}
	_, changed, err := MigrateProfileData(profile)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Fatal("second migration reported a change")
	}
}

func TestLoadProfileSavesMigratedData(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.json")
	data := []byte(`{"components":{"base":true,"communication":true}}`)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	profile, err := LoadProfile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !profile.Components["communication-discord"] {
		t.Fatal("loaded profile was not migrated")
	}
	saved, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var stored Profile
	if err := json.Unmarshal(saved, &stored); err != nil {
		t.Fatal(err)
	}
	if stored.Components["communication"] {
		t.Fatal("legacy profile was not replaced")
	}
}
