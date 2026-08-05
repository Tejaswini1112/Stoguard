package history

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"

	"github.com/stoguard/stoguard/internal/models"
	"github.com/stoguard/stoguard/internal/platform"
)

type Store struct {
	Entries []models.HistoryEntry `json:"entries"`
}

func filePath() string {
	return filepath.Join(platform.DataDir(), "scan-history.json")
}

func Load() *Store {
	s := &Store{}
	data, err := os.ReadFile(filePath())
	if err != nil {
		return s
	}
	_ = json.Unmarshal(data, s)
	return s
}

func (s *Store) Append(entry models.HistoryEntry) error {
	s.Entries = append(s.Entries, entry)
	if len(s.Entries) > 60 {
		s.Entries = s.Entries[len(s.Entries)-60:]
	}
	return s.Save()
}

func (s *Store) Save() error {
	if err := platform.EnsureDataDir(); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filePath(), data, 0o600)
}

func FromScan(result *models.ScanResult) models.HistoryEntry {
	top := make([]string, 0, 8)
	for i, it := range result.Items {
		if i >= 8 {
			break
		}
		top = append(top, it.ID)
	}
	return models.HistoryEntry{
		Date:            time.Now(),
		FreeBytes:       result.FreeBytes,
		TotalBytes:      result.DiskTotalBytes,
		ReclaimableSafe: result.SafeBytes,
		CategoryTotals:  result.CategoryTotals,
		TopItemIDs:      top,
	}
}
