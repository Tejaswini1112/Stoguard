package chat

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/stoguard/stoguard/internal/models"
)

const ollamaURL = "http://127.0.0.1:11434/api/chat"

// Answer grounds a natural-language question in scan facts. Uses Ollama when available.
func Answer(question string, result *models.ScanResult, doctor *models.DoctorReport) (string, error) {
	facts := buildFacts(result, doctor)
	prompt := fmt.Sprintf(`You are Stoguard, a developer workstation assistant.
Only use the FACTS below. Do not invent sizes. Be concise.

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
	b.WriteString("\n(Tip: install Ollama locally for richer AI answers — Stoguard will use it automatically.)")
	return b.String()
}
