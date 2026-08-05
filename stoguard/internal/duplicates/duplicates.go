package duplicates

import (
	"path/filepath"
	"sort"
	"strings"

	"github.com/stoguard/stoguard/internal/models"
)

// Find groups likely duplicate developer artifacts from a scan with tighter grouping.
func Find(items []models.ScanItem) []models.DuplicateGroup {
	groups := []models.DuplicateGroup{}

	add := func(kind, label, advice string, list []models.ScanItem) {
		if len(list) < 2 {
			return
		}
		// Prefer groups with meaningful waste
		waste := wasteExceptLargest(list)
		groups = append(groups, models.DuplicateGroup{
			Kind:       kind,
			Label:      label,
			Items:      sortBySize(list),
			WasteBytes: waste,
			Advice:     advice,
		})
	}

	add("runtimes", "Multiple Node-related caches / installs",
		"Keep one active Node toolchain; remove unused version caches.",
		filter(items, func(it models.ScanItem) bool {
			p := strings.ToLower(it.Path)
			id := strings.ToLower(it.ID)
			return strings.Contains(p, "node_modules") || strings.Contains(p, "/.npm") ||
				strings.Contains(p, "nvm") || strings.Contains(p, "fnm") ||
				strings.Contains(id, "node") || strings.Contains(id, "npm") ||
				strings.Contains(id, "yarn") || strings.Contains(id, "pnpm")
		}))

	add("ai-models", "Multiple local AI model stores",
		"Archive unused models to external storage or delete duplicates.",
		filter(items, func(it models.ScanItem) bool {
			c := strings.ToLower(it.Category)
			id := strings.ToLower(it.ID)
			p := strings.ToLower(it.Path)
			return strings.Contains(c, "ai") || strings.Contains(id, "ollama") ||
				strings.Contains(id, "huggingface") || strings.Contains(id, "lmstudio") ||
				strings.Contains(id, "comfy") || strings.Contains(p, "ollama") ||
				strings.Contains(p, "huggingface") || strings.Contains(p, "lm-studio") ||
				strings.Contains(p, "gguf")
		}))

	add("python", "Overlapping Python environments / caches",
		"Remove stale virtualenvs you no longer activate.",
		filter(items, func(it models.ScanItem) bool {
			p := strings.ToLower(it.Path)
			id := strings.ToLower(it.ID)
			return strings.Contains(p, "virtualenv") || strings.Contains(p, "/venv") ||
				strings.Contains(p, ".venv") || strings.Contains(id, "pipenv") ||
				strings.Contains(id, "conda") || strings.Contains(id, "poetry") ||
				strings.Contains(id, "pip-cache") || strings.Contains(p, "__pycache__")
		}))

	add("containers", "Container / VM image caches",
		"Prune unused images and build cache layers you no longer need.",
		filter(items, func(it models.ScanItem) bool {
			c := strings.ToLower(it.Category)
			id := strings.ToLower(it.ID)
			p := strings.ToLower(it.Path)
			return strings.Contains(c, "container") || strings.Contains(id, "docker") ||
				strings.Contains(id, "podman") || strings.Contains(id, "containerd") ||
				strings.Contains(p, "docker") || strings.Contains(id, "colima")
		}))

	add("build-cache", "Overlapping build / compiler caches",
		"Clear stale build caches after switching toolchains or branches.",
		filter(items, func(it models.ScanItem) bool {
			id := strings.ToLower(it.ID)
			p := strings.ToLower(it.Path)
			return strings.Contains(id, "gradle") || strings.Contains(id, "cargo") ||
				strings.Contains(id, "ccache") || strings.Contains(id, "bazel") ||
				strings.Contains(p, ".gradle") || strings.Contains(p, "deriveddata") ||
				strings.Contains(p, "target/debug") || strings.Contains(id, "turbo") ||
				strings.Contains(id, "next-cache")
		}))

	// Same basename under different parents with similar sizes (±35%).
	byBase := map[string][]models.ScanItem{}
	for _, it := range items {
		if it.SizeBytes < 100_000_000 {
			continue
		}
		base := strings.ToLower(filepath.Base(it.Path))
		if base == "" || base == "." || base == "cache" || base == "caches" {
			continue
		}
		byBase[base] = append(byBase[base], it)
	}
	for base, list := range byBase {
		if len(list) < 2 {
			continue
		}
		// Cluster by similar size
		for _, cluster := range sizeClusters(list, 0.35) {
			if len(cluster) < 2 {
				continue
			}
			add("same-name", "Same folder name in multiple places: "+base,
				"Compare dates and keep the copy you still use.", cluster)
		}
	}

	// Same category + similar leaf names
	byCatLeaf := map[string][]models.ScanItem{}
	for _, it := range items {
		if it.SizeBytes < 50_000_000 {
			continue
		}
		leaf := normalizeLeaf(filepath.Base(it.Path))
		key := strings.ToLower(it.Category) + "|" + leaf
		byCatLeaf[key] = append(byCatLeaf[key], it)
	}
	for key, list := range byCatLeaf {
		if len(list) < 2 {
			continue
		}
		parts := strings.SplitN(key, "|", 2)
		label := "Repeated " + parts[1] + " under " + parts[0]
		add("category-leaf", label, "These look like parallel installs of the same tool cache.", list)
	}

	// Sort groups by waste descending
	sort.Slice(groups, func(i, j int) bool {
		return groups[i].WasteBytes > groups[j].WasteBytes
	})
	return dedupeGroups(groups)
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
			if used[j] {
				continue
			}
			other := float64(sorted[j].SizeBytes)
			if ref == 0 {
				continue
			}
			diff := abs(ref-other) / ref
			if diff <= tol {
				cluster = append(cluster, sorted[j])
				used[j] = true
			}
		}
		clusters = append(clusters, cluster)
	}
	return clusters
}

func normalizeLeaf(s string) string {
	s = strings.ToLower(s)
	s = strings.TrimSuffix(s, ".cache")
	s = strings.ReplaceAll(s, "_", "-")
	return s
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
		key := g.Kind + ":" + strings.Join(ids, ",")
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
