package trash

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"github.com/stoguard/stoguard/internal/platform"
	"github.com/stoguard/stoguard/internal/safety"
)

// Move sends a path to the OS trash / recycle bin when possible.
func Move(path string) error {
	safe, err := safety.ValidateForTrash(path)
	if err != nil {
		return err
	}
	switch runtime.GOOS {
	case "darwin":
		return moveMac(safe)
	case "windows":
		return moveWindows(safe)
	default:
		return moveLinux(safe)
	}
}

func moveMac(path string) error {
	trash := filepath.Join(platform.Home(), ".Trash")
	if err := os.MkdirAll(trash, 0o700); err != nil {
		return err
	}
	return moveUnique(path, trash)
}

func moveLinux(path string) error {
	home := platform.Home()
	trashFiles := filepath.Join(home, ".local", "share", "Trash", "files")
	trashInfo := filepath.Join(home, ".local", "share", "Trash", "info")
	if err := os.MkdirAll(trashFiles, 0o700); err != nil {
		return err
	}
	_ = os.MkdirAll(trashInfo, 0o700)

	base := filepath.Base(path)
	dest := uniqueName(trashFiles, base)
	infoPath := filepath.Join(trashInfo, filepath.Base(dest)+".trashinfo")
	content := fmt.Sprintf("[Trash Info]\nPath=%s\nDeletionDate=%s\n",
		path, time.Now().Format("2006-01-02T15:04:05"))
	if err := os.WriteFile(infoPath, []byte(content), 0o600); err != nil {
		return err
	}
	return os.Rename(path, dest)
}

func moveWindows(path string) error {
	// Soft fallback: move into a Stoguard recycle staging folder under the user profile.
	// Full Recycle Bin COM integration can replace this later.
	recycle := filepath.Join(platform.DataDir(), "Recycle")
	if err := os.MkdirAll(recycle, 0o755); err != nil {
		return err
	}
	return moveUnique(path, recycle)
}

func moveUnique(path, dir string) error {
	dest := uniqueName(dir, filepath.Base(path))
	return os.Rename(path, dest)
}

func uniqueName(dir, base string) string {
	dest := filepath.Join(dir, base)
	if _, err := os.Lstat(dest); err != nil {
		return dest
	}
	ext := filepath.Ext(base)
	name := base[:len(base)-len(ext)]
	for i := 1; i < 1000; i++ {
		candidate := filepath.Join(dir, fmt.Sprintf("%s %d%s", name, i, ext))
		if _, err := os.Lstat(candidate); err != nil {
			return candidate
		}
	}
	return filepath.Join(dir, fmt.Sprintf("%s-%d%s", name, time.Now().UnixNano(), ext))
}
