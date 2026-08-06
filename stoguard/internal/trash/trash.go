package trash

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/stoguard/stoguard/internal/safety"
)

// MoveResult is returned to the API so the UI can explain Recycle vs staging.
type MoveResult struct {
	Method      string `json:"method"`
	Destination string `json:"destination,omitempty"`
	Path        string `json:"path"`
}

type osResult struct {
	Method      string
	Destination string
}

// Move sends a path to the OS trash / recycle bin.
func Move(path string) error {
	_, err := MoveDetailed(path)
	return err
}

// MoveDetailed returns where the item went (recycle bin vs staging folder).
func MoveDetailed(path string) (MoveResult, error) {
	safe, err := safety.ValidateForTrash(path)
	if err != nil {
		return MoveResult{}, err
	}
	res, err := moveOSDetailed(safe)
	if err != nil {
		return MoveResult{}, err
	}
	return MoveResult{Method: res.Method, Destination: res.Destination, Path: safe}, nil
}

func moveUnique(path, dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	dest := uniqueName(dir, filepath.Base(path))
	if err := os.Rename(path, dest); err == nil {
		return nil
	} else {
		if copyErr := copyRecursive(path, dest); copyErr != nil {
			_ = os.RemoveAll(dest)
			return fmt.Errorf("rename failed (%v); copy failed: %w", err, copyErr)
		}
		if remErr := os.RemoveAll(path); remErr != nil {
			return fmt.Errorf("staged copy ok but remove source failed: %w", remErr)
		}
		return nil
	}
}

func copyRecursive(src, dst string) error {
	info, err := os.Lstat(src)
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := os.Readlink(src)
		if err != nil {
			return err
		}
		return os.Symlink(target, dst)
	}
	if info.IsDir() {
		if err := os.MkdirAll(dst, info.Mode().Perm()); err != nil {
			return err
		}
		entries, err := os.ReadDir(src)
		if err != nil {
			return err
		}
		for _, e := range entries {
			if err := copyRecursive(filepath.Join(src, e.Name()), filepath.Join(dst, e.Name())); err != nil {
				return err
			}
		}
		return nil
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, info.Mode().Perm())
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
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
