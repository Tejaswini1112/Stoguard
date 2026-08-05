//go:build windows

package platform

import (
	"syscall"
	"unsafe"
)

var (
	modkernel32            = syscall.NewLazyDLL("kernel32.dll")
	procGetDiskFreeSpaceEx = modkernel32.NewProc("GetDiskFreeSpaceExW")
)

func diskUsage(path string) (free, total int64, err error) {
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return 0, 0, err
	}
	var freeBytes, totalBytes, totalFree uint64
	r1, _, e := procGetDiskFreeSpaceEx.Call(
		uintptr(unsafe.Pointer(p)),
		uintptr(unsafe.Pointer(&freeBytes)),
		uintptr(unsafe.Pointer(&totalBytes)),
		uintptr(unsafe.Pointer(&totalFree)),
	)
	if r1 == 0 {
		if e != nil {
			return 0, 0, e
		}
		return 0, 0, syscall.EINVAL
	}
	return int64(freeBytes), int64(totalBytes), nil
}
