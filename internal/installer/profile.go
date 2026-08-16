package installer

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type Profile struct {
	Components map[string]bool `json:"components"`
}

var legacyComponentIDs = map[string][]string{
	"communication": {
		"communication-discord",
		"communication-telegram",
		"communication-whatsapp",
		"communication-slack",
	},
	"desktop": {
		"desktop-chrome",
		"desktop-firefox",
		"desktop-brave",
		"communication-discord",
		"communication-telegram",
		"communication-whatsapp",
		"communication-slack",
		"desktop-raycast",
		"desktop-finetune",
		"desktop-typewhisper",
		"desktop-rectangle",
		"desktop-aerospace",
		"desktop-linearmouse",
		"desktop-localsend",
	},
	"media": {
		"media-tools",
		"media-spotify",
		"media-stremio",
		"media-vlc",
		"media-castor",
	},
	"databases": {
		"service-mysql",
		"service-postgresql",
		"service-redis",
		"service-sqlite",
	},
}

func DefaultProfile() Profile {
	components := make(map[string]bool)
	for _, component := range Components() {
		components[component.ID] = component.Default || component.Required
	}
	return Profile{Components: components}
}

func LoadProfile(path string) (Profile, error) {
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return DefaultProfile(), nil
	}
	if err != nil {
		return Profile{}, err
	}
	var profile Profile
	if err := json.Unmarshal(data, &profile); err != nil {
		return Profile{}, fmt.Errorf("invalid profile: %w", err)
	}
	if profile.Components == nil {
		return Profile{}, fmt.Errorf("invalid profile: components is required")
	}
	profile, migrated, err := MigrateProfileData(profile)
	if err != nil {
		return Profile{}, err
	}
	ids := componentIDs()
	for id := range profile.Components {
		if !ids[id] {
			return Profile{}, fmt.Errorf("invalid profile: unknown component %q", id)
		}
	}
	for id := range ids {
		if _, ok := profile.Components[id]; !ok {
			profile.Components[id] = false
		}
	}
	for _, component := range Components() {
		if component.Required {
			profile.Components[component.ID] = true
		}
	}
	if migrated {
		if err := SaveProfile(path, profile); err != nil {
			return Profile{}, err
		}
	}
	return profile, nil
}

func MigrateProfileData(profile Profile) (Profile, bool, error) {
	if profile.Components == nil {
		return Profile{}, false, fmt.Errorf("invalid profile: components is required")
	}
	changed := false
	for legacyID, componentIDs := range legacyComponentIDs {
		enabled, ok := profile.Components[legacyID]
		if !ok {
			continue
		}
		if enabled {
			for _, componentID := range componentIDs {
				profile.Components[componentID] = true
			}
		}
		delete(profile.Components, legacyID)
		changed = true
	}
	return profile, changed, nil
}

func SaveProfile(path string, profile Profile) error {
	if _, err := LoadProfileData(profile); err != nil {
		return err
	}
	data, err := json.MarshalIndent(profile, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".profile-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(append(data, '\n')); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}

func LoadProfileData(profile Profile) (Profile, error) {
	ids := componentIDs()
	for id := range profile.Components {
		if !ids[id] {
			return Profile{}, fmt.Errorf("invalid profile: unknown component %q", id)
		}
	}
	for _, component := range Components() {
		if component.Required && !profile.Components[component.ID] {
			return Profile{}, fmt.Errorf("invalid profile: required component %q is disabled", component.ID)
		}
	}
	return profile, nil
}
