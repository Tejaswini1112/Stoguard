package fleet

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/stoguard/stoguard/internal/models"
	"github.com/stoguard/stoguard/internal/platform"
)

func dir() string {
	d := filepath.Join(platform.DataDir(), "fleet")
	_ = os.MkdirAll(d, 0o755)
	return d
}

// Ingest stores a fleet report from a machine.
func Ingest(report models.FleetReport) (models.FleetMachine, error) {
	if report.Hostname == "" {
		host, _ := os.Hostname()
		report.Hostname = host
	}
	if report.ScannedAt.IsZero() {
		report.ScannedAt = time.Now()
	}
	if report.Platform == "" {
		report.Platform = platform.OS()
	}

	safe := sanitize(report.Hostname)
	path := filepath.Join(dir(), safe+".json")
	b, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return models.FleetMachine{}, err
	}
	if err := os.WriteFile(path, b, 0o644); err != nil {
		return models.FleetMachine{}, err
	}
	return toMachine(report), nil
}

// List returns aggregated machines sorted by reclaimable desc.
func List() ([]models.FleetMachine, error) {
	entries, err := os.ReadDir(dir())
	if err != nil {
		if os.IsNotExist(err) {
			return []models.FleetMachine{}, nil
		}
		return nil, err
	}
	out := []models.FleetMachine{}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir(), e.Name()))
		if err != nil {
			continue
		}
		var report models.FleetReport
		if json.Unmarshal(b, &report) != nil {
			continue
		}
		out = append(out, toMachine(report))
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].Reclaimable > out[j].Reclaimable
	})
	return out, nil
}

// FromScan builds a fleet report from a local scan (for export / self-ingest).
func FromScan(result *models.ScanResult) models.FleetReport {
	host, _ := os.Hostname()
	tops := topCategories(result.CategoryTotals, 5)
	return models.FleetReport{
		Hostname:    host,
		Platform:    result.Platform,
		ScannedAt:   result.ScannedAt,
		Reclaimable: result.SafeBytes + result.CheckBytes,
		SafeBytes:   result.SafeBytes,
		CheckBytes:  result.CheckBytes,
		TotalBytes:  result.TotalBytes,
		FreeBytes:   result.FreeBytes,
		ItemCount:   len(result.Items),
		TopCategories: tops,
	}
}

func toMachine(r models.FleetReport) models.FleetMachine {
	return models.FleetMachine{
		Hostname:      r.Hostname,
		Platform:      r.Platform,
		ScannedAt:     r.ScannedAt,
		Reclaimable:   r.Reclaimable,
		SafeBytes:     r.SafeBytes,
		CheckBytes:    r.CheckBytes,
		TotalBytes:    r.TotalBytes,
		FreeBytes:     r.FreeBytes,
		ItemCount:     r.ItemCount,
		TopCategories: r.TopCategories,
	}
}

func topCategories(m map[string]int64, n int) []models.CategoryBytes {
	type kv struct {
		k string
		v int64
	}
	list := make([]kv, 0, len(m))
	for k, v := range m {
		list = append(list, kv{k, v})
	}
	sort.Slice(list, func(i, j int) bool { return list[i].v > list[j].v })
	if len(list) > n {
		list = list[:n]
	}
	out := make([]models.CategoryBytes, 0, len(list))
	for _, x := range list {
		out = append(out, models.CategoryBytes{Category: x.k, Bytes: x.v})
	}
	return out
}

func sanitize(s string) string {
	s = strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' || r == '.' {
			return r
		}
		return '_'
	}, s)
	if s == "" {
		return "unknown"
	}
	return s
}
