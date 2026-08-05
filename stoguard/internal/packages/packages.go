package packages

import (
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
	Source       string     `json:"source"`
	Path         string     `json:"path"`
	SizeBytes    int64      `json:"sizeBytes"`
	Definition   string     `json:"definition"`
	Detail       string     `json:"detail"`
	LastActivity *time.Time `json:"lastActivity,omitempty"`
	DaysIdle     *int       `json:"daysIdle,omitempty"`
}

func Scan() []Finding {
	var out []Finding
	home := platform.Home()
	switch runtime.GOOS {
	case "darwin":
		out = append(out, brewCellar("/opt/homebrew/Cellar")...)
		out = append(out, brewCellar("/usr/local/Cellar")...)
		out = append(out, npmGlobals("/opt/homebrew/lib/node_modules")...)
		out = append(out, npmGlobals("/usr/local/lib/node_modules")...)
	case "linux", "freebsd":
		out = append(out, brewCellar(filepath.Join(home, "homebrew/Cellar"))...)
		out = append(out, brewCellar("/home/linuxbrew/.linuxbrew/Cellar")...)
		out = append(out, npmGlobals("/usr/lib/node_modules")...)
		out = append(out, npmGlobals(filepath.Join(home, ".npm-global/lib/node_modules"))...)
	case "windows":
		out = append(out, npmGlobals(filepath.Join(home, "AppData/Roaming/npm/node_modules"))...)
		out = append(out, dirPackages(filepath.Join(home, "AppData/Local/Programs"), "Windows Programs", 5_000_000)...)
	}
	out = append(out, npmGlobals(filepath.Join(home, ".local/lib/node_modules"))...)
	out = append(out, pipx(filepath.Join(home, ".local/share/pipx/venvs"))...)
	out = append(out, cargoBins(filepath.Join(home, ".cargo/bin"))...)
	out = append(out, userBins(filepath.Join(home, ".local/bin"))...)

	sort.Slice(out, func(i, j int) bool { return out[i].SizeBytes > out[j].SizeBytes })
	if len(out) > 80 {
		out = out[:80]
	}
	return out
}

func brewCellar(root string) []Finding {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []Finding
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		formula := e.Name()
		vers, _ := os.ReadDir(filepath.Join(root, formula))
		for _, v := range vers {
			if !v.IsDir() {
				continue
			}
			path := filepath.Join(root, formula, v.Name())
			size := dirSize(path)
			if size < 1_000_000 {
				continue
			}
			out = append(out, withIdle(Finding{
				ID:        "brew-" + formula + "-" + v.Name(),
				Name:      formula,
				Source:    "Homebrew",
				Path:      path,
				SizeBytes: size,
				Detail:    "Cellar " + v.Name() + ". Uninstall with brew uninstall " + formula + " if unused.",
			}, path))
		}
	}
	return out
}

func npmGlobals(root string) []Finding {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []Finding
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, ".") || name == "npm" || name == "corepack" {
			continue
		}
		path := filepath.Join(root, name)
		size := dirSize(path)
		if size < 500_000 {
			continue
		}
		out = append(out, withIdle(Finding{
			ID:        "npm-" + name + "-" + path,
			Name:      name,
			Source:    "npm global",
			Path:      path,
			SizeBytes: size,
			Detail:    "Global npm package. Remove with npm uninstall -g " + name + " if unused.",
		}, path))
	}
	return out
}

func pipx(root string) []Finding {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []Finding
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		path := filepath.Join(root, e.Name())
		size := dirSize(path)
		if size < 1_000_000 {
			continue
		}
		out = append(out, withIdle(Finding{
			ID:        "pipx-" + e.Name(),
			Name:      e.Name(),
			Source:    "pipx",
			Path:      path,
			SizeBytes: size,
			Detail:    "pipx env. Remove with pipx uninstall " + e.Name() + " if unused.",
		}, path))
	}
	return out
}

func cargoBins(root string) []Finding {
	return binaries(root, "Cargo bin", 500_000)
}

func userBins(root string) []Finding {
	return binaries(root, "User bin", 500_000)
}

func binaries(root, source string, min int64) []Finding {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []Finding
	for _, e := range entries {
		if e.Type()&os.ModeSymlink != 0 {
			continue
		}
		path := filepath.Join(root, e.Name())
		info, err := e.Info()
		if err != nil || info.IsDir() {
			continue
		}
		if info.Size() < min {
			continue
		}
		out = append(out, withIdle(Finding{
			ID:        "bin-" + source + "-" + e.Name(),
			Name:      e.Name(),
			Source:    source,
			Path:      path,
			SizeBytes: info.Size(),
			Detail:    "Executable on PATH. Confirm you still use " + e.Name() + " before removing.",
		}, path))
	}
	return out
}

func dirPackages(root, source string, min int64) []Finding {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []Finding
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		path := filepath.Join(root, e.Name())
		size := dirSize(path)
		if size < min {
			continue
		}
		out = append(out, withIdle(Finding{
			ID:        "prog-" + e.Name(),
			Name:      e.Name(),
			Source:    source,
			Path:      path,
			SizeBytes: size,
			Detail:    "Installed under Local\\Programs. Uninstall via Settings if unused.",
		}, path))
	}
	return out
}

func withIdle(f Finding, path string) Finding {
	if f.Definition == "" {
		f.Definition = Definition(f.Name, f.Source)
	}
	if info, err := os.Stat(path); err == nil {
		t := info.ModTime()
		f.LastActivity = &t
		days := int(time.Since(t).Hours() / 24)
		if days < 0 {
			days = 0
		}
		f.DaysIdle = &days
	}
	return f
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
