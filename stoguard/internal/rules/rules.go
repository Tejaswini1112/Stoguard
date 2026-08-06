package rules

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	"github.com/stoguard/stoguard/internal/models"
	"github.com/stoguard/stoguard/internal/platform"
)

// LoadAll loads common + OS-specific bundled rules and user plugins.
func LoadAll(rulesDir string) ([]models.Rule, error) {
	osName := platform.OS()
	byID := map[string]models.Rule{}

	for _, name := range []string{"common.json", osName + ".json"} {
		path := filepath.Join(rulesDir, name)
		list, err := loadRuleFile(path)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return nil, err
		}
		for _, r := range list {
			byID[r.ID] = r
		}
	}

	pluginDir := filepath.Join(rulesDir, "plugins")
	userPluginDir := filepath.Join(platform.DataDir(), "Plugins")
	// Also pick up repo-style packs checked out next to the binary when developing.
	repoPlugins := filepath.Join(filepath.Dir(rulesDir), "..", "plugins")
	for _, dir := range []string{pluginDir, userPluginDir, repoPlugins} {
		_ = filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() || !strings.HasSuffix(d.Name(), ".json") {
				return nil
			}
			plugin, err := loadPlugin(path)
			if err != nil || !pluginMatches(plugin, osName) {
				return nil
			}
			for _, r := range plugin.Rules {
				byID[r.ID] = r
			}
			return nil
		})
	}

	out := make([]models.Rule, 0, len(byID))
	for _, r := range byID {
		out = append(out, r)
	}
	return out, nil
}

func loadRuleFile(path string) ([]models.Rule, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var list []models.Rule
	if err := json.Unmarshal(data, &list); err != nil {
		return nil, err
	}
	return list, nil
}

func loadPlugin(path string) (models.Plugin, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return models.Plugin{}, err
	}
	var p models.Plugin
	if err := json.Unmarshal(data, &p); err != nil {
		return models.Plugin{}, err
	}
	return p, nil
}

func pluginMatches(p models.Plugin, osName string) bool {
	if len(p.Platforms) == 0 {
		return true
	}
	for _, plat := range p.Platforms {
		plat = strings.ToLower(plat)
		if plat == "any" || plat == osName || (plat == "darwin" && osName == "macos") {
			return true
		}
	}
	return false
}
