package installer

import (
	"path/filepath"
	"testing"
)

func TestProfileDefaultsAndRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "profile.json")
	profile, err := LoadProfile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !profile.Components["base"] || !profile.Components["git"] || !profile.Components["terminal"] {
		t.Fatal("baseline not selected")
	}
	if err := SaveProfile(path, profile); err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadProfile(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded.Components) != len(profile.Components) || loaded.Components["base"] != profile.Components["base"] {
		t.Fatal("profile did not round trip")
	}
}

func TestProfileRejectsUnknownAndRequiredChanges(t *testing.T) {
	if _, err := LoadProfileData(Profile{Components: map[string]bool{"unknown": true}}); err == nil {
		t.Fatal("unknown component accepted")
	}
	profile := DefaultProfile()
	profile.Components["base"] = false
	if _, err := LoadProfileData(profile); err == nil {
		t.Fatal("required component disabled")
	}
}
