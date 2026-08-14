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
	return profile, nil
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
