package duplicates

import (
	"fmt"
	"path/filepath"
	"sort"
	"strings"

	"github.com/stoguard/stoguard/internal/models"
)

type Difference struct {
	Icon   string `json:"icon"`
	Label  string `json:"label"`
	Detail string `json:"detail"`
}

// Find groups items into confirmed duplicates vs related-but-distinct (with differences).
func Find(items []models.ScanItem) []models.DuplicateGroup {
	var groups []models.DuplicateGroup

	// Confirmed: same basename + size within 2% + different paths
	byBase := map[string][]models.ScanItem{}
	for _, it := range items {
		if it.SizeBytes < 50_000_000 {
			continue
		}
		base := strings.ToLower(filepath.Base(it.Path))
		if base == "" || base == "." || base == "cache" || base == "caches" || base == "tmp" {
			continue
		}
		byBase[base] = append(byBase[base], it)
	}
	for base, list := range byBase {
		if len(list) < 2 {
			continue
		}
		for _, cluster := range sizeClusters(list, 0.02) {
			if len(cluster) < 2 {
				continue
			}
			// Require at least two distinct paths
			paths := map[string]bool{}
			for _, it := range cluster {
				paths[it.Path] = true
			}
			if len(paths) < 2 {
				continue
			}
			groups = append(groups, models.DuplicateGroup{
				Kind:       "duplicate",
				Label:      "Confirmed duplicate: " + base,
				Items:      sortBySize(cluster),
				WasteBytes: wasteExceptLargest(cluster),
				Advice:     "Same name and nearly identical size at different paths — keep one copy.",
				Verdict:    "duplicate",
				Differences: []models.DupDifference{
					{Icon: "check", Label: "Match", Detail: "Basename + size within 2%"},
					{Icon: "disk", Label: "Reclaimable", Detail: fmtBytes(wasteExceptLargest(cluster))},
				},
			})
		}
	}

	// Related (NOT duplicates): category families with distinct sizes/paths
	relatedFamilies := []struct {
		kind, label, advice string
		match               func(models.ScanItem) bool
	}{
		{"node", "Node / npm ecosystem (related, not duplicates)",
			"Different tools and caches — not the same install. Compare paths before deleting.",
			func(it models.ScanItem) bool {
				p := strings.ToLower(it.Path + " " + it.ID)
				return strings.Contains(p, "nvm") || strings.Contains(p, "fnm") ||
					strings.Contains(p, "/.npm") || strings.Contains(p, "pnpm") || strings.Contains(p, "yarn")
			}},
		{"python", "Python environments (related, not duplicates)",
			"Different venvs/caches — not duplicates unless paths and sizes match.",
			func(it models.ScanItem) bool {
				p := strings.ToLower(it.Path + " " + it.ID)
				return strings.Contains(p, ".venv") || strings.Contains(p, "/venv") ||
					strings.Contains(p, "pyenv") || strings.Contains(p, "conda") || strings.Contains(p, "pip-cache")
			}},
		{"ai", "AI model stores (related, not duplicates)",
			"Ollama / HF / LM Studio are different stores. Only identical blobs are duplicates.",
			func(it models.ScanItem) bool {
				p := strings.ToLower(it.Path + " " + it.ID + " " + it.Category)
				return strings.Contains(p, "ollama") || strings.Contains(p, "huggingface") ||
					strings.Contains(p, "lm-studio") || strings.Contains(p, "gguf") || strings.Contains(p, "ai tool")
			}},
		{"containers", "Container runtimes (related, not duplicates)",
			"Docker / Colima / Podman data are separate systems — not interchangeable duplicates.",
			func(it models.ScanItem) bool {
				p := strings.ToLower(it.Path + " " + it.ID + " " + it.Category)
				return strings.Contains(p, "docker") || strings.Contains(p, "colima") ||
					strings.Contains(p, "podman") || strings.Contains(p, "container")
			}},
	}

	dupPaths := map[string]bool{}
	for _, g := range groups {
		for _, it := range g.Items {
			dupPaths[it.Path] = true
		}
	}

	for _, fam := range relatedFamilies {
		list := filter(items, fam.match)
		var distinct []models.ScanItem
		for _, it := range list {
			if !dupPaths[it.Path] {
				distinct = append(distinct, it)
			}
		}
		if len(distinct) < 2 {
			continue
		}
		// If everything already looks size-identical, it may be real dups — skip related
		if len(sizeClusters(distinct, 0.02)) == 1 && len(distinct) >= 2 {
			// already handled or borderline — still mark related if names differ a lot
		}
		diffs := relatedDiffs(distinct)
		groups = append(groups, models.DuplicateGroup{
			Kind:        fam.kind,
			Label:       fam.label,
			Items:       sortBySize(distinct),
			WasteBytes:  0, // not duplicate waste
			Advice:      fam.advice,
			Verdict:     "related",
			Differences: diffs,
		})
	}

	sort.Slice(groups, func(i, j int) bool {
		if groups[i].Verdict != groups[j].Verdict {
			return groups[i].Verdict == "duplicate"
		}
		return groups[i].WasteBytes > groups[j].WasteBytes
	})
	return dedupeGroups(groups)
}

