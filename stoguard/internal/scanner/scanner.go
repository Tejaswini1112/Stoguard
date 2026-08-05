package scanner

import (
	"io/fs"
	"os"
	"path/filepath"
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
	for _, r := range list {
		if !e.Profile.ShouldScan(r.ID) {
			atomic.AddInt32(&skipped, 1)
			continue
		}
		path := platform.ExpandPath(r.Path)
		if path == "" {
			continue
		}
		jobs = append(jobs, job{rule: r, path: path})
	}

	items := make([]models.ScanItem, 0, len(jobs))
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 12)

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
				item.SizeBytes = dirSize(j.path)
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
			if item.SizeBytes >= 400_000_000 {
				item.Children = largestChildren(j.path, maxChildren)
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

func dirSize(root string) int64 {
	var total int64
	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return nil
		}
		total += info.Size()
		return nil
	})
	return total
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
			size = dirSize(p)
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
