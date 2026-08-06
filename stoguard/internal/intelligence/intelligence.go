package intelligence

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/stoguard/stoguard/internal/fleet"
	"github.com/stoguard/stoguard/internal/models"
	"github.com/stoguard/stoguard/internal/platform"
)

type Dimension struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Score  int    `json:"score"`
	Detail string `json:"detail"`
}

type HealthReport struct {
	Overall     int         `json:"overall"`
	Dimensions  []Dimension `json:"dimensions"`
	Headline    string      `json:"headline"`
	GeneratedAt time.Time   `json:"generatedAt"`
}

type PredictiveInsight struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Body     string `json:"body"`
	Severity string `json:"severity"`
}

type ProactiveAlert struct {
	ID             string `json:"id"`
	Title          string `json:"title"`
	Explanation    string `json:"explanation"`
	Recommendation string `json:"recommendation"`
	Severity       string `json:"severity"`
	Related        string `json:"related,omitempty"`
}

type LearningArticle struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Category    string `json:"category"`
	What        string `json:"what"`
	WhyCreated  string `json:"whyCreated"`
	WhySafe     string `json:"whySafe"`
	WhenDelete  string `json:"whenDelete"`
	AfterDelete string `json:"afterDelete"`
}

type AutomationRule struct {
	ID       string     `json:"id"`
	Name     string     `json:"name"`
	Enabled  bool       `json:"enabled"`
	Schedule string     `json:"schedule"`
	Action   string     `json:"action"`
	MinBytes int64      `json:"minBytes"`
	LastRun  *time.Time `json:"lastRun,omitempty"`
}

type AutomationStore struct {
	Rules      []AutomationRule `json:"rules"`
	CloudOptIn bool             `json:"cloudOptIn"`
}

type PrefStat struct {
	KeepCount  int        `json:"keepCount"`
	CleanCount int        `json:"cleanCount"`
	LastAction string     `json:"lastAction,omitempty"`
	LastAt     *time.Time `json:"lastAt,omitempty"`
}

type PreferenceMemory struct {
	ByKey map[string]PrefStat `json:"byKey"`
}

type CloudBenchmark struct {
	ID             string `json:"id"`
	Cohort         string `json:"cohort"`
	AverageBytes   int64  `json:"averageBytes"`
	YourBytes      int64  `json:"yourBytes"`
	Recommendation string `json:"recommendation"`
	Source         string `json:"source,omitempty"`
	SampleSize     *int   `json:"sampleSize,omitempty"`
}

type Snapshot struct {
	Health      HealthReport        `json:"health"`
	Predictive  []PredictiveInsight `json:"predictive"`
	Proactive   []ProactiveAlert    `json:"proactive"`
	Learning    []LearningArticle   `json:"learning"`
	Automation  AutomationStore     `json:"automation"`
	Benchmarks  []CloudBenchmark    `json:"benchmarks"`
	Preferences PreferenceMemory    `json:"preferences"`
}

func dataPath(name string) string {
	return filepath.Join(platform.DataDir(), name)
}

func LoadAutomation() AutomationStore {
	path := dataPath("automation.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return AutomationStore{Rules: defaultRules(), CloudOptIn: false}
	}
	var s AutomationStore
	if json.Unmarshal(data, &s) != nil || len(s.Rules) == 0 {
		return AutomationStore{Rules: defaultRules(), CloudOptIn: false}
	}
	return s
}

func SaveAutomation(s AutomationStore) error {
	_ = os.MkdirAll(platform.DataDir(), 0o755)
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(dataPath("automation.json"), data, 0o644)
}

func LoadPreferences() PreferenceMemory {
	path := dataPath("preference-memory.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return PreferenceMemory{ByKey: map[string]PrefStat{}}
	}
	var p PreferenceMemory
	if json.Unmarshal(data, &p) != nil || p.ByKey == nil {
		return PreferenceMemory{ByKey: map[string]PrefStat{}}
	}
	return p
}

func SavePreferences(p PreferenceMemory) error {
	_ = os.MkdirAll(platform.DataDir(), 0o755)
	data, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(dataPath("preference-memory.json"), data, 0o644)
}

func RecordKeep(id string) PreferenceMemory {
	p := LoadPreferences()
	s := p.ByKey[id]
	s.KeepCount++
	s.LastAction = "keep"
	now := time.Now()
	s.LastAt = &now
	p.ByKey[id] = s
	_ = SavePreferences(p)
	return p
}

func RecordClean(id string) PreferenceMemory {
	p := LoadPreferences()
	s := p.ByKey[id]
	s.CleanCount++
	s.LastAction = "clean"
	now := time.Now()
	s.LastAt = &now
	p.ByKey[id] = s
	_ = SavePreferences(p)
	return p
}

