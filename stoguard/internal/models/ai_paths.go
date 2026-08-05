package models

import "strings"

// AIModelPaths extracts AI model-related scan items with a provider label.
func AIModelPaths(items []ScanItem) []ModelPath {
	out := []ModelPath{}
	for _, it := range items {
		if !isAIModelItem(it) {
			continue
		}
		out = append(out, ModelPath{
			ID:        it.ID,
			Name:      it.Name,
			Path:      it.Path,
			Category:  it.Category,
			SizeBytes: it.SizeBytes,
			Safety:    it.Safety,
			Note:      it.Note,
			Provider:  detectProvider(it),
		})
	}
	return out
}

func isAIModelItem(it ScanItem) bool {
	c := strings.ToLower(it.Category)
	id := strings.ToLower(it.ID)
	p := strings.ToLower(it.Path)
	n := strings.ToLower(it.Name)
	needles := []string{
		"ollama", "huggingface", "lmstudio", "lm-studio", "comfy",
		"gguf", "stable-diffusion", "whisper", "llama", "mlx",
	}
	blob := c + " " + id + " " + p + " " + n
	if strings.Contains(c, "ai") || strings.Contains(c, "model") {
		return true
	}
	for _, needle := range needles {
		if strings.Contains(blob, needle) {
			return true
		}
	}
	return false
}

func detectProvider(it ScanItem) string {
	blob := strings.ToLower(it.ID + " " + it.Path + " " + it.Name + " " + it.Category)
	switch {
	case strings.Contains(blob, "ollama"):
		return "Ollama"
	case strings.Contains(blob, "huggingface") || strings.Contains(blob, "hugging-face"):
		return "Hugging Face"
	case strings.Contains(blob, "lmstudio") || strings.Contains(blob, "lm-studio"):
		return "LM Studio"
	case strings.Contains(blob, "comfy"):
		return "ComfyUI"
	case strings.Contains(blob, "mlx"):
		return "MLX"
	case strings.Contains(blob, "gguf"):
		return "GGUF"
	default:
		return "Local AI"
	}
}
