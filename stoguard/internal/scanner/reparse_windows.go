//go:build windows

package scanner

import (
	"os"
	"syscall"
)

// isReparseDir skips NTFS junctions / mount points that otherwise recurse forever
// (common under AppData\\Local\\Packages and Docker Desktop).
func isReparseDir(path string, d os.DirEntry) bool {
	if !d.IsDir() {
		return false
	}
	info, err := d.Info()
	if err != nil {
		return false
	}
	stat, ok := info.Sys().(*syscall.Win32FileAttributeData)
	if !ok {
		return false
	}
	const fileAttributeReparsePoint = 0x400
	return stat.FileAttributes&fileAttributeReparsePoint != 0
}