func defaultRules() []AutomationRule {
	return []AutomationRule{
		{ID: "sunday-safe", Name: "Sunday safe-cache tidy", Enabled: false, Schedule: "sunday", Action: "safeCaches", MinBytes: 1_000_000_000},
		{ID: "npm-5gb", Name: "npm cache if > 5 GB", Enabled: false, Schedule: "weekly", Action: "npmCache", MinBytes: 5_000_000_000},
		{ID: "daily-scan", Name: "Daily background scan", Enabled: true, Schedule: "daily", Action: "scanOnly", MinBytes: 0},
	}
}

func Build(result *models.ScanResult, hist []models.HistoryEntry) Snapshot {
	auto := LoadAutomation()
	prefs := LoadPreferences()
	sys := platform.CollectSystem()
	health := computeHealth(result, sys)
	return Snapshot{
		Health:      health,
		Predictive:  predict(result, hist, sys),
		Proactive:   proactive(result, hist, sys, prefs),
		Learning:    Articles(),
		Automation:  auto,
		Benchmarks:  benchmarks(result, auto.CloudOptIn),
		Preferences: prefs,
	}
}

func computeHealth(result *models.ScanResult, sys platform.SystemInfo) HealthReport {
	used := sys.DiskUsedPct
	storage := 100
	if used > 95 {
		storage -= 40
	} else if used > 90 {
		storage -= 28
	} else if used > 80 {
		storage -= 16
	} else if used > 70 {
		storage -= 8
	}
	if result != nil && result.SafeBytes > 20_000_000_000 {
		storage -= 12
	} else if result != nil && result.SafeBytes > 5_000_000_000 {
		storage -= 6
	}
	if storage < 5 {
		storage = 5
	}

	perf := 88
	memPct := 0.0
	if sys.MemSysBytes > 0 {
		memPct = float64(sys.MemAllocBytes) / float64(sys.MemSysBytes) * 100
	}
	if memPct > 90 {
		perf -= 12
	} else if memPct > 70 {
		perf -= 6
	}
	if used > 90 {
		perf -= 12
	} else if used > 80 {
		perf -= 6
	}
	if perf < 5 {
		perf = 5
	}

	sec := 92
	ai := 90
	if result != nil {
		for _, it := range result.Items {
			if it.Safety == models.SafetyNever {
				sec -= 3
			}
			if strings.Contains(strings.ToLower(it.Category), "ai") {
				if it.SizeBytes > 10_000_000_000 {
					ai -= 8
				}
			}
		}
	}
	if sec < 20 {
		sec = 20
	}
	if ai < 15 {
		ai = 15
	}

	dims := []Dimension{
		{ID: "storage", Name: "Storage", Score: storage, Detail: fmt.Sprintf("Disk ~%.0f%% used · %.1f GB safe", used, float64(safeBytes(result))/1e9)},
		{ID: "performance", Name: "Performance", Score: perf, Detail: "CPU/RAM/disk pressure"},
		{ID: "security", Name: "Security", Score: sec, Detail: "High-risk paths flagged"},
		{ID: "ai", Name: "AI Workspace", Score: ai, Detail: "Local models and AI caches"},
	}
	overall := 0
	for _, d := range dims {
		overall += d.Score
	}
	overall /= len(dims)
	headline := "Critical space/performance risk — clean and review now."
	switch {
	case overall >= 90:
		headline = "Workstation looks healthy — keep light maintenance."
	case overall >= 75:
		headline = "Solid machine with a few reclaim opportunities."
	case overall >= 55:
		headline = "Pressure building — act on safe caches and idle AI models."
	}
	return HealthReport{Overall: overall, Dimensions: dims, Headline: headline, GeneratedAt: time.Now()}
}

func safeBytes(result *models.ScanResult) int64 {
	if result == nil {
		return 0
	}
	return result.SafeBytes
}

