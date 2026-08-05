package platform

import (
	"os"
	"os/user"
	"runtime"
	"time"
)

// SystemInfo is a full workstation snapshot for the Engine / status panel.
type SystemInfo struct {
	Hostname       string  `json:"hostname"`
	Username       string  `json:"username"`
	Home           string  `json:"home"`
	DataDir        string  `json:"dataDir"`
	Platform       string  `json:"platform"`
	OS             string  `json:"os"`
	Arch           string  `json:"arch"`
	GoVersion      string  `json:"goVersion"`
	NumCPU         int     `json:"numCPU"`
	Goroutines     int     `json:"goroutines"`
	MemAllocBytes  uint64  `json:"memAllocBytes"`
	MemSysBytes    uint64  `json:"memSysBytes"`
	DiskFreeBytes  int64   `json:"diskFreeBytes"`
	DiskTotalBytes int64   `json:"diskTotalBytes"`
	DiskUsedPct    float64 `json:"diskUsedPercent"`
	UptimeSeconds  int64   `json:"uptimeSeconds,omitempty"`
	CollectedAt    string  `json:"collectedAt"`
}

var processStart = time.Now()

func CollectSystem() SystemInfo {
	host, _ := os.Hostname()
	uname := ""
	if u, err := user.Current(); err == nil {
		uname = u.Username
		if uname == "" {
			uname = u.Name
		}
	}
	free, total, _ := DiskUsage(Home())
	var usedPct float64
	if total > 0 {
		usedPct = float64(total-free) / float64(total) * 100
	}
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)

	return SystemInfo{
		Hostname:       host,
		Username:       uname,
		Home:           Home(),
		DataDir:        DataDir(),
		Platform:       OS(),
		OS:             runtime.GOOS,
		Arch:           runtime.GOARCH,
		GoVersion:      runtime.Version(),
		NumCPU:         runtime.NumCPU(),
		Goroutines:     runtime.NumGoroutine(),
		MemAllocBytes:  ms.Alloc,
		MemSysBytes:    ms.Sys,
		DiskFreeBytes:  free,
		DiskTotalBytes: total,
		DiskUsedPct:    usedPct,
		UptimeSeconds:  int64(time.Since(processStart).Seconds()),
		CollectedAt:    time.Now().Format(time.RFC3339),
	}
}
