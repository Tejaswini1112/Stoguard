//go:build darwin

package trash

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/stoguard/stoguard/internal/platform"
)

func moveOS(path string) error {
	// Prefer Finder so items appear in Trash with proper Put Back metadata.
	script := fmt.Sprintf(`tell application "Finder" to delete (POSIX file %q as alias)`, path)
	cmd := exec.Command("osascript", "-e", script)
	if out, err := cmd.CombinedOutput(); err == nil {
		return nil
	} else {
		// Fall back to ~/.Trash rename if AppleScript blocked.
		_ = out
		trash := filepath.Join(platform.Home(), ".Trash")
		if mkErr := os.MkdirAll(trash, 0o700); mkErr != nil {
			return fmt.Errorf("finder trash failed (%v) and ~/.Trash unavailable: %w", err, mkErr)
		}
		return moveUnique(path, trash)
	}
}
