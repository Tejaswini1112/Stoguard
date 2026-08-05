//go:build windows

package trash

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/stoguard/stoguard/internal/platform"
)

func moveOS(path string) error {
	if err := sendToRecycleBin(path); err == nil {
		return nil
	} else {
		// Fallback staging if PowerShell / VB is unavailable.
		recycle := filepath.Join(platform.DataDir(), "Recycle")
		if mkErr := os.MkdirAll(recycle, 0o755); mkErr != nil {
			return fmt.Errorf("recycle bin failed (%v) and staging failed: %w", err, mkErr)
		}
		return moveUnique(path, recycle)
	}
}

func sendToRecycleBin(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	escaped := strings.ReplaceAll(path, "'", "''")
	var ps string
	if info.IsDir() {
		ps = fmt.Sprintf(
			`Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('%s','OnlyErrorDialogs','SendToRecycleBin')`,
			escaped,
		)
	} else {
		ps = fmt.Sprintf(
			`Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('%s','OnlyErrorDialogs','SendToRecycleBin')`,
			escaped,
		)
	}
	cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", ps)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("powershell recycle: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	// Confirm original is gone
	if _, err := os.Lstat(path); err == nil {
		return fmt.Errorf("path still exists after recycle attempt")
	}
	return nil
}