func predict(result *models.ScanResult, hist []models.HistoryEntry, sys platform.SystemInfo) []PredictiveInsight {
	var out []PredictiveInsight
	if len(hist) >= 2 {
		first := hist[0]
		if len(hist) > 8 {
			first = hist[len(hist)-8]
		}
		last := hist[len(hist)-1]
		days := last.Date.Sub(first.Date).Hours() / 24
		if days < 0.5 {
			days = 0.5
		}
		freeDelta := float64(first.FreeBytes - last.FreeBytes)
		if freeDelta > 50_000_000 && sys.DiskTotalBytes > 0 {
			bpd := freeDelta / days
			targetFree := float64(sys.DiskTotalBytes) * 0.05
			need := float64(sys.DiskFreeBytes) - targetFree
			daysTo95 := 0.0
			if need > 0 && bpd > 0 {
				daysTo95 = need / bpd
			}
			sev := "info"
			if daysTo95 < 14 {
				sev = "critical"
			} else if daysTo95 < 45 {
				sev = "warn"
			}
			out = append(out, PredictiveInsight{
				ID:       "disk-eta",
				Title:    fmt.Sprintf("SSD may hit 95%% in ~%.0f days", maxf(1, daysTo95)),
				Body:     fmt.Sprintf("Based on %.1f GB/day free-space loss over the last %.0f days.", bpd/1e9, days),
				Severity: sev,
			})
		} else {
			out = append(out, PredictiveInsight{
				ID: "disk-stable", Title: "Disk usage looks stable",
				Body: fmt.Sprintf("Free space held roughly steady (%.1f GB free now).", float64(sys.DiskFreeBytes)/1e9), Severity: "info",
			})
		}
	}
	if result != nil && len(result.Items) > 0 {
		top := result.Items[0]
		for _, it := range result.Items {
			if it.SizeBytes > top.SizeBytes {
				top = it
			}
		}
		if top.SizeBytes > 5_000_000_000 {
			out = append(out, PredictiveInsight{
				ID: "hotspot", Title: top.Name + " is your largest hotspot",
				Body: fmt.Sprintf("%s · %s", human(top.SizeBytes), top.Note), Severity: "info",
			})
		}
	}
	if len(out) == 0 {
		out = append(out, PredictiveInsight{
			ID: "need-history", Title: "Need more scans for forecasts",
			Body: "Run scans over a few days — Stoguard will project when your SSD fills.", Severity: "info",
		})
	}
	return out
}

func proactive(result *models.ScanResult, hist []models.HistoryEntry, sys platform.SystemInfo, prefs PreferenceMemory) []ProactiveAlert {
	var alerts []ProactiveAlert
	used := sys.DiskUsedPct
	if used >= 92 {
		alerts = append(alerts, ProactiveAlert{
			ID: "disk-critical", Title: "Disk critically full",
			Explanation:    fmt.Sprintf("Volume is %.0f%% full.", used),
			Recommendation: "Clean safe caches first, then review Docker / AI models.",
			Severity:       "critical", Related: "health",
		})
	}
	if result != nil {
		for i, it := range result.Items {
			if i >= 8 {
				break
			}
			if shouldDeprioritize(prefs, it.ID) {
				continue
			}
			if it.Safety == models.SafetySafe && it.SizeBytes > 2_000_000_000 {
				rec := "Safe to Trash; regenerates on next use."
				if shouldPrioritize(prefs, it.ID) {
					rec = "You usually clean this — move to Trash when ready."
				}
				alerts = append(alerts, ProactiveAlert{
					ID: "safe-" + it.ID, Title: it.Name + " can free " + human(it.SizeBytes),
					Explanation: it.Note, Recommendation: rec, Severity: "info", Related: it.Category,
				})
			}
		}
	}
	if len(hist) >= 2 {
		last := hist[len(hist)-1]
		prev := hist[len(hist)-2]
		for cat, bytes := range last.CategoryTotals {
			delta := bytes - prev.CategoryTotals[cat]
			if delta > 3_000_000_000 {
				days := int(last.Date.Sub(prev.Date).Hours() / 24)
				if days < 1 {
					days = 1
				}
				alerts = append(alerts, ProactiveAlert{
					ID: "grow-" + cat, Title: fmt.Sprintf("%s grew %s in %dd", cat, human(delta), days),
					Explanation:    "Repeated builds or downloads often cause this.",
					Recommendation: "Open " + cat + " and review the largest folders.",
					Severity:       "warn", Related: cat,
				})
			}
		}
	}
	if len(alerts) > 12 {
		alerts = alerts[:12]
	}
	return alerts
}

func BenchmarksPublic(result *models.ScanResult, optIn bool) []CloudBenchmark {
	return benchmarks(result, optIn)
}

