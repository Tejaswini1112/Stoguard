package scanner

import (
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/stoguard/stoguard/internal/adaptive"
	"github.com/stoguard/stoguard/internal/fingerprint"
	"github.com/stoguard/stoguard/internal/models"
	"github.com/stoguard/stoguard/internal/platform"
	"github.com/stoguard/stoguard/internal/rules"
)

const maxChildren = 5

// Windows NTFS + Defender make unbounded WalkDir extremely slow.
// Cap depth / files / wall time so a scan finishes in seconds–tens of seconds.
const (
	maxWalkDepth     = 10
	maxWalkFiles     = 120_000
	maxWalkDuration  = 8 * time.Second
	maxCommandDepth  = 4
	maxCommandFiles  = 8_000
	maxCommandDur    = 3 * time.Second
	maxChildWalkDur  = 2 * time.Second
	maxChildFiles    = 20_000
)

type Engine struct {
	RulesDir string
	Profile  *adaptive.Profile
	Cache    *fingerprint.Cache
}

func New(rulesDir string) *Engine {
	return &Engine{
		RulesDir: rulesDir,
		Profile:  adaptive.Load(),
		Cache:    fingerprint.Load(),
	}
}

func (e *Engine) Scan() (*models.ScanResult, error) {
	list, err := rules.LoadAll(e.RulesDir)
	if err != nil {
		return nil, err
	}

	e.Profile.BeginScan()
	var skipped int32
	var cachedHits int32

	type job struct {
		rule models.Rule
		path string
	}
	jobs := make([]job, 0, len(list))
	seenPaths := map[string]struct{}{}
	for _, r := range list {
		if !e.Profile.ShouldScan(r.ID) {
			atomic.AddInt32(&skipped, 1)
			continue
		}
		path := platform.ExpandPath(r.Path)
		if path == "" {
			continue
		}
		// Deduplicate identical expanded paths (e.g. Temp vs %TEMP%).
		key := filepath.Clean(path)
		if runtime.GOOS == "windows" {
			key = filepath.Clean(path)
			// case-insensitive dedupe
			key = stringLower(key)
		}
		if _, ok := seenPaths[key]; ok {
			continue
		}
		seenPaths[key] = struct{}{}
		jobs = append(jobs, job{rule: r, path: path})
	}

	items := make([]models.ScanItem, 0, len(jobs))
	var mu sync.Mutex
	var wg sync.WaitGroup
	workers := 12
	if runtime.GOOS == "windows" {
		workers = 3 // fewer parallel walks → less Defender thrash
	}
	sem := make(chan struct{}, workers)

	for _, j := range jobs {
		j := j
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			info, err := os.Lstat(j.path)
			if err != nil {
				e.Profile.RecordMiss(j.rule.ID)
				return
			}
			e.Profile.RecordHit(j.rule.ID)

			item := models.ScanItem{
				ID:       j.rule.ID,
				Name:     j.rule.Name,
				Path:     j.path,
				Category: j.rule.Category,
				Safety:   j.rule.Safety,
				Note:     j.rule.Note,
				Command:  j.rule.Command,
				Known:    true,
			}

			if size, ok := e.Cache.CachedSize(j.rule.ID, j.path); ok {
				item.SizeBytes = size
				item.FromCache = true
				atomic.AddInt32(&cachedHits, 1)
			} else {
				item.SizeBytes = measure(j.path, j.rule.Safety)
				e.Cache.Store(j.rule.ID, j.path, item.SizeBytes)
			}

			if act := lastActivity(j.path, info); act != nil {
				item.LastActivity = act
				days := int(time.Since(*act).Hours() / 24)
				if days < 0 {
					days = 0
				}
				item.DaysUnused = &days
			}
			// Skip expensive child rewalks on Windows unless huge + not command.
			if item.SizeBytes >= 400_000_000 && j.rule.Safety != models.SafetyCommand {
				if runtime.GOOS != "windows" || item.SizeBytes >= 2_000_000_000 {
					item.Children = largestChildren(j.path, maxChildren)
				}
			}

			if item.SizeBytes <= 0 {
				return
			}
			mu.Lock()
			items = append(items, item)
			mu.Unlock()
		}()
	}
	wg.Wait()

	_ = e.Profile.Save()
	_ = e.Cache.Save()

	sort.Slice(items, func(i, j int) bool { return items[i].SizeBytes > items[j].SizeBytes })

	var total, safe, check int64
	cats := map[string]int64{}
	for _, it := range items {
		total += it.SizeBytes
		cats[it.Category] += it.SizeBytes
		switch it.Safety {
		case models.SafetySafe:
			safe += it.SizeBytes
		case models.SafetyCheck:
			check += it.SizeBytes
		}
	}

	free, diskTotal, _ := platform.DiskUsage(platform.Home())

	return &models.ScanResult{
		Platform:       platform.OS(),
		ScannedAt:      time.Now(),
		Items:          items,
		TotalBytes:     total,
		SafeBytes:      safe,
		CheckBytes:     check,
		SkippedRules:   int(skipped),
		CachedHits:     int(cachedHits),
		FreeBytes:      free,
		DiskTotalBytes: diskTotal,
		CategoryTotals: cats,
	}, nil
}

