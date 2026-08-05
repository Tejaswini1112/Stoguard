package agenttools

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/stoguard/stoguard/internal/platform"
)

type Finding struct {
	ID           string     `json:"id"`
	Name         string     `json:"name"`
	Kind         string     `json:"kind"`
	Path         string     `json:"path"`
	SizeBytes    int64      `json:"sizeBytes"`
	Detail       string     `json:"detail"`
	LastActivity *time.Time `json:"lastActivity,omitempty"`
	StaleDays    *int       `json:"staleDays,omitempty"`
	IsStale      bool       `json:"isStale"`
}

func Scan() []Finding {
	home := platform.Home()
	var out []Finding
	out = append(out, mcpConfigs(home)...)
	out = append(out, skills(home)...)
	out = append(out, extensions(home)...)
	sort.Slice(out, func(i, j int) bool {
		if out[i].IsStale != out[j].IsStale {
			return out[i].IsStale
		}
		return out[i].SizeBytes > out[j].SizeBytes
	})
	if len(out) > 60 {
		out = out[:60]
	}
	return out
}

func mcpConfigs(home string) []Finding {
	candidates := []string{
		filepath.Join(home, ".cursor", "mcp.json"),
		filepath.Join(home, ".vscode", "mcp.json"),
		filepath.Join(home, ".mcp.json"),
		filepath.Join(home, ".config", "claude", "mcp.json"),
	}
	if runtime.GOOS == "darwin" {
		candidates = append(candidates,
			filepath.Join(home, "Library/Application Support/Claude/claude_desktop_config.json"),
			filepath.Join(home, "Library/Application Support/Cursor/User/globalStorage/cursor.mcp/mcp.json"),
		)
	}
	if runtime.GOOS == "windows" {
		candidates = append(candidates,
			filepath.Join(home, "AppData/Roaming/Cursor/User/globalStorage/cursor.mcp/mcp.json"),
			filepath.Join(home, "AppData/Roaming/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"),
		)
	}
	if runtime.GOOS == "linux" {
		candidates = append(candidates,
			filepath.Join(home, ".config/Cursor/User/globalStorage/cursor.mcp/mcp.json"),
			filepath.Join(home, ".config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"),
		)
	}
	var out []Finding
	for _, path := range candidates {
		if _, err := os.Stat(path); err != nil {
			continue
		}
		servers := mcpNames(path)
		name := filepath.Base(path)
		if len(servers) > 0 {
			name = strings.Join(servers, ", ")
		}
		out = append(out, stale(Finding{
			ID:        "mcp-" + path,
			Name:      name,
			Kind:      "MCP",
			Path:      path,
			SizeBytes: fileSize(path),
			Detail:    "MCP config — disable unused servers to reduce agent clutter.",
		}, path))
	}
	return out
}

func skills(home string) []Finding {
	roots := []string{
		filepath.Join(home, ".cursor", "skills"),
		filepath.Join(home, ".cursor", "skills-cursor"),
		filepath.Join(home, ".codex", "skills"),
		filepath.Join(home, ".claude", "skills"),
		filepath.Join(home, ".agents", "skills"),
	}
	var out []Finding
	for _, root := range roots {
		entries, err := os.ReadDir(root)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if strings.HasPrefix(e.Name(), ".") {
				continue
			}
			path := filepath.Join(root, e.Name())
			size := dirSize(path)
			out = append(out, stale(Finding{
				ID:        "skill-" + path,
				Name:      e.Name(),
				Kind:      "Skill",
				Path:      path,
				SizeBytes: size,
				Detail:    "AI skill / agent pack. Remove if outdated or unused.",
			}, path))
		}
	}
	return out
}

func extensions(home string) []Finding {
	type root struct {
		label string
		path  string
	}
	roots := []root{
		{"Cursor", filepath.Join(home, ".cursor", "extensions")},
		{"VS Code", filepath.Join(home, ".vscode", "extensions")},
	}
	if runtime.GOOS == "darwin" {
		// already covered via ~/.cursor
	}
	if runtime.GOOS == "windows" {
		roots = append(roots,
			root{"Cursor", filepath.Join(home, "AppData/Roaming/Cursor/extensions")},
			root{"VS Code", filepath.Join(home, "AppData/Roaming/Code/extensions")},
		)
	}
	if runtime.GOOS == "linux" {
		roots = append(roots,
			root{"VS Code", filepath.Join(home, ".config/Code/extensions")},
		)
	}
	var out []Finding
	for _, r := range roots {
		entries, err := os.ReadDir(r.path)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
				continue
			}
			path := filepath.Join(r.path, e.Name())
			size := dirSize(path)
			if size < 2_000_000 {
				continue
			}
			out = append(out, stale(Finding{
				ID:        "ext-" + r.label + "-" + e.Name(),
				Name:      e.Name(),
				Kind:      r.label + " extension",
				Path:      path,
				SizeBytes: size,
				Detail:    "Editor extension. Uninstall from " + r.label + " if idle.",
			}, path))
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SizeBytes > out[j].SizeBytes })
	if len(out) > 40 {
		out = out[:40]
	}
	return out
}

func mcpNames(path string) []string {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var obj map[string]any
	if err := json.Unmarshal(b, &obj); err != nil {
		return nil
	}
	for _, key := range []string{"mcpServers", "servers"} {
		if m, ok := obj[key].(map[string]any); ok {
			names := make([]string, 0, len(m))
			for k := range m {
				names = append(names, k)
			}
			sort.Strings(names)
			return names
		}
	}
	return nil
}

func stale(f Finding, path string) Finding {
	if info, err := os.Stat(path); err == nil {
		t := info.ModTime()
		f.LastActivity = &t
		days := int(time.Since(t).Hours() / 24)
		if days < 0 {
			days = 0
		}
		f.StaleDays = &days
		f.IsStale = days >= 60
		if f.IsStale {
			f.Detail = fmt.Sprintf("%s Idle ~%d days.", f.Detail, days)
		}
	}
	if f.SizeBytes <= 0 {
		f.SizeBytes = 1
	}
	return f
}

func fileSize(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 1
	}
	return info.Size()
}

func dirSize(root string) int64 {
	var total int64
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		total += info.Size()
		return nil
	})
	return total
}