func relatedDiffs(items []models.ScanItem) []models.DupDifference {
	var diffs []models.DupDifference
	names := []string{}
	seen := map[string]bool{}
	for _, it := range items {
		n := filepath.Base(it.Path)
		if !seen[n] {
			seen[n] = true
			names = append(names, n)
		}
	}
	diffs = append(diffs, models.DupDifference{
		Icon: "tag", Label: "Names", Detail: strings.Join(names, " · "),
	})
	if len(items) >= 2 {
		sorted := sortBySize(items)
		maxB, minB := sorted[0].SizeBytes, sorted[len(sorted)-1].SizeBytes
		if maxB != minB {
			diffs = append(diffs, models.DupDifference{
				Icon: "scale", Label: "Size gap",
				Detail: fmt.Sprintf("%s → %s", fmtBytes(minB), fmtBytes(maxB)),
			})
		} else {
			diffs = append(diffs, models.DupDifference{
				Icon: "scale", Label: "Sizes", Detail: "Similar disk use — still different paths/tools",
			})
		}
	}
	cats := map[string]bool{}
	for _, it := range items {
		cats[it.Category] = true
	}
	if len(cats) > 1 {
		var c []string
		for k := range cats {
			c = append(c, k)
		}
		sort.Strings(c)
		diffs = append(diffs, models.DupDifference{
			Icon: "folder", Label: "Categories differ", Detail: strings.Join(c, " · "),
		})
	}
	diffs = append(diffs, models.DupDifference{
		Icon: "x", Label: "Verdict", Detail: "Not a duplicate — fingerprints/roles differ",
	})
	return diffs
}

func fmtBytes(n int64) string {
	switch {
	case n >= 1_000_000_000:
		return fmt.Sprintf("%.1f GB", float64(n)/1e9)
	case n >= 1_000_000:
		return fmt.Sprintf("%.0f MB", float64(n)/1e6)
	default:
		return fmt.Sprintf("%d B", n)
	}
}

func sizeClusters(items []models.ScanItem, tol float64) [][]models.ScanItem {
	sorted := sortBySize(items)
	used := make([]bool, len(sorted))
	var clusters [][]models.ScanItem
	for i := range sorted {
		if used[i] {
			continue
		}
		cluster := []models.ScanItem{sorted[i]}
		used[i] = true
		ref := float64(sorted[i].SizeBytes)
		for j := i + 1; j < len(sorted); j++ {
			if used[j] || ref == 0 {
				continue
			}
			other := float64(sorted[j].SizeBytes)
			if abs(ref-other)/ref <= tol {
				cluster = append(cluster, sorted[j])
				used[j] = true
			}
		}
		clusters = append(clusters, cluster)
	}
	return clusters
}

func dedupeGroups(groups []models.DuplicateGroup) []models.DuplicateGroup {
	seen := map[string]bool{}
	out := []models.DuplicateGroup{}
	for _, g := range groups {
		ids := make([]string, len(g.Items))
		for i, it := range g.Items {
			ids[i] = it.ID + "|" + it.Path
		}
		sort.Strings(ids)
		key := g.Verdict + ":" + g.Kind + ":" + strings.Join(ids, ",")
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, g)
	}
	return out
}

func sortBySize(items []models.ScanItem) []models.ScanItem {
	out := append([]models.ScanItem{}, items...)
	sort.Slice(out, func(i, j int) bool { return out[i].SizeBytes > out[j].SizeBytes })
	return out
}

func filter(items []models.ScanItem, fn func(models.ScanItem) bool) []models.ScanItem {
	out := []models.ScanItem{}
	for _, it := range items {
		if fn(it) {
			out = append(out, it)
		}
	}
	return out
}

func wasteExceptLargest(items []models.ScanItem) int64 {
	var max, sum int64
	for _, it := range items {
		sum += it.SizeBytes
		if it.SizeBytes > max {
			max = it.SizeBytes
		}
	}
	if sum <= max {
		return 0
	}
	return sum - max
}

func abs(f float64) float64 {
	if f < 0 {
		return -f
	}
	return f
}
