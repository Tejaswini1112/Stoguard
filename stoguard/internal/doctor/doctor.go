package doctor

import (
	"fmt"
	"sort"
	"time"

	"github.com/stoguard/stoguard/internal/history"
	"github.com/stoguard/stoguard/internal/models"
	"github.com/stoguard/stoguard/internal/platform"
)

func Build(result *models.ScanResult, hist *history.Store) models.DoctorReport {
	recs := []models.Recommendation{}
	for _, it := range result.Items {
		if it.SizeBytes < 50_000_000 {
			continue
		}
		action := "review"
		advice := it.Note
		switch it.Safety {
		case models.SafetySafe:
			action = "trashSafe"
			advice = "Safe to move to Trash. Regenerates when the tool runs again."
		case models.SafetyCommand:
			action = "runCommand"
			advice = "Prefer the official prune command instead of deleting files by hand."
		case models.SafetyNever:
			action = "info"
			advice = "Keep this. Cleaning it can break your setup."
		}
		if it.DaysUnused != nil && *it.DaysUnused >= 30 && it.Safety != models.SafetyNever {
			advice = fmt.Sprintf("Unused for about %d days. %s", *it.DaysUnused, advice)
		}
		recs = append(recs, models.Recommendation{
			ID:            "rec-" + it.ID,
			Title:         it.Name,
			Explanation:   it.Note,
			Advice:        advice,
			Bytes:         it.SizeBytes,
			DaysUnused:    it.DaysUnused,
			Action:        action,
			RelatedItemID: it.ID,
			Command:       it.Command,
		})
	}
	sort.Slice(recs, func(i, j int) bool { return recs[i].Bytes > recs[j].Bytes })
	if len(recs) > 12 {
		recs = recs[:12]
	}

	growth := growthInsights(result, hist)
	summary := []string{
		fmt.Sprintf("%s recoverable marked safe", bytes(result.SafeBytes)),
		fmt.Sprintf("%s needs a quick review before cleaning", bytes(result.CheckBytes)),
		fmt.Sprintf("Adaptive scanner skipped %d unused rule paths", result.SkippedRules),
	}
	if result.CachedHits > 0 {
		summary = append(summary, fmt.Sprintf("%d folders reused from fingerprint cache", result.CachedHits))
	}
	if len(growth) > 0 && growth[0].DeltaBytes > 0 {
		summary = append(summary, fmt.Sprintf("Largest growth: %s (%s)", growth[0].Category, bytes(growth[0].DeltaBytes)))
	}

	headline := fmt.Sprintf("You can likely reclaim %s on this %s workstation.", bytes(result.SafeBytes), platform.OS())
	if result.SafeBytes == 0 {
		headline = "No large safe caches found — your workstation looks tidy."
	}

	return models.DoctorReport{
		GeneratedAt:      time.Now(),
		Headline:         headline,
		SummaryLines:     summary,
		ReclaimableSafe:  result.SafeBytes,
		ReclaimableCheck: result.CheckBytes,
		Recommendations:  recs,
		Growth:           growth,
		Platform:         platform.OS(),
	}
}

func growthInsights(result *models.ScanResult, hist *history.Store) []models.GrowthInsight {
	if hist == nil || len(hist.Entries) == 0 {
		return nil
	}
	prev := hist.Entries[len(hist.Entries)-1]
	type pair struct {
		cat   string
		delta int64
	}
	var deltas []pair
	for cat, cur := range result.CategoryTotals {
		delta := cur - prev.CategoryTotals[cat]
		if delta == 0 {
			continue
		}
		deltas = append(deltas, pair{cat, delta})
	}
	sort.Slice(deltas, func(i, j int) bool {
		ai, aj := deltas[i].delta, deltas[j].delta
		if ai < 0 {
			ai = -ai
		}
		if aj < 0 {
			aj = -aj
		}
		return ai > aj
	})
	out := []models.GrowthInsight{}
	for i, d := range deltas {
		if i >= 5 {
			break
		}
		detail := "grew since last scan"
		if d.delta < 0 {
			detail = "shrank since last scan"
		}
		out = append(out, models.GrowthInsight{
			ID:         fmt.Sprintf("g-%s", d.cat),
			Category:   d.cat,
			DeltaBytes: d.delta,
			Detail:     detail,
		})
	}
	return out
}

func bytes(n int64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := int64(unit), 0
	for v := n / unit; v >= unit; v /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(n)/float64(div), "KMGTPE"[exp])
}
