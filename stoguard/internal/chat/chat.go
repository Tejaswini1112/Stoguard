package chat

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/stoguard/stoguard/internal/intelligence"
	"github.com/stoguard/stoguard/internal/models"
)

const ollamaURL = "http://127.0.0.1:11434/api/chat"

// Answer grounds a natural-language question in scan facts. Uses Ollama when available.
func Answer(question string, result *models.ScanResult, doctor *models.DoctorReport) (string, error) {
	facts := buildFacts(result, doctor)
	prompt := fmt.Sprintf(`You are Stoguard, an AI mentor for developer workstations.
Only use the FACTS below. Do not invent sizes. Teach clearly: what something is, why it grew, whether delete is safe, and what happens after.

FACTS:
%s

USER: %s`, facts, question)

	if reply, err := askOllama(prompt); err == nil && strings.TrimSpace(reply) != "" {
		return reply, nil
	}
	return localAnswer(question, result, doctor), nil
}

func buildFacts(result *models.ScanResult, doctor *models.DoctorReport) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Platform: %s\n", result.Platform)
	fmt.Fprintf(&b, "Scan total: %d bytes\n", result.TotalBytes)
	fmt.Fprintf(&b, "Safe reclaimable: %d bytes\n", result.SafeBytes)
	fmt.Fprintf(&b, "Review reclaimable: %d bytes\n", result.CheckBytes)
	fmt.Fprintf(&b, "Free disk: %d / %d bytes\n", result.FreeBytes, result.DiskTotalBytes)
	snap := intelligence.Build(result, nil)
	fmt.Fprintf(&b, "Health: %d/100 — %s\n", snap.Health.Overall, snap.Health.Headline)
	for _, p := range snap.Predictive {
		fmt.Fprintf(&b, "Forecast: %s — %s\n", p.Title, p.Body)
	}
	b.WriteString("Top items:\n")
	for i, it := range result.Items {
		if i >= 15 {
			break
		}
		fmt.Fprintf(&b, "- %s (%s): %d bytes; safety=%s; note=%s\n",
			it.Name, it.Category, it.SizeBytes, it.Safety, it.Note)
	}
	if doctor != nil {
		fmt.Fprintf(&b, "Doctor headline: %s\n", doctor.Headline)
	}
	return b.String()
}

func askOllama(prompt string) (string, error) {
	body := map[string]any{
		"model":  "llama3.2",
		"stream": false,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
	}
	raw, _ := json.Marshal(body)
	client := &http.Client{Timeout: 12 * time.Second}
	resp, err := client.Post(ollamaURL, "application/json", bytes.NewReader(raw))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("ollama status %d", resp.StatusCode)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	var parsed struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	}
	if err := json.Unmarshal(data, &parsed); err != nil {
		return "", err
	}
	return parsed.Message.Content, nil
}