func benchmarks(result *models.ScanResult, optIn bool) []CloudBenchmark {
	if !optIn || result == nil {
		return nil
	}
	baselines := map[string]int64{
		"docker": 18_000_000_000, "deriveddata": 10_000_000_000, "npm": 2_500_000_000,
		"ollama": 14_000_000_000, "huggingface": 20_000_000_000, "gradle": 6_000_000_000,
		"flutter": 9_000_000_000, "wsl": 30_000_000_000, "nuget": 3_000_000_000,
		"flatpak": 5_000_000_000, "cargo": 4_000_000_000, "pip": 3_000_000_000,
	}
	labels := map[string]string{
		"docker": "Docker", "deriveddata": "Xcode DerivedData", "npm": "npm cache",
		"ollama": "Ollama models", "huggingface": "Hugging Face", "gradle": "Gradle",
		"flutter": "Flutter / pub-cache", "wsl": "WSL", "nuget": "NuGet",
		"flatpak": "Flatpak", "cargo": "Cargo", "pip": "pip / Python",
	}
	yours := fleet.CohortMetrics(result)
	peerAvgs, peerCounts := peerAveragesFromFleet()
	var out []CloudBenchmark
	for id, yourBytes := range yours {
		avg := baselines[id]
		if avg == 0 {
			avg = yourBytes
		}
		source := "baseline"
		var samples *int
		if remote := remoteCohortAvg(id); remote > 0 {
			avg = remote
			source = "remote"
		} else if p, ok := peerAvgs[id]; ok && peerCounts[id] >= 2 {
			avg = p
			source = "fleet-peers"
			n := peerCounts[id]
			samples = &n
		}
		rec := "Within a normal range for this cohort."
		ratio := float64(yourBytes) / float64(max64(1, avg))
		if ratio >= 2.5 {
			rec = "Well above cohort — prioritize cleanup / archive."
		} else if ratio >= 1.4 {
			rec = "Above average — good reclaim candidate."
		} else if ratio <= 0.6 {
			rec = "Below cohort average — healthy relative to peers."
		}
		out = append(out, CloudBenchmark{
			ID: id, Cohort: labels[id], AverageBytes: avg, YourBytes: yourBytes,
			Recommendation: rec, Source: source, SampleSize: samples,
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].YourBytes > out[j].YourBytes })
	return out
}

func peerAveragesFromFleet() (map[string]int64, map[string]int) {
	list, err := fleet.List()
	if err != nil {
		return map[string]int64{}, map[string]int{}
	}
	sums := map[string]int64{}
	counts := map[string]int{}
	for _, m := range list {
		for k, v := range m.CohortMetrics {
			if v <= 0 {
				continue
			}
			sums[k] += v
			counts[k]++
		}
	}
	avgs := map[string]int64{}
	for k, s := range sums {
		avgs[k] = s / int64(max(1, counts[k]))
	}
	return avgs, counts
}

func remoteCohortAvg(id string) int64 {
	url := os.Getenv("STOGUARD_COHORT_FEED")
	if url == "" {
		return 0
	}
	// Cached file only — refresh via separate tooling to keep scan fast.
	path := filepath.Join(platform.DataDir(), "cohort-remote.json")
	b, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	var feed struct {
		Averages map[string]int64 `json:"averages"`
	}
	if json.Unmarshal(b, &feed) != nil {
		return 0
	}
	return feed.Averages[id]
}

func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func Articles() []LearningArticle {
	return []LearningArticle{
		{ID: "deriveddata", Title: "DerivedData", Category: "Xcode",
			What: "Xcode’s build products, indexes, and module caches.", WhyCreated: "Speeds incremental compiles.",
			WhySafe: "Xcode regenerates it on the next build.", WhenDelete: "When huge or builds act weird.",
			AfterDelete: "Next build is slower (cold compile)."},
		{ID: "docker", Title: "Docker disk image", Category: "Containers",
			What: "VM disk holding images, containers, and build cache.", WhyCreated: "Fast container starts.",
			WhySafe: "Pruning unused images keeps Dockerfiles intact.", WhenDelete: "When unused images pile up.",
			AfterDelete: "Next pull/build re-downloads layers."},
		{ID: "npm-cache", Title: "npm cache", Category: "Packages",
			What: "Downloaded package tarballs.", WhyCreated: "Faster reinstalls across projects.",
			WhySafe: "Rebuildable with npm install.", WhenDelete: "When multi‑GB and idle.",
			AfterDelete: "Next installs refill the cache."},
		{ID: "ollama", Title: "Ollama models", Category: "AI",
			What: "Local LLM weights.", WhyCreated: "Offline inference without cloud APIs.",
			WhySafe: "Deletes weights only, not Ollama itself.", WhenDelete: "When idle for weeks.",
			AfterDelete: "ollama pull again to restore."},
	}
}

func ArticleMatching(q string) *LearningArticle {
	q = strings.ToLower(q)
	for _, a := range Articles() {
		if strings.Contains(q, a.ID) || strings.Contains(q, strings.ToLower(a.Title)) {
			cp := a
			return &cp
		}
	}
	return nil
}

func shouldDeprioritize(p PreferenceMemory, id string) bool {
	s, ok := p.ByKey[id]
	return ok && s.KeepCount >= 2 && s.KeepCount > s.CleanCount
}

func shouldPrioritize(p PreferenceMemory, id string) bool {
	s, ok := p.ByKey[id]
	return ok && s.CleanCount >= 2 && s.CleanCount > s.KeepCount
}

func human(b int64) string {
	const gb = 1_000_000_000.0
	if b >= 1_000_000_000 {
		return fmt.Sprintf("%.1f GB", float64(b)/gb)
	}
	if b >= 1_000_000 {
		return fmt.Sprintf("%.0f MB", float64(b)/1_000_000)
	}
	return fmt.Sprintf("%d B", b)
}

func maxf(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}
