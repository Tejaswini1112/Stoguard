package adaptive

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"

	"github.com/stoguard/stoguard/internal/platform"
)

const AutoSkipAfterMisses = 5

type Profile struct {
	MissStreak     map[string]int      `json:"missStreak"`
	SkippedRuleIDs map[string]struct{} `json:"skippedRuleIds"`
	ScanCount      int                 `json:"scanCount"`
	mu             sync.Mutex
}

func filePath() string {
	return filepath.Join(platform.DataDir(), "adaptive-profile.json")
}

func Load() *Profile {
	p := &Profile{
		MissStreak:     map[string]int{},
		SkippedRuleIDs: map[string]struct{}{},
	}
	data, err := os.ReadFile(filePath())
	if err != nil {
		return p
	}
	_ = json.Unmarshal(data, p)
	if p.MissStreak == nil {
		p.MissStreak = map[string]int{}
	}
	if p.SkippedRuleIDs == nil {
		p.SkippedRuleIDs = map[string]struct{}{}
	}
	return p
}

func (p *Profile) Save() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := platform.EnsureDataDir(); err != nil {
		return err
	}
	data, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filePath(), data, 0o600)
}

func (p *Profile) ShouldScan(ruleID string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, skip := p.SkippedRuleIDs[ruleID]; skip {
		return false
	}
	return p.MissStreak[ruleID] < AutoSkipAfterMisses
}

func (p *Profile) RecordHit(ruleID string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.MissStreak[ruleID] = 0
	delete(p.SkippedRuleIDs, ruleID)
}

func (p *Profile) RecordMiss(ruleID string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	next := p.MissStreak[ruleID] + 1
	p.MissStreak[ruleID] = next
	if next >= AutoSkipAfterMisses {
		p.SkippedRuleIDs[ruleID] = struct{}{}
	}
}

func (p *Profile) BeginScan() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.ScanCount++
}

func (p *Profile) SkippedCount() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.SkippedRuleIDs)
}

func (p *Profile) Reset() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.MissStreak = map[string]int{}
	p.SkippedRuleIDs = map[string]struct{}{}
}
