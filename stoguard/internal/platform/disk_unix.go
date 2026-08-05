//go:build !windows

package platform

import "syscall"

func diskUsage(path string) (free, total int64, err error) {
	var st syscall.Statfs_t
	if err = syscall.Statfs(path, &st); err != nil {
		return 0, 0, err
	}
	// Prefer Bavail (non-root free) when available.
	bsize := int64(st.Bsize)
	free = int64(st.Bavail) * bsize
	total = int64(st.Blocks) * bsize
	return free, total, nil
}
