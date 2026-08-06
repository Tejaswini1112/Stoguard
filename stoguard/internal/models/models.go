package models

import "time"

type Safety string

const (
	SafetySafe    Safety = "safe"
	SafetyCheck   Safety = "check"
	SafetyCommand Safety = "command"
	SafetyNever   Safety = "never"
)

type Rule struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Path     string `json:"path"`
	Category string `json:"category"`
	Safety   Safety `json:"safety"`
	Note     string `json:"note"`
	Command  string `json:"command,omitempty"`
}

type Plugin struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Version   string   `json:"version"`
	Platforms []string `json:"platforms"`
	Rules     []Rule   `json:"rules"`
}

type LargeChild struct {
	Name      string `json:"name"`
	Path      string `json:"path"`
	SizeBytes int64  `json:"sizeBytes"`
}

type ScanItem struct {
	ID           string       `json:"id"`
	Name         string       `json:"name"`
	Path         string       `json:"path"`
	Category     string       `json:"category"`
	Safety       Safety       `json:"safety"`
	Note         string       `json:"note"`
	Command      string       `json:"command,omitempty"`
	SizeBytes    int64        `json:"sizeBytes"`
	Known        bool         `json:"known"`
	LastActivity *time.Time   `json:"lastActivity,omitempty"`
	DaysUnused   *int         `json:"daysUnused,omitempty"`
	Children     []LargeChild `json:"children,omitempty"`
	FromCache    bool         `json:"fromCache"`
}

type ScanResult struct {
	Platform       string            `json:"platform"`
	ScannedAt      time.Time         `json:"scannedAt"`
	Items          []ScanItem        `json:"items"`
	TotalBytes     int64             `json:"totalBytes"`
	SafeBytes      int64             `json:"safeBytes"`
	CheckBytes     int64             `json:"checkBytes"`
	SkippedRules   int               `json:"skippedRules"`
	CachedHits     int               `json:"cachedHits"`
	FreeBytes      int64             `json:"freeBytes"`
	DiskTotalBytes int64             `json:"diskTotalBytes"`
	CategoryTotals map[string]int64  `json:"categoryTotals"`
}

type Recommendation struct {
	ID            string `json:"id"`
	Title         string `json:"title"`
	Explanation   string `json:"explanation"`
	Advice        string `json:"advice"`
	Bytes         int64  `json:"bytes"`
	DaysUnused    *int   `json:"daysUnused,omitempty"`
	Action        string `json:"action"`
	RelatedItemID string `json:"relatedItemId,omitempty"`
	Command       string `json:"command,omitempty"`
}

type GrowthInsight struct {
	ID         string `json:"id"`
	Category   string `json:"category"`
	DeltaBytes int64  `json:"deltaBytes"`
	Detail     string `json:"detail"`
}

type DoctorReport struct {
	GeneratedAt     time.Time        `json:"generatedAt"`
	Headline        string           `json:"headline"`
	SummaryLines    []string         `json:"summaryLines"`
	ReclaimableSafe int64            `json:"reclaimableSafe"`
	ReclaimableCheck int64           `json:"reclaimableCheck"`
	Recommendations []Recommendation `json:"recommendations"`
	Growth          []GrowthInsight  `json:"growth"`
	Platform        string           `json:"platform"`
}

type HistoryEntry struct {
	Date            time.Time         `json:"date"`
	FreeBytes       int64             `json:"freeBytes"`
	TotalBytes      int64             `json:"totalBytes"`
	ReclaimableSafe int64             `json:"reclaimableSafe"`
	CategoryTotals  map[string]int64  `json:"categoryTotals"`
	TopItemIDs      []string          `json:"topItemIds"`
}

type DupDifference struct {
	Icon   string `json:"icon"`
	Label  string `json:"label"`
	Detail string `json:"detail"`
}

type DuplicateGroup struct {
	Kind        string          `json:"kind"`
	Label       string          `json:"label"`
	Items       []ScanItem      `json:"items"`
	WasteBytes  int64           `json:"wasteBytes"`
	Advice      string          `json:"advice"`
	Verdict     string          `json:"verdict"` // duplicate | related
	Differences []DupDifference `json:"differences,omitempty"`
}

