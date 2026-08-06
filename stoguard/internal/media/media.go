package media

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/stoguard/stoguard/internal/platform"
)

type Kind string

const (
	KindImage    Kind = "image"
	KindVideo    Kind = "video"
	KindDocument Kind = "document"
)

type Asset struct {
	ID        string `json:"id"`
	Path      string `json:"path"`
	Name      string `json:"name"`
	Kind      Kind   `json:"kind"`
	SizeBytes int64  `json:"sizeBytes"`
	Note      string `json:"note"`
}

var (
	imageExt = map[string]bool{"jpg": true, "jpeg": true, "png": true, "heic": true, "heif": true, "tif": true, "tiff": true, "bmp": true, "webp": true, "gif": true}
	videoExt = map[string]bool{"mp4": true, "mov": true, "m4v": true, "avi": true, "mkv": true, "mpg": true, "mpeg": true, "wmv": true}
	docExt   = map[string]bool{"pdf": true, "docx": true, "pptx": true, "xlsx": true, "key": true, "pages": true, "numbers": true, "zip": true, "psd": true, "ai": true}
)

const (
	minImage = 8_000_000
	minVideo = 80_000_000
	minDoc   = 15_000_000
)

func Scan(limit int) []Asset {
	if limit <= 0 {
		limit = 200
	}
	home := platform.Home()
	roots := []string{
		filepath.Join(home, "Downloads"),
		filepath.Join(home, "Documents"),
		filepath.Join(home, "Desktop"),
		filepath.Join(home, "Pictures"),
		filepath.Join(home, "Movies"),
		filepath.Join(home, "Videos"),
	}
	var out []Asset
	for _, root := range roots {
		_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			if len(out) >= limit {
				return filepath.SkipAll
			}
			name := d.Name()
			if strings.HasPrefix(name, ".") {
				return nil
			}
			ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(name), "."))
			kind, minB := classify(ext)
			if kind == "" {
				return nil
			}
			info, err := d.Info()
			if err != nil {
				return nil
			}
			sz := info.Size()
			if sz < minB {
				return nil
			}
			note := "Large " + string(kind) + " — open Media Optimizer in the macOS app to approve compression (keep resolution or target KB/MB/GB/TB)."
			out = append(out, Asset{
				ID: path, Path: path, Name: name, Kind: kind, SizeBytes: sz, Note: note,
			})
			return nil
		})
		if len(out) >= limit {
			break
		}
	}
	// Sort largest first (simple insertion for small N)
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			if out[j].SizeBytes > out[i].SizeBytes {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out
}

func classify(ext string) (Kind, int64) {
	if imageExt[ext] {
		return KindImage, minImage
	}
	if videoExt[ext] {
		return KindVideo, minVideo
	}
	if docExt[ext] {
		return KindDocument, minDoc
	}
	return "", 0
}
