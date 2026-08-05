package trash

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/stoguard/stoguard/internal/safety"
)

// Move sends a path to the OS trash / recycle bin.
func Move(path string) error {
	safe, err := safety.ValidateForTrash(path)
	if err != nil {
		return err
	}
	return moveOS(safe)
}

func moveUnique(path, dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
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
