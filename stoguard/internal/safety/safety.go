package safety

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/stoguard/stoguard/internal/platform"
)

var (
	ErrMissing        = errors.New("path no longer exists")
	ErrOutsideHome    = errors.New("path resolves outside your home folder")
	ErrSymlinkEscape  = errors.New("symlink points outside the intended location")
	ErrDisallowedRoot = errors.New("refusing to trash a protected system location")
)

func blockedPrefixes() []string {
	switch runtime.GOOS {
	case "windows":
		return []string{
			`C:\Windows`,
			`C:\Program Files`,
			`C:\Program Files (x86)`,
		}
	default:
		return []string{
			"/System", "/usr", "/bin", "/sbin", "/Library",
			"/private/var/db", "/private/etc", "/boot", "/etc",
		}
	}
}

func under(parent, candidate string) bool {
	parent = filepath.Clean(parent)
	candidate = filepath.Clean(candidate)
	if parent == candidate {
		return true
	}
	sep := string(os.PathSeparator)
	return strings.HasPrefix(candidate, parent+sep)
}

// ValidateForTrash ensures path is under home (or allowed roots) and symlinks do not escape.
func ValidateForTrash(path string) (string, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return "", ErrMissing
	}

	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	abs = filepath.Clean(abs)

	resolved := abs
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := filepath.EvalSymlinks(abs)
		if err != nil {
			return "", ErrSymlinkEscape
		}
		resolved = filepath.Clean(target)
	} else {
		if t, err := filepath.EvalSymlinks(abs); err == nil {
			resolved = filepath.Clean(t)
		}
	}

	home := filepath.Clean(platform.Home())
	if !under(home, abs) {
		return "", ErrOutsideHome
	}
	if !under(home, resolved) {
		return "", ErrSymlinkEscape
	}

	for _, blocked := range blockedPrefixes() {
		b := filepath.Clean(blocked)
		if under(b, resolved) || resolved == b {
			return "", ErrDisallowedRoot
		}
	}
	return abs, nil
}