func localAnswer(question string, result *models.ScanResult, doctor *models.DoctorReport) string {
	q := strings.ToLower(question)
	if a := intelligence.ArticleMatching(q); a != nil &&
		(strings.Contains(q, "what") || strings.Contains(q, "explain") || strings.Contains(q, "teach") || strings.Contains(q, "when") || strings.Contains(q, "derived") || strings.Contains(q, "docker")) {
		return fmt.Sprintf("%s — teacher mode\n\nWhat it is:\n%s\n\nWhy it exists:\n%s\n\nWhy cleanup can be safe:\n%s\n\nWhen to delete:\n%s\n\nAfter deletion:\n%s",
			a.Title, a.What, a.WhyCreated, a.WhySafe, a.WhenDelete, a.AfterDelete)
	}
	if strings.Contains(q, "health") || strings.Contains(q, "score") {
		snap := intelligence.Build(result, nil)
		var b strings.Builder
		fmt.Fprintf(&b, "Health score: %d/100\n%s\n", snap.Health.Overall, snap.Health.Headline)
		for _, d := range snap.Health.Dimensions {
			fmt.Fprintf(&b, "• %s: %d — %s\n", d.Name, d.Score, d.Detail)
		}
		return b.String()
	}
	if strings.Contains(q, "forecast") || strings.Contains(q, "fill") || strings.Contains(q, "predict") {
		snap := intelligence.Build(result, nil)
		var b strings.Builder
		for _, p := range snap.Predictive {
			fmt.Fprintf(&b, "• %s\n  %s\n", p.Title, p.Body)
		}
		if b.Len() == 0 {
			return "Need more scan history for forecasts — run Scan again over a few days."
		}
		return b.String()
	}
	if strings.Contains(q, "cleanup sequence") || strings.Contains(q, "safest") || strings.Contains(q, "clean first") {
		return cleanupSequence(result)
	}
	if strings.Contains(q, "safe to delete") || strings.Contains(q, "can i delete") || strings.Contains(q, "will deleting") {
		return safeDelete(q, result)
	}

	var b strings.Builder
	if doctor != nil {
		b.WriteString(doctor.Headline + "\n\n")
	}
	if strings.Contains(q, "slow") || strings.Contains(q, "full") || strings.Contains(q, "ssd") {
		b.WriteString("Largest reclaimable areas from your last scan:\n")
	} else {
		b.WriteString("Based on your scan:\n")
	}
	for i, it := range result.Items {
		if i >= 5 {
			break
		}
		fmt.Fprintf(&b, "• %s — %.1f GB (%s)\n", it.Name, float64(it.SizeBytes)/1e9, it.Safety)
	}
	if result.SafeBytes > 0 {
		fmt.Fprintf(&b, "\nSafe to clean first: about %.1f GB.\n", float64(result.SafeBytes)/1e9)
	}
	b.WriteString("\nAsk me to explain DerivedData, Docker, or Ollama — or “what’s the safest cleanup sequence?”")
	return b.String()
}

func cleanupSequence(result *models.ScanResult) string {
	var safe, cmds, check []models.ScanItem
	for _, it := range result.Items {
		switch it.Safety {
		case models.SafetySafe:
			safe = append(safe, it)
		case models.SafetyCommand:
			cmds = append(cmds, it)
		case models.SafetyCheck:
			check = append(check, it)
		}
	}
	var b strings.Builder
	b.WriteString("Safest cleanup sequence (from your scan):\n\n1) Safe rebuildable caches:\n")
	for i, it := range safe {
		if i >= 5 {
			break
		}
		fmt.Fprintf(&b, "   • %s — %.1f GB\n", it.Name, float64(it.SizeBytes)/1e9)
	}
	b.WriteString("\n2) Tool CLIs (don’t delete VM disks by hand):\n")
	for i, it := range cmds {
		if i >= 4 {
			break
		}
		fmt.Fprintf(&b, "   • %s — %s\n", it.Name, it.Command)
	}
	b.WriteString("\n3) Review check-first items last.\nNothing is permanent until you empty Trash/Recycle Bin.")
	return b.String()
}

func safeDelete(q string, result *models.ScanResult) string {
	for _, it := range result.Items {
		name := strings.ToLower(it.Name)
		if strings.Contains(q, name) || (strings.Contains(q, "docker") && strings.Contains(name, "docker")) ||
			(strings.Contains(q, "derived") && strings.Contains(name, "derived")) {
			return fmt.Sprintf("Can you delete %s (%.1f GB)?\n\nSafety: %s\nWhat it is: %s\n\nPrefer Trash/OS recycle — recoverable until emptied.",
				it.Name, float64(it.SizeBytes)/1e9, it.Safety, it.Note)
		}
	}
	if a := intelligence.ArticleMatching(q); a != nil {
		return fmt.Sprintf("%s\n\nWhen to delete: %s\nAfter: %s", a.Title, a.WhenDelete, a.AfterDelete)
	}
	return fmt.Sprintf("Name a folder from your scan. About %.1f GB is labeled safe overall.", float64(result.SafeBytes)/1e9)
}
