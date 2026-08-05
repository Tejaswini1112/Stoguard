package platform

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

func OS() string {
	switch runtime.GOOS {
	case "darwin":
		return "macos"
	case "windows":
		return "windows"
	case "linux":
		return "linux"
	default:
		return runtime.GOOS
	}
}

func Home() string {
	h, err := os.UserHomeDir()
	if err != nil || h == "" {
		return os.Getenv("HOME")
	}
	return h
}

func DataDir() string {
	home := Home()
	switch runtime.GOOS {
	case "darwin":
		return filepath.Join(home, "Library", "Application Support", "Stoguard")
	case "windows":
		if base := os.Getenv("APPDATA"); base != "" {
			return filepath.Join(base, "Stoguard")
		}
		return filepath.Join(home, "AppData", "Roaming", "Stoguard")
	default:
		if xdg := os.Getenv("XDG_DATA_HOME"); xdg != "" {
			return filepath.Join(xdg, "stoguard")
		}
		return filepath.Join(home, ".local", "share", "stoguard")
	}
}

func EnsureDataDir() error {
	return os.MkdirAll(DataDir(), 0o755)
}

func ExpandPath(p string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return p
	}
	home := Home()
	if p == "~" {
		return home
	}
	if strings.HasPrefix(p, "~/") || strings.HasPrefix(p, "~\\") {
		return filepath.Join(home, p[2:])
	}
	// Windows-style ~\AppData\...
	if strings.HasPrefix(p, `~\`) {
		return filepath.Join(home, p[2:])
	}
	if runtime.GOOS == "windows" {
		p = os.ExpandEnv(p)
	}
	return filepath.Clean(p)
}

func DiskUsage(path string) (free, total int64, err error) {
	return diskUsage(path)
}
