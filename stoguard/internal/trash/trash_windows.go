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

func moveOSDetailed(path string) (osResult, error) {
	if err := sendToRecycleBinVB(path); err == nil {
		return osResult{Method: "recycle_bin"}, nil
	} else {
		vbErr := err
		if err := sendToRecycleBinShell(path); err == nil {
			return osResult{Method: "recycle_bin"}, nil
		} else {
			shellErr := err
			recycle := filepath.Join(platform.DataDir(), "Recycle")
			if mkErr := os.MkdirAll(recycle, 0o755); mkErr != nil {
				return osResult{}, fmt.Errorf("Recycle Bin failed (%v; %v) and staging failed: %w", vbErr, shellErr, mkErr)
			}
			if err := moveUnique(path, recycle); err != nil {
				return osResult{}, fmt.Errorf("Recycle Bin failed (%v; %v); staging failed: %w", vbErr, shellErr, err)
			}
			return osResult{Method: "staging", Destination: recycle}, nil
		}
	}
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
			`Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('%s','OnlyErrorDialogs','SendToRecycleBin')`,
			escaped,
		)
	} else {
		ps = fmt.Sprintf(
			`Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('%s','OnlyErrorDialogs','SendToRecycleBin')`,
			escaped,
		)
	}
	out, err := runPowerShell(ps)
	if err != nil {
		return fmt.Errorf("powershell VB recycle: %w (%s)", err, out)
	}
	if _, err := os.Lstat(path); err == nil {
		return fmt.Errorf("path still exists after VB recycle")
	}
	return nil
}

func sendToRecycleBinShell(path string) error {
	escaped := strings.ReplaceAll(path, "'", "''")
	ps := fmt.Sprintf(`
$ErrorActionPreference = 'Stop'
$p = '%s'
if (-not (Test-Path -LiteralPath $p)) { throw 'missing' }
$shell = New-Object -ComObject Shell.Application
$dir = Split-Path -Parent $p
$name = Split-Path -Leaf $p
$item = $shell.NameSpace($dir).ParseName($name)
if ($null -eq $item) { throw 'parse failed' }
$item.InvokeVerb('delete')
Start-Sleep -Milliseconds 500
if (Test-Path -LiteralPath $p) { throw 'still exists' }
`, escaped)
	out, err := runPowerShell(ps)
	if err != nil {
		return fmt.Errorf("shell recycle: %w (%s)", err, out)
	}
	if _, err := os.Lstat(path); err == nil {
		return fmt.Errorf("path still exists after shell recycle")
	}
	return nil
}
