package tier

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/stoguard/stoguard/internal/platform"
)

// Tier levels for Stoguard editions.
type Tier string

const (
	Free Tier = "free"
	Pro  Tier = "pro"
	Team Tier = "team"
)

type licenseFile struct {
	Tier    string `json:"tier"`
	License string `json:"license,omitempty"`
	Seat    string `json:"seat,omitempty"`
}

type Info struct {
	Tier        Tier              `json:"tier"`
	Source      string            `json:"source"`
	Features    map[string]bool   `json:"features"`
	Matrix      []FeatureRow      `json:"matrix"`
	DisplayName string            `json:"displayName"`
}

type FeatureRow struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Free        bool   `json:"free"`
	Pro         bool   `json:"pro"`
	Team        bool   `json:"team"`
	Unlocked    bool   `json:"unlocked"`
}

var (
	mu       sync.RWMutex
	cached   *Info
)

// Resolve returns the active tier.
// Priority: STOGUARD_TIER env > dataDir/license.json > default Pro for local builds.
func Resolve() Info {
	mu.RLock()
	if cached != nil {
		c := *cached
		mu.RUnlock()
		return c
	}
	mu.RUnlock()

	info := resolveFresh()
	mu.Lock()
	cached = &info
	mu.Unlock()
	return info
}

// Refresh clears cache (e.g. after writing license.json).
func Refresh() Info {
	mu.Lock()
	cached = nil
	mu.Unlock()
	return Resolve()
}

func resolveFresh() Info {
	// Local / open builds unlock Team so fleet console works out of the box.
	// Set STOGUARD_TIER=free|pro to simulate lower tiers.
	source := "default-team"
	t := Team

	if env := strings.TrimSpace(os.Getenv("STOGUARD_TIER")); env != "" {
		if parsed, ok := parse(env); ok {
			t = parsed
			source = "env:STOGUARD_TIER"
		}
	} else if lic, ok := readLicense(); ok {
		t = lic
		source = "license.json"
	}

	return Info{
		Tier:        t,
		Source:      source,
		Features:    featureMap(t),
		Matrix:      matrix(t),
		DisplayName: display(t),
	}
}

func parse(s string) (Tier, bool) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "free":
		return Free, true
	case "pro", "professional":
		return Pro, true
	case "team", "enterprise":
		return Team, true
	default:
		return "", false
	}
}

func readLicense() (Tier, bool) {
	path := filepath.Join(platform.DataDir(), "license.json")
	b, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	var lic licenseFile
	if err := json.Unmarshal(b, &lic); err != nil {
		return "", false
	}
	return parse(lic.Tier)
}

func display(t Tier) string {
	switch t {
	case Free:
		return "Free"
	case Team:
		return "Team"
	default:
		return "Pro"
	}
}

func rank(t Tier) int {
	switch t {
	case Free:
		return 0
	case Pro:
		return 1
	case Team:
		return 2
	default:
		return 1
	}
}

func atLeast(have, need Tier) bool {
	return rank(have) >= rank(need)
}

func matrix(active Tier) []FeatureRow {
	rows := []FeatureRow{
		{ID: "scan", Name: "Workstation scan", Description: "Rule-based cache & artifact scan", Free: true, Pro: true, Team: true},
		{ID: "trash", Name: "Trash cleanup", Description: "Move findings to OS Trash", Free: true, Pro: true, Team: true},
		{ID: "history", Name: "Storage timeline", Description: "Local scan history", Free: true, Pro: true, Team: true},
		{ID: "doctor", Name: "Workstation Doctor", Description: "Prioritized recommendations", Free: false, Pro: true, Team: true},
		{ID: "ask", Name: "Ask Stoguard", Description: "Local Q&A over scan facts", Free: false, Pro: true, Team: true},
		{ID: "health", Name: "Health score", Description: "Storage/performance/security/AI score + predictions", Free: true, Pro: true, Team: true},
		{ID: "learning", Name: "Learning Center", Description: "Teachable glossary for caches and AI terms", Free: true, Pro: true, Team: true},
		{ID: "automation", Name: "Automation", Description: "Scheduled scans and safe tidy rules", Free: false, Pro: true, Team: true},
		{ID: "duplicates", Name: "Duplicate grouping", Description: "Smarter duplicate detection", Free: false, Pro: true, Team: true},
		{ID: "models", Name: "AI Cleanup", Description: "Models, skills, MCP, and AI caches in one cleanup view", Free: false, Pro: true, Team: true},
		{ID: "packages", Name: "Package Finder", Description: "Installed packages with definitions and disk space", Free: false, Pro: true, Team: true},
		{ID: "agent_tools", Name: "AI Skills & MCP", Description: "Included in AI Cleanup (MCP, skills, extensions)", Free: false, Pro: true, Team: true},
		{ID: "fleet_export", Name: "Fleet JSON export", Description: "Export this machine for IT", Free: false, Pro: true, Team: true},
		{ID: "fleet_admin", Name: "Team fleet console", Description: "Ingest & aggregate fleet reports", Free: false, Pro: false, Team: true},
	}
	for i := range rows {
		need := Free
		if rows[i].Pro && !rows[i].Free {
			need = Pro
		}
		if rows[i].Team && !rows[i].Pro {
			need = Team
		}
		rows[i].Unlocked = atLeast(active, need)
		// Team-only rows
		if !rows[i].Free && !rows[i].Pro && rows[i].Team {
			rows[i].Unlocked = atLeast(active, Team)
		}
	}
	return rows
}

func featureMap(active Tier) map[string]bool {
	m := map[string]bool{}
	for _, r := range matrix(active) {
		m[r.ID] = r.Unlocked
	}
	return m
}

// Allows reports whether a feature id is unlocked.
func Allows(featureID string) bool {
	return Resolve().Features[featureID]
}

// IsTeam is true when Team tier is active.
func IsTeam() bool {
	return Resolve().Tier == Team
}
