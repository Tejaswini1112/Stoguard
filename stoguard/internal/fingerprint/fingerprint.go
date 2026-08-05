package fingerprint

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/stoguard/stoguard/internal/platform"
)

type Entry struct {
	SizeBytes  int64   `json:"sizeBytes"`
	Mtime      int64   `json:"mtime"`
	SizeHint   int64   `json:"sizeHint"`
	UpdatedAt  float64 `json:"updatedAt"`
}

type Cache struct {
	Entries map[string]Entry `json:"entries"`
	mu      sync.Mutex
}

func filePath() string {
	return filepath.Join(platform.DataDir(), "scan-cache.json")
}

func Load() *Cache {
	c := &Cache{Entries: map[string]Entry{}}
	data, err := os.ReadFile(filePath())
	if err != nil {
		return c
	}
	_ = json.Unmarshal(data, c)
	if c.Entries == nil {
		c.Entries = map[string]Entry{}
	}
	return c
}

func (c *Cache) Save() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if err := platform.EnsureDataDir(); err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filePath(), data, 0o600)
}

func liveMtime(path string) (int64, int64, bool) {
	info, err := os.Lstat(path)
	if err != nil {
		return 0, 0, false
	}
	mtime := info.ModTime().UnixNano()
	size := info.Size()
	return mtime, size, true
}

func (c *Cache) CachedSize(ruleID, path string) (int64, bool) {
	mtime, sizeHint, ok := liveMtime(path)
	if !ok {
		return 0, false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.Entries[ruleID]
	if !ok || e.Mtime != mtime || e.SizeHint != sizeHint {
		return 0, false
	}
	return e.SizeBytes, true
}

func (c *Cache) Store(ruleID, path string, sizeBytes int64) {
	mtime, sizeHint, ok := liveMtime(path)
	if !ok {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.Entries[ruleID] = Entry{
		SizeBytes: sizeBytes,
		Mtime:     mtime,
		SizeHint:  sizeHint,
		UpdatedAt: float64(time.Now().Unix()),
	}
}
