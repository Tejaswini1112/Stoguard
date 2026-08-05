//go:build linux || freebsd || openbsd || netbsd || dragonfly

package trash

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/stoguard/stoguard/internal/platform"
)

func moveOS(path string) error {
	// Prefer desktop trash helpers when present.
	for _, helper := range [][]string{
		{"gio", "trash", path},
		{"trash-put", path},
		{"trash", path},
	} {
		if _, err := exec.LookPath(helper[0]); err != nil {
			continue
		}
		cmd := exec.Command(helper[0], helper[1:]...)
		if err := cmd.Run(); err == nil {
			if _, statErr := os.Lstat(path); statErr != nil {
				return nil
			}
		}
	}
	return moveFreeDesktop(path)
}

func moveFreeDesktop(path string) error {
	home := platform.Home()
	trashFiles := filepath.Join(home, ".local", "share", "Trash", "files")
	trashInfo := filepath.Join(home, ".local", "share", "Trash", "info")
	if err := os.MkdirAll(trashFiles, 0o700); err != nil {
		return err
	}
	_ = os.MkdirAll(trashInfo, 0o700)

	dest := uniqueName(trashFiles, filepath.Base(path))
	infoPath := filepath.Join(trashInfo, filepath.Base(dest)+".trashinfo")
	content := fmt.Sprintf("[Trash Info]\nPath=%s\nDeletionDate=%s\n",
		path, time.Now().Format("2006-01-02T15:04:05"))
	if err := os.WriteFile(infoPath, []byte(content), 0o600); err != nil {
		return err
	}
	if err := os.Rename(path, dest); err != nil {
		// Cross-device: copy+remove
		return fmt.Errorf("move to trash: %w", err)
	}
	return nil
}
