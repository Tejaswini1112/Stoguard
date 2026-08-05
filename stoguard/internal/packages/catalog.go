package packages

import "strings"

// Definition returns a plain-English explanation of what a package is for.
func Definition(name, source string) string {
	key := strings.ToLower(strings.TrimSpace(name))
	if d, ok := catalog[key]; ok {
		return d
	}
	if i := strings.LastIndex(key, "/"); i >= 0 {
		if d, ok := catalog[key[i+1:]]; ok {
			return d
		}
	}
	switch strings.ToLower(source) {
	case "homebrew":
		return "Homebrew formula — a command-line tool or library installed via brew."
	case "npm global":
		return "Global Node.js package — a CLI or tooling installed with npm for use across projects."
	case "pipx":
		return "Isolated Python CLI app installed with pipx (keeps its own virtualenv)."
	case "cargo bin":
		return "Rust binary installed with cargo (often a CLI utility)."
	case "user bin":
		return "Executable on your PATH under ~/.local/bin — usually a developer CLI you installed manually."
	case "windows programs":
		return "Application installed under Local\\Programs. Review whether you still use it."
	default:
		return "Installed developer package. Review whether you still use “" + name + "” before removing it."
	}
}

var catalog = map[string]string{
	"strix":        "AI-assisted penetration testing / security assessment CLI.",
	"nmap":         "Network scanner — discovers hosts and open ports.",
	"nikto":        "Web server vulnerability scanner.",
	"sqlmap":       "Automated SQL injection and database takeover tool.",
	"hydra":        "Password cracking / login brute-force utility.",
	"john":         "John the Ripper — offline password cracker.",
	"hashcat":      "Advanced password recovery / hash cracking GPU tool.",
	"wireshark":    "Packet capture and network protocol analyzer.",
	"tcpdump":      "Command-line packet capture utility.",
	"ffuf":         "Web fuzzer for directories, vhosts, and parameters.",
	"gobuster":     "Directory/DNS/vhost brute-forcing tool.",
	"nuclei":       "Template-based vulnerability scanner (ProjectDiscovery).",
	"httpx":        "HTTP probing toolkit (ProjectDiscovery).",
	"subfinder":    "Passive subdomain discovery tool.",
	"node":         "Node.js JavaScript runtime — runs JS apps and tooling.",
	"python":       "Python language runtime.",
	"python@3.11":  "Python 3.11 runtime (Homebrew versioned formula).",
	"python@3.12":  "Python 3.12 runtime (Homebrew versioned formula).",
	"python@3.13":  "Python 3.13 runtime (Homebrew versioned formula).",
	"go":           "Go programming language toolchain (compiler + tools).",
	"rust":         "Rust programming language metapackage.",
	"rustup":       "Rust toolchain installer and version manager.",
	"ruby":         "Ruby language runtime.",
	"php":          "PHP language runtime.",
	"openjdk":      "OpenJDK Java Development Kit.",
	"temurin":      "Eclipse Temurin OpenJDK builds.",
	"git":          "Distributed version control system.",
	"gh":           "GitHub’s official command-line client.",
	"glab":         "GitLab’s official command-line client.",
	"wget":         "Non-interactive network downloader.",
	"curl":         "Transfer data with URLs (HTTP/FTP/etc.).",
	"jq":           "Command-line JSON processor.",
	"yq":           "Command-line YAML/JSON/XML processor.",
	"tmux":         "Terminal multiplexer — split panes and persist sessions.",
	"neovim":       "Modern Vim-based text editor.",
	"vim":          "Classic modal text editor.",
	"ffmpeg":       "Audio/video conversion and streaming toolkit.",
	"imagemagick":  "Image conversion and editing command-line suite.",
	"cmake":        "Cross-platform build system generator.",
	"ninja":        "Small, fast build system.",
	"make":         "GNU Make build automation tool.",
	"docker":       "Container runtime and CLI.",
	"colima":       "Container runtimes on macOS with minimal setup.",
	"kubectl":      "Kubernetes command-line tool.",
	"helm":         "Kubernetes package manager.",
	"terraform":    "Infrastructure as code by HashiCorp.",
	"ansible":      "IT automation / configuration management.",
	"awscli":       "AWS official command-line interface.",
	"azure-cli":    "Microsoft Azure command-line tools.",
	"gcloud":       "Google Cloud CLI.",
	"ollama":       "Run large language models locally.",
	"huggingface-cli": "Hugging Face Hub CLI for models and datasets.",
	"typescript":   "TypeScript language compiler (tsc).",
	"eslint":       "JavaScript/TypeScript linter.",
	"prettier":     "Opinionated code formatter.",
	"yarn":         "JavaScript package manager.",
	"pnpm":         "Fast, disk-efficient JavaScript package manager.",
	"npm":          "Node package manager (usually comes with Node).",
	"vite":         "Frontend build tool and dev server.",
	"webpack":      "JavaScript module bundler.",
	"next":         "Next.js React framework CLI.",
	"create-react-app": "Scaffold a React app (often obsolete vs Vite).",
	"vercel":       "Vercel deployment CLI.",
	"supabase":     "Supabase project management CLI.",
	"firebase-tools": "Firebase CLI for hosting, functions, etc.",
	"expo-cli":     "Expo React Native toolchain (legacy package name).",
	"eas-cli":      "Expo Application Services CLI.",
	"black":        "Python code formatter.",
	"ruff":         "Extremely fast Python linter/formatter.",
	"poetry":       "Python dependency and packaging manager.",
	"pipenv":       "Python virtualenv + Pipfile manager.",
	"httpie":       "User-friendly HTTP client.",
	"http":         "HTTPie CLI binary name.",
	"bat":          "cat clone with syntax highlighting.",
	"fd":           "Fast, user-friendly find alternative.",
	"ripgrep":      "Fast recursive search (rg).",
	"rg":           "ripgrep binary — fast recursive search.",
	"fzf":          "Command-line fuzzy finder.",
	"tree":         "Display directories as trees.",
	"htop":         "Interactive process viewer.",
	"btop":         "Resource monitor with a modern TUI.",
	"watch":        "Run a command repeatedly, show output.",
	"redis":        "In-memory data store / cache server.",
	"postgresql":   "PostgreSQL database server.",
	"mysql":        "MySQL database server.",
	"sqlite":       "Embedded SQL database engine.",
	"mongodb-community": "MongoDB community edition.",
	"nginx":        "High-performance HTTP server and reverse proxy.",
	"caddy":        "Automatic-HTTPS web server.",
}
