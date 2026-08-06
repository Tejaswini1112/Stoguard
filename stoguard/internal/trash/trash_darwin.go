//go:build darwin

package trash

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/stoguard/stoguard/internal/platform"
)

func moveOSDetailed(path string) (osResult, error) {
	script := fmt.Sprintf(`tell application "Finder" to delete (POSIX file %q as alias)`, path)
	cmd := exec.Command("osascript", "-e", script)
	if _, err := cmd.CombinedOutput(); err == nil {
		return osResult{Method: "trash"}, nil
	} else {
		trashDir := filepath.Join(platform.Home(), ".Trash")
		if mkErr := os.MkdirAll(trashDir, 0o700); mkErr != nil {
			return osResult{}, fmt.Errorf("finder trash failed (%v) and ~/.Trash unavailable: %w", err, mkErr)
		}
		if err := moveUnique(path, trashDir); err != nil {
			return osResult{}, err
		}
		return osResult{Method: "staging", Destination: trashDir}, nil
	}
}
