//go:build !windows

package scanner

import "os"

func isReparseDir(path string, d os.DirEntry) bool {
	return false
}