func measure(root string, safety models.Safety) int64 {
	if safety == models.SafetyCommand {
		// Prefer prune/CLI over walking VHDX trees — shallow + large-file bias.
		return walkSize(root, maxCommandDepth, maxCommandFiles, maxCommandDur)
	}
	depth := maxWalkDepth
	files := maxWalkFiles
	dur := maxWalkDuration
	if runtime.GOOS == "windows" {
		depth = 8
		files = 60_000
		dur = 6 * time.Second
	}
	return walkSize(root, depth, files, dur)
}

func walkSize(root string, maxDepth, maxFiles int, budget time.Duration) int64 {
	info, err := os.Lstat(root)
	if err != nil {
		return 0
	}
	if !info.IsDir() {
		return info.Size()
	}

	deadline := time.Now().Add(budget)
	var total int64
	var files int
	rootDepth := depthOf(root)

	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if time.Now().After(deadline) || files >= maxFiles {
			return fs.SkipAll
		}
		if d.IsDir() {
			if path != root && depthOf(path)-rootDepth > maxDepth {
				return fs.SkipDir
			}
			// Skip symlinks / reparse points (WSL mounts, junctions) — they explode walks.
			if (d.Type()&os.ModeSymlink) != 0 || isReparseDir(path, d) {
				if path != root {
					return fs.SkipDir
				}
			}
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		total += info.Size()
		files++
		return nil
	})
	return total
}

func depthOf(p string) int {
	clean := filepath.Clean(p)
	if clean == "" || clean == string(filepath.Separator) {
		return 0
	}
	n := 0
	for _, c := range clean {
		if c == filepath.Separator {
			n++
		}
	}
	return n
}

func stringLower(s string) string {
	b := make([]byte, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		b[i] = c
	}
	return string(b)
}

func lastActivity(path string, info os.FileInfo) *time.Time {
	t := info.ModTime()
	return &t
}

func largestChildren(root string, n int) []models.LargeChild {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	type pair struct {
		name string
		path string
		size int64
	}
	var list []pair
	for _, e := range entries {
		p := filepath.Join(root, e.Name())
		var size int64
		if e.IsDir() {
			size = walkSize(p, 6, maxChildFiles, maxChildWalkDur)
		} else if info, err := e.Info(); err == nil {
			size = info.Size()
		}
		if size <= 0 {
			continue
		}
		list = append(list, pair{e.Name(), p, size})
	}
	sort.Slice(list, func(i, j int) bool { return list[i].size > list[j].size })
	if len(list) > n {
		list = list[:n]
	}
	out := make([]models.LargeChild, 0, len(list))
	for _, p := range list {
		out = append(out, models.LargeChild{Name: p.name, Path: p.path, SizeBytes: p.size})
	}
	return out
}