type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type AppStatus struct {
	Name     string          `json:"name"`
	Version  string          `json:"version"`
	Platform string          `json:"platform"`
	OS       string          `json:"os"`
	Arch     string          `json:"arch"`
	Home     string          `json:"home"`
	DataDir  string          `json:"dataDir"`
	Tier     string          `json:"tier"`
	TierName string          `json:"tierName"`
	Features map[string]bool `json:"features,omitempty"`
	System   any             `json:"system,omitempty"`
}

type CategoryBytes struct {
	Category string `json:"category"`
	Bytes    int64  `json:"bytes"`
}

type FleetReport struct {
	SchemaVersion string                     `json:"schemaVersion,omitempty"`
	MachineID     string                     `json:"machineID"`
	Hostname      string                     `json:"hostname"`
	Platform      string                     `json:"platform"`
	Arch          string                     `json:"arch,omitempty"`
	AppVersion    string                     `json:"appVersion,omitempty"`
	ScannedAt     time.Time                  `json:"scannedAt"`
	Reclaimable   int64                      `json:"reclaimable"`
	SafeBytes     int64                      `json:"safeBytes"`
	CheckBytes    int64                      `json:"checkBytes"`
	TotalBytes    int64                      `json:"totalBytes"`
	FreeBytes     int64                      `json:"freeBytes"`
	ItemCount     int                        `json:"itemCount"`
	TopCategories []CategoryBytes            `json:"topCategories"`
	TopItems      []FleetItem                `json:"topItems,omitempty"`
	EnvWarnings   []string                   `json:"envWarnings,omitempty"`
	HealthScore   *int                       `json:"healthScore,omitempty"`
	Compliance    *ComplianceSnapshot        `json:"compliance,omitempty"`
	AIModels      []AIModelInventoryEntry    `json:"aiModels,omitempty"`
	Licenses      []LicenseEntry             `json:"licenses,omitempty"`
	CohortMetrics map[string]int64           `json:"cohortMetrics,omitempty"`
	// Legacy alias for older clients
	Host string `json:"host,omitempty"`
}

type FleetItem struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Category string `json:"category"`
	Bytes    int64  `json:"bytes"`
	Safety   string `json:"safety"`
}

type ComplianceSnapshot struct {
	Score    int      `json:"score"`
	Passed   []string `json:"passed"`
	Failed   []string `json:"failed"`
	Baseline string   `json:"baseline"`
}

type AIModelInventoryEntry struct {
	Provider string `json:"provider"`
	Name     string `json:"name"`
	Bytes    int64  `json:"bytes"`
	DaysIdle *int   `json:"daysIdle,omitempty"`
}

type LicenseEntry struct {
	Product string `json:"product"`
	Path    string `json:"path"`
	Note    string `json:"note"`
}

type FleetMachine struct {
	MachineID     string                  `json:"machineID"`
	Hostname      string                  `json:"hostname"`
	Platform      string                  `json:"platform"`
	Arch          string                  `json:"arch,omitempty"`
	ScannedAt     time.Time               `json:"scannedAt"`
	Reclaimable   int64                   `json:"reclaimable"`
	SafeBytes     int64                   `json:"safeBytes"`
	CheckBytes    int64                   `json:"checkBytes"`
	TotalBytes    int64                   `json:"totalBytes"`
	FreeBytes     int64                   `json:"freeBytes"`
	ItemCount     int                     `json:"itemCount"`
	TopCategories []CategoryBytes         `json:"topCategories"`
	HealthScore   *int                    `json:"healthScore,omitempty"`
	Compliance    *ComplianceSnapshot     `json:"compliance,omitempty"`
	AIModels      []AIModelInventoryEntry `json:"aiModels,omitempty"`
	Licenses      []LicenseEntry          `json:"licenses,omitempty"`
	EnvWarnings   []string                `json:"envWarnings,omitempty"`
	CohortMetrics map[string]int64        `json:"cohortMetrics,omitempty"`
}

type FleetSummary struct {
	MachineCount     int            `json:"machineCount"`
	TotalReclaimable int64          `json:"totalReclaimable"`
	Platforms        map[string]int `json:"platforms"`
	NonCompliant     int            `json:"nonCompliantCount"`
	AvgHealth        *int           `json:"avgHealth,omitempty"`
}

// ModelPath is a local AI model store discovered during scan.
type ModelPath struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Path      string `json:"path"`
	Category  string `json:"category"`
	SizeBytes int64  `json:"sizeBytes"`
	Safety    Safety `json:"safety"`
	Note      string `json:"note"`
	Provider  string `json:"provider"`
}

