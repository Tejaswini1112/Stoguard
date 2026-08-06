package main

import (
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/stoguard/stoguard/internal/api"
	"github.com/stoguard/stoguard/internal/fleet"
	"github.com/stoguard/stoguard/internal/platform"
)

//go:embed web
var webFS embed.FS

//go:embed rules
var rulesFS embed.FS

func main() {
	port := flag.Int("port", 8787, "UI / API port")
	bind := flag.String("bind", "127.0.0.1", "listen address (use 0.0.0.0 for LAN Team fleet server)")
	apiKey := flag.String("api-key", os.Getenv("STOGUARD_API_KEY"), "require X-Stoguard-Key on API (recommended with -bind 0.0.0.0)")
	noOpen := flag.Bool("no-open", false, "do not open the browser")
	scanOnly := flag.Bool("scan", false, "run one CLI scan and exit")
	fleetCmd := flag.String("fleet", "", "fleet CLI: list | summary | export | ingest-self")
	flag.Parse()

	rulesDir, err := materializeRules()
	if err != nil {
		fatal(err)
	}
	_ = platform.EnsureDataDir()

	srv := api.New(rulesDir)
	srv.APIKey = *apiKey

	if *fleetCmd != "" {
		runFleetCLI(srv, *fleetCmd)
		return
	}

	if *scanOnly {
		result, err := srv.Engine.Scan()
		if err != nil {
			fatal(err)
		}
		fmt.Printf("Stoguard scan (%s): %d items, %.1f GB total, %.1f GB safe\n",
			result.Platform, len(result.Items),
			float64(result.TotalBytes)/1e9, float64(result.SafeBytes)/1e9)
		for i, it := range result.Items {
			if i >= 15 {
				break
			}
			fmt.Printf("  %6.1f GB  %-28s  %s\n", float64(it.SizeBytes)/1e9, it.Name, it.Path)
		}
		return
	}

	webRoot, err := fs.Sub(webFS, "web")
	if err != nil {
		fatal(err)
	}

	apiHandler := srv.Handler()
	files := http.FileServer(http.FS(webRoot))
	root := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			apiHandler.ServeHTTP(w, r)
			return
		}
		files.ServeHTTP(w, r)
	})

	addr := fmt.Sprintf("%s:%d", *bind, *port)
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		fatal(err)
	}

	url := "http://" + addr
	if *bind == "0.0.0.0" {
		url = fmt.Sprintf("http://127.0.0.1:%d", *port)
	}
	fmt.Printf("Stoguard running on %s (listen %s) (%s/%s)\n", url, addr, runtime.GOOS, runtime.GOARCH)
	fmt.Printf("Data directory: %s\n", platform.DataDir())
	if *apiKey != "" {
		fmt.Println("API key auth enabled (X-Stoguard-Key)")
	}
	if *bind != "127.0.0.1" && *apiKey == "" {
		fmt.Println("WARNING: binding beyond localhost without -api-key is insecure")
	}

	if !*noOpen && *bind == "127.0.0.1" {
		go func() {
			time.Sleep(300 * time.Millisecond)
			openBrowser(url)
		}()
	}

	if err := http.Serve(ln, root); err != nil {
		fatal(err)
	}
}

func runFleetCLI(srv *api.Server, cmd string) {
	switch cmd {
	case "list":
		list, err := fleet.List()
		if err != nil {
			fatal(err)
		}
		for _, m := range list {
			comp := "-"
			if m.Compliance != nil {
				comp = fmt.Sprintf("%d", m.Compliance.Score)
			}
			fmt.Printf("%-20s %-8s reclaim=%.1fGB compliance=%s\n",
				m.Hostname, m.Platform, float64(m.Reclaimable)/1e9, comp)
		}
	case "summary":
		sum, err := fleet.Summary()
		if err != nil {
			fatal(err)
		}
		b, _ := json.MarshalIndent(sum, "", "  ")
		fmt.Println(string(b))
	case "export":
		result, err := srv.Engine.Scan()
		if err != nil {
			fatal(err)
		}
		rep := fleet.FromScan(result)
		b, _ := json.MarshalIndent(rep, "", "  ")
		fmt.Println(string(b))
	case "ingest-self":
		result, err := srv.Engine.Scan()
		if err != nil {
			fatal(err)
		}
		m, err := fleet.Ingest(fleet.FromScan(result))
		if err != nil {
			fatal(err)
		}
		fmt.Printf("ingested %s (%s)\n", m.Hostname, m.Platform)
	default:
		fatal(fmt.Errorf("unknown -fleet %q (list|summary|export|ingest-self)", cmd))
	}
}

func materializeRules() (string, error) {
	for _, c := range []string{"rules", filepath.Join("stoguard", "rules")} {
		if st, err := os.Stat(c); err == nil && st.IsDir() {
			a, _ := filepath.Abs(c)
			return a, nil
		}
	}
	if exe, err := os.Executable(); err == nil {
		c := filepath.Join(filepath.Dir(exe), "rules")
		if st, err := os.Stat(c); err == nil && st.IsDir() {
			return c, nil
		}
	}

	dest := filepath.Join(platform.DataDir(), "rules-bundle")
	if err := os.MkdirAll(dest, 0o755); err != nil {
		return "", err
	}
	err := fs.WalkDir(rulesFS, "rules", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel("rules", path)
		if err != nil || rel == "." {
			return err
		}
		target := filepath.Join(dest, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, err := rulesFS.ReadFile(path)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		return os.WriteFile(target, data, 0o644)
	})
	return dest, err
}

func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	_ = cmd.Start()
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "stoguard:", err)
	os.Exit(1)
}
