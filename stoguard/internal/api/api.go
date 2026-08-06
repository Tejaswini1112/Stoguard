package api

import (
	"encoding/json"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/stoguard/stoguard/internal/agenttools"
	"github.com/stoguard/stoguard/internal/chat"
	"github.com/stoguard/stoguard/internal/doctor"
	"github.com/stoguard/stoguard/internal/duplicates"
	"github.com/stoguard/stoguard/internal/fleet"
	"github.com/stoguard/stoguard/internal/history"
	"github.com/stoguard/stoguard/internal/intelligence"
	"github.com/stoguard/stoguard/internal/media"
	"github.com/stoguard/stoguard/internal/models"
	"github.com/stoguard/stoguard/internal/packages"
	"github.com/stoguard/stoguard/internal/platform"
	"github.com/stoguard/stoguard/internal/scanner"
	"github.com/stoguard/stoguard/internal/tier"
	"github.com/stoguard/stoguard/internal/trash"
)

type Server struct {
	RulesDir string
	APIKey   string // if set, require X-Stoguard-Key on /api/* (except /api/status)
	Engine   *scanner.Engine
	mu       sync.RWMutex
	last     *models.ScanResult
	lastDoc  *models.DoctorReport
	hist     *history.Store
}

func New(rulesDir string) *Server {
	return &Server{
		RulesDir: rulesDir,
		Engine:   scanner.New(rulesDir),
		hist:     history.Load(),
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/status", s.handleStatus)
	mux.HandleFunc("/api/tier", s.handleTier)
	mux.HandleFunc("/api/scan", s.handleScan)
	mux.HandleFunc("/api/doctor", s.handleDoctor)
	mux.HandleFunc("/api/history", s.handleHistory)
	mux.HandleFunc("/api/duplicates", s.handleDuplicates)
	mux.HandleFunc("/api/models", s.handleModels)
	mux.HandleFunc("/api/packages", s.handlePackages)
	mux.HandleFunc("/api/agent-tools", s.handleAgentTools)
	mux.HandleFunc("/api/trash", s.handleTrash)
	mux.HandleFunc("/api/ask", s.handleAsk)
	mux.HandleFunc("/api/reveal", s.handleReveal)
	mux.HandleFunc("/api/reset-adaptive", s.handleResetAdaptive)
	mux.HandleFunc("/api/fleet", s.handleFleet)
	mux.HandleFunc("/api/fleet/ingest", s.handleFleetIngest)
	mux.HandleFunc("/api/fleet/export", s.handleFleetExport)
	mux.HandleFunc("/api/fleet/summary", s.handleFleetSummary)
	mux.HandleFunc("/api/fleet/delete", s.handleFleetDelete)
	mux.HandleFunc("/api/intelligence", s.handleIntelligence)
	mux.HandleFunc("/api/automation", s.handleAutomation)
	mux.HandleFunc("/api/preference", s.handlePreference)
	mux.HandleFunc("/api/learning", s.handleLearning)
	mux.HandleFunc("/api/media", s.handleMedia)
	mux.HandleFunc("/api/cohort", s.handleCohort)
	return s.withAPIKey(mux)
}

func (s *Server) withAPIKey(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.APIKey == "" || r.URL.Path == "/api/status" || !strings.HasPrefix(r.URL.Path, "/api/") {
			next.ServeHTTP(w, r)
			return
		}
		key := r.Header.Get("X-Stoguard-Key")
		if key == "" {
			key = r.URL.Query().Get("key")
		}
		if key != s.APIKey {
			http.Error(w, "unauthorized — set X-Stoguard-Key", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	info := tier.Resolve()
	sys := platform.CollectSystem()
	writeJSON(w, models.AppStatus{
		Name:     "Stoguard",
		Version:  "0.4.2",
		Platform: platform.OS(),
		OS:       runtime.GOOS,
		Arch:     runtime.GOARCH,
		Home:     platform.Home(),
		DataDir:  platform.DataDir(),
		Tier:     string(info.Tier),
		TierName: info.DisplayName,
		Features: info.Features,
		System:   sys,
	})
}

func (s *Server) handleTier(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, tier.Refresh())
}

func (s *Server) handleScan(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	result, err := s.Engine.Scan()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	doc := doctor.Build(result, s.hist)
	_ = s.hist.Append(history.FromScan(result))

	s.mu.Lock()
	s.last = result
	s.lastDoc = &doc
	s.mu.Unlock()

	writeJSON(w, map[string]any{
		"scan":   result,
		"doctor": doc,
		"tier":   tier.Resolve(),
	})
}

func (s *Server) handleDoctor(w http.ResponseWriter, r *http.Request) {
	if !tier.Allows("doctor") {
		http.Error(w, "Workstation Doctor requires Pro or Team", http.StatusPaymentRequired)
		return
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.lastDoc == nil {
		http.Error(w, "run a scan first", 400)
		return
	}
	writeJSON(w, s.lastDoc)
}

func (s *Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, s.hist.Entries)
}

func (s *Server) handleDuplicates(w http.ResponseWriter, r *http.Request) {
	if !tier.Allows("duplicates") {
		http.Error(w, "Duplicates requires Pro or Team", http.StatusPaymentRequired)
		return
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.last == nil {
		http.Error(w, "run a scan first", 400)
		return
	}
	writeJSON(w, duplicates.Find(s.last.Items))
}

func (s *Server) handleModels(w http.ResponseWriter, r *http.Request) {
	if !tier.Allows("models") {
		http.Error(w, "AI model inventory requires Pro or Team", http.StatusPaymentRequired)
		return
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.last == nil {
		http.Error(w, "run a scan first", 400)
		return
	}
	writeJSON(w, models.AIModelPaths(s.last.Items))
}

func (s *Server) handlePackages(w http.ResponseWriter, r *http.Request) {
	if !tier.Allows("packages") {
		http.Error(w, "Package Finder requires Pro or Team", http.StatusPaymentRequired)
		return
	}
	writeJSON(w, packages.Scan())
}

func (s *Server) handleAgentTools(w http.ResponseWriter, r *http.Request) {
	if !tier.Allows("agent_tools") {
		http.Error(w, "AI Skills & MCP requires Pro or Team", http.StatusPaymentRequired)
		return
	}
	writeJSON(w, agenttools.Scan())
}

func (s *Server) handleTrash(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		Path string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Path == "" {
		http.Error(w, "path required", 400)
		return
	}
	if err := trash.Move(body.Path); err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	// Learn from cleans when we can map path → last scan item id.
	s.mu.RLock()
	last := s.last
	s.mu.RUnlock()
	if last != nil {
		for _, it := range last.Items {
			if it.Path == body.Path {
				_ = intelligence.RecordClean(it.ID)
				break
			}
		}
	}
	writeJSON(w, map[string]string{"status": "ok"})
}

func (s *Server) handleAsk(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !tier.Allows("ask") {
		http.Error(w, "Ask Stoguard requires Pro or Team", http.StatusPaymentRequired)
		return
	}
	var body struct {
		Question string `json:"question"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Question == "" {
		http.Error(w, "question required", 400)
		return
	}
	s.mu.RLock()
	scan := s.last
	doc := s.lastDoc
	s.mu.RUnlock()
	if scan == nil {
		http.Error(w, "run a scan first", 400)
		return
	}
	answer, err := chat.Answer(body.Question, scan, doc)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, map[string]string{"answer": answer})
}

func (s *Server) handleReveal(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		http.Error(w, "path required", 400)
		return
	}
	if _, err := os.Stat(path); err != nil {
		http.Error(w, "missing", 404)
		return
	}
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", "-R", path)
	case "windows":
		// explorer requires /select,PATH as one argument (no space after comma).
		cmd = exec.Command("explorer", "/select,"+filepath.Clean(path))
	default:
		cmd = exec.Command("xdg-open", filepath.Dir(path))
	}
	_ = cmd.Start()
	writeJSON(w, map[string]string{"status": "ok"})
}

func (s *Server) handleResetAdaptive(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	s.Engine.Profile.Reset()
	_ = s.Engine.Profile.Save()
	writeJSON(w, map[string]string{"status": "ok"})
}

func (s *Server) handleFleet(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !tier.Allows("fleet_admin") {
		http.Error(w, "Team fleet console requires Team tier", http.StatusPaymentRequired)
		return
	}
	list, err := fleet.List()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, list)
}

func (s *Server) handleFleetIngest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !tier.Allows("fleet_admin") {
		http.Error(w, "Fleet ingest requires Team tier", http.StatusPaymentRequired)
		return
	}
	var report models.FleetReport
	if err := json.NewDecoder(r.Body).Decode(&report); err != nil {
		http.Error(w, "invalid fleet JSON", 400)
		return
	}
	// If body empty-ish, fall back to last local scan
	if report.Hostname == "" && report.Reclaimable == 0 {
		s.mu.RLock()
		last := s.last
		s.mu.RUnlock()
		if last != nil {
			report = fleet.FromScan(last)
		}
	}
	machine, err := fleet.Ingest(report)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, machine)
}

func (s *Server) handleFleetExport(w http.ResponseWriter, r *http.Request) {
	if !tier.Allows("fleet_export") {
		http.Error(w, "Fleet export requires Pro or Team", http.StatusPaymentRequired)
		return
	}
	s.mu.RLock()
	last := s.last
	s.mu.RUnlock()
	if last == nil {
		http.Error(w, "run a scan first", 400)
		return
	}
	writeJSON(w, fleet.FromScan(last))
}

func (s *Server) handleFleetSummary(w http.ResponseWriter, r *http.Request) {
	if !tier.Allows("fleet_admin") {
		http.Error(w, "Team fleet console requires Team tier", http.StatusPaymentRequired)
		return
	}
	sum, err := fleet.Summary()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, sum)
}

func (s *Server) handleFleetDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodDelete {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if !tier.Allows("fleet_admin") {
		http.Error(w, "Team fleet console requires Team tier", http.StatusPaymentRequired)
		return
	}
	id := r.URL.Query().Get("id")
	if id == "" {
		var body struct {
			ID string `json:"id"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		id = body.ID
	}
	if id == "" {
		http.Error(w, "missing id", 400)
		return
	}
	if err := fleet.Delete(id); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	writeJSON(w, map[string]string{"status": "ok"})
}

func (s *Server) handleCohort(w http.ResponseWriter, r *http.Request) {
	auto := intelligence.LoadAutomation()
	if !auto.CloudOptIn {
		writeJSON(w, map[string]any{"enabled": false, "benchmarks": []any{}})
		return
	}
	s.mu.RLock()
	last := s.last
	s.mu.RUnlock()
	writeJSON(w, map[string]any{
		"enabled":    true,
		"benchmarks": intelligence.BenchmarksPublic(last, true),
		"note":       "Baselines + fleet-peer averages. Optional remote feed via STOGUARD_COHORT_FEED.",
	})
}

func (s *Server) handleIntelligence(w http.ResponseWriter, r *http.Request) {
	s.mu.RLock()
	last := s.last
	s.mu.RUnlock()
	writeJSON(w, intelligence.Build(last, s.hist.Entries))
}

func (s *Server) handleLearning(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, intelligence.Articles())
}

func (s *Server) handleMedia(w http.ResponseWriter, r *http.Request) {
	assets := media.Scan(200)
	writeJSON(w, map[string]any{
		"assets": assets,
		"note":   "Detection is cross-platform. Approve-and-optimize (keep resolution or target KB/MB/GB/TB) runs in the native macOS Media Optimizer.",
	})
}

func (s *Server) handleAutomation(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, intelligence.LoadAutomation())
	case http.MethodPost:
		var body intelligence.AutomationStore
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "invalid automation JSON", 400)
			return
		}
		if err := intelligence.SaveAutomation(body); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		writeJSON(w, body)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Server) handlePreference(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		ID     string `json:"id"`
		Action string `json:"action"` // keep | clean
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.ID == "" {
		http.Error(w, "id and action required", 400)
		return
	}
	var prefs intelligence.PreferenceMemory
	switch body.Action {
	case "keep":
		prefs = intelligence.RecordKeep(body.ID)
	case "clean":
		prefs = intelligence.RecordClean(body.ID)
	default:
		http.Error(w, "action must be keep or clean", 400)
		return
	}
	writeJSON(w, prefs)
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}
