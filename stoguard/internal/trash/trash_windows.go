//go:build windows

package trash

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/stoguard/stoguard/internal/platform"
)

func moveOSDetailed(path string) (osResult, error) {
	// Prefer silent VB Recycle Bin — do NOT use Shell InvokeVerb("delete"):
	// that can show interactive "Folder In Use" dialogs in the user's session.
	if err := sendToRecycleBinVB(path); err == nil {
		return osResult{Method: "recycle_bin"}, nil
	} else {
		vbErr := err
		if isSharingViolation(vbErr) || isSharingViolationMsg(vbErr.Error()) {
			return osResult{}, fmt.Errorf(
				"in use: close the app locking this path (Edge/Chrome/VS Code/Cursor), then Clean again — %v",
				vbErr,
			)
		}
		recycle := filepath.Join(platform.DataDir(), "Recycle")
		if mkErr := os.MkdirAll(recycle, 0o755); mkErr != nil {
			return osResult{}, fmt.Errorf("Recycle Bin failed (%v) and staging failed: %w", vbErr, mkErr)
		}
		if err := moveUnique(path, recycle); err != nil {
			if isSharingViolation(err) || isSharingViolationMsg(err.Error()) {
				return osResult{}, fmt.Errorf(
					"in use: close Edge/Chrome (or the app using GPUCache/Cache), then retry — %v",
					err,
				)
			}
			return osResult{}, fmt.Errorf("Recycle Bin failed (%v); staging failed: %w", vbErr, err)
		}
		return osResult{Method: "staging", Destination: recycle}, nil
	}
}

func isSharingViolation(err error) bool {
	if err == nil {
		return false
	}
	if errno, ok := err.(syscall.Errno); ok {
		// ERROR_SHARING_VIOLATION = 32, ERROR_LOCK_VIOLATION = 33
		return errno == 32 || errno == 33
	}
	return false
}

func isSharingViolationMsg(s string) bool {
	s = strings.ToLower(s)
	return strings.Contains(s, "sharing violation") ||
		strings.Contains(s, "being used by another") ||
		strings.Contains(s, "in use") ||
		strings.Contains(s, "access is denied")
}

func powershellExe() string {
	root := os.Getenv("SystemRoot")
	if root == "" {
		root = `C:\Windows`
	}
	candidate := filepath.Join(root, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
	if _, err := os.Stat(candidate); err == nil {
		return candidate
	}
	return "powershell.exe"
}

func runPowerShell(script string) (string, error) {
	cmd := exec.Command(
		powershellExe(),
		"-NoProfile",
		"-NonInteractive",
		"-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden",
		"-Command", script,
	)
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func sendToRecycleBinVB(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	escaped := strings.ReplaceAll(path, "'", "''")
	var ps string
	if info.IsDir() {
		ps = fmt.Sprintf(
			`$ErrorActionPreference='Stop'; Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('%s','OnlyErrorDialogs','SendToRecycleBin')`,
			escaped,
		)
	} else {
		ps = fmt.Sprintf(
			`$ErrorActionPreference='Stop'; Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('%s','OnlyErrorDialogs','SendToRecycleBin')`,
			escaped,
		)
	}
	out, err := runPowerShell(ps)
	if err != nil {
		return fmt.Errorf("powershell VB recycle: %w (%s)", err, out)
	}
	if _, err := os.Lstat(path); err == nil {
		return fmt.Errorf("path still exists after VB recycle (likely still in use)")
	}
	return nil
}
