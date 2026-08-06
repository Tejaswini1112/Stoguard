package fleet

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
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

// Ingest stores a fleet report from a machine (schema v2 compatible with Swift EnterpriseReport).
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
	if report.MachineID == "" {
		report.MachineID = report.Hostname
	}
	if report.SchemaVersion == "" {
		report.SchemaVersion = "2.0"
	}
	if report.Arch == "" {
		report.Arch = runtime.GOARCH
	}

	safe := sanitize(report.MachineID)
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

// Delete removes a machine by id/hostname filename.
func Delete(machineID string) error {
	path := filepath.Join(dir(), sanitize(machineID)+".json")
	return os.Remove(path)
}

// Summary aggregates fleet health for the Team console.
func Summary() (models.FleetSummary, error) {
	list, err := List()
	if err != nil {
		return models.FleetSummary{}, err
	}
	sum := models.FleetSummary{
		MachineCount: len(list),
		Platforms:    map[string]int{},
	}
	var healthSum, healthN int
	for _, m := range list {
		sum.TotalReclaimable += m.Reclaimable
		sum.Platforms[m.Platform]++
		if m.Compliance != nil && m.Compliance.Score < 80 {
			sum.NonCompliant++
		}
		if m.HealthScore != nil {
			healthSum += *m.HealthScore
			healthN++
		}
	}
	if healthN > 0 {
		avg := healthSum / healthN
		sum.AvgHealth = &avg
	}
	return sum, nil
}

// FromScan builds a fleet report from a local scan (for export / self-ingest).
func FromScan(result *models.ScanResult) models.FleetReport {
	host, _ := os.Hostname()
	tops := topCategories(result.CategoryTotals, 8)
	safe := result.SafeBytes
	check := result.CheckBytes
	cohort := CohortMetrics(result)
	comp := EvaluateCompliance(result, 0)
	return models.FleetReport{
		SchemaVersion: "2.0",
		MachineID:     host,
		Hostname:      host,
		Platform:      result.Platform,
		Arch:          runtime.GOARCH,
		AppVersion:    "0.4.2",
		ScannedAt:     result.ScannedAt,
		Reclaimable:   safe + check,
		SafeBytes:     safe,
		CheckBytes:    check,
		TotalBytes:    result.DiskTotalBytes,
		FreeBytes:     result.FreeBytes,
		ItemCount:     len(result.Items),
		TopCategories: tops,
		CohortMetrics: cohort,
		Compliance:    &comp,
	}
}

// EvaluateCompliance scores a machine against the developer baseline.
func EvaluateCompliance(result *models.ScanResult, envWarns int) models.ComplianceSnapshot {
	passed := []string{}
	failed := []string{}
	if result != nil && result.DiskTotalBytes > 0 {
		used := float64(result.DiskTotalBytes-result.FreeBytes) / float64(result.DiskTotalBytes) * 100
		if used < 90 {
			passed = append(passed, "Disk under 90% used")
		} else {
			failed = append(failed, "Disk over 90% full")
		}
	}
	if result != nil && result.SafeBytes < 20_000_000_000 {
		passed = append(passed, "Safe reclaimable under 20 GB")
	} else if result != nil {
		failed = append(failed, "Safe reclaimable exceeds 20 GB policy")
	}
	if envWarns == 0 {
		passed = append(passed, "No env warnings reported")
	} else {
		failed = append(failed, "Env warnings present")
	}
	total := len(passed) + len(failed)
	score := 100
	if total > 0 {
		score = len(passed) * 100 / total
	}
	return models.ComplianceSnapshot{
		Score:    score,
		Passed:   passed,
		Failed:   failed,
		Baseline: "Stoguard Developer Baseline v1",
	}
}

// CohortMetrics extracts anonymous category bytes for cloud knowledge.
func CohortMetrics(result *models.ScanResult) map[string]int64 {
	if result == nil {
		return nil
	}
	keys := []struct {
		id    string
		match []string
	}{
		{"docker", []string{"docker", "container"}},
		{"deriveddata", []string{"deriveddata", "derived"}},
		{"npm", []string{"npm"}},
		{"ollama", []string{"ollama"}},
		{"huggingface", []string{"hugging"}},
		{"gradle", []string{"gradle"}},
		{"flutter", []string{"flutter", "pub-cache"}},
		{"wsl", []string{"wsl", "ext4"}},
		{"nuget", []string{"nuget"}},
		{"flatpak", []string{"flatpak"}},
		{"cargo", []string{"cargo", "rustup"}},
		{"pip", []string{"pip", "pycache"}},
	}
	out := map[string]int64{}
	for _, k := range keys {
		var sum int64
		for _, it := range result.Items {
			hay := strings.ToLower(it.Name + " " + it.Path + " " + it.Category)
			for _, m := range k.match {
				if strings.Contains(hay, m) {
					sum += it.SizeBytes
					break
				}
			}
		}
		if sum > 0 {
			out[k.id] = sum
		}
	}
	return out
}

func toMachine(r models.FleetReport) models.FleetMachine {
	return models.FleetMachine{
		MachineID:     r.MachineID,
		Hostname:      r.Hostname,
		Platform:      r.Platform,
		Arch:          r.Arch,
		ScannedAt:     r.ScannedAt,
		Reclaimable:   r.Reclaimable,
		SafeBytes:     r.SafeBytes,
		CheckBytes:    r.CheckBytes,
		TotalBytes:    r.TotalBytes,
		FreeBytes:     r.FreeBytes,
		ItemCount:     r.ItemCount,
		TopCategories: r.TopCategories,
		HealthScore:   r.HealthScore,
		Compliance:    r.Compliance,
		AIModels:      r.AIModels,
		Licenses:      r.Licenses,
		EnvWarnings:   r.EnvWarnings,
		CohortMetrics: r.CohortMetrics,
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
