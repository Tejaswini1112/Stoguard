import Foundation

/// Human-readable definitions for common developer packages so users know why they installed them.
enum PackageCatalog {
    /// Returns a short definition for a package name (brew/npm/pipx/binary).
    static func definition(for name: String, source: String) -> String {
        let key = normalize(name)
        if let exact = catalog[key] { return exact }
        // Scoped npm packages: @scope/name → try name
        if key.contains("/") {
            let short = key.split(separator: "/").last.map(String.init) ?? key
            if let d = catalog[short] { return d }
        }
        // Heuristic fallbacks by source
        switch source.lowercased() {
        case "homebrew":
            return "Homebrew formula — a command-line tool or library installed via brew. Check `brew info \(name)` for upstream docs."
        case "npm global":
            return "Global Node.js package — a CLI or tooling installed with npm for use across projects."
        case "pipx":
            return "Isolated Python CLI app installed with pipx (keeps its own virtualenv)."
        case "cargo bin":
            return "Rust binary installed with cargo (often a CLI utility)."
        case "user bin":
            return "Executable on your PATH under ~/.local/bin — usually a developer CLI you installed manually."
        default:
            return "Installed developer package. Review whether you still use “\(name)” before removing it."
        }
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Curated definitions for packages people often forget about.
    private static let catalog: [String: String] = [
        // Security / pentest
        "strix": "AI-assisted penetration testing / security assessment CLI. Large if models or scanners are bundled.",
        "nmap": "Network scanner — discovers hosts and open ports. Used for security audits and network debugging.",
        "nikto": "Web server vulnerability scanner.",
        "sqlmap": "Automated SQL injection and database takeover tool.",
        "hydra": "Password cracking / login brute-force utility.",
        "john": "John the Ripper — offline password cracker.",
        "hashcat": "Advanced password recovery / hash cracking GPU tool.",
        "wireshark": "Packet capture and network protocol analyzer.",
        "tcpdump": "Command-line packet capture utility.",
        "ffuf": "Web fuzzer for directories, vhosts, and parameters.",
        "gobuster": "Directory/DNS/vhost brute-forcing tool.",
        "nuclei": "Template-based vulnerability scanner (ProjectDiscovery).",
        "httpx": "HTTP probing toolkit (ProjectDiscovery).",
        "subfinder": "Passive subdomain discovery tool.",

        // Languages / runtimes
        "node": "Node.js JavaScript runtime — runs JS apps and tooling.",
        "python": "Python language runtime.",
        "python@3.11": "Python 3.11 runtime (Homebrew versioned formula).",
        "python@3.12": "Python 3.12 runtime (Homebrew versioned formula).",
        "python@3.13": "Python 3.13 runtime (Homebrew versioned formula).",
        "go": "Go programming language toolchain (compiler + tools).",
        "rust": "Rust programming language metapackage.",
        "rustup": "Rust toolchain installer and version manager.",
        "ruby": "Ruby language runtime.",
        "php": "PHP language runtime.",
        "openjdk": "OpenJDK Java Development Kit.",
        "temurin": "Eclipse Temurin OpenJDK builds.",

        // Dev tools
        "git": "Distributed version control system.",
        "gh": "GitHub’s official command-line client.",
        "glab": "GitLab’s official command-line client.",
        "wget": "Non-interactive network downloader.",
        "curl": "Transfer data with URLs (HTTP/FTP/etc.).",
        "jq": "Command-line JSON processor.",
        "yq": "Command-line YAML/JSON/XML processor.",
        "tmux": "Terminal multiplexer — split panes and persist sessions.",
        "neovim": "Modern Vim-based text editor.",
        "vim": "Classic modal text editor.",
        "ffmpeg": "Audio/video conversion and streaming toolkit.",
        "imagemagick": "Image conversion and editing command-line suite.",
        "cmake": "Cross-platform build system generator.",
        "make": "Build automation tool (GNU Make).",
        "ninja": "Small, fast build system.",
        "pkg-config": "Helper for compiling against installed libraries.",
        "openssl": "TLS/SSL cryptography toolkit and libraries.",
        "sqlite": "Embedded SQL database engine CLI.",
        "postgresql": "PostgreSQL database server and client tools.",
        "mysql": "MySQL database server/client tools.",
        "redis": "In-memory data store / cache server.",
        "mongodb-community": "MongoDB community database server.",

        // Containers / cloud
        "docker": "Container engine CLI (often used with Docker Desktop).",
        "docker-compose": "Define and run multi-container Docker apps.",
        "kubectl": "Kubernetes cluster command-line tool.",
        "helm": "Kubernetes package manager.",
        "minikube": "Local Kubernetes cluster for development.",
        "kind": "Kubernetes IN Docker — local clusters for testing.",
        "terraform": "Infrastructure as code (HashiCorp).",
        "opentofu": "Open-source Terraform-compatible IaC tool.",
        "awscli": "AWS command-line interface.",
        "azure-cli": "Microsoft Azure command-line tools.",
        "gcloud-cli": "Google Cloud CLI.",
        "doctl": "DigitalOcean command-line client.",

        // JS tooling
        "npm": "Node package manager (usually comes with Node).",
        "yarn": "Alternative JavaScript package manager.",
        "pnpm": "Fast, disk-efficient JavaScript package manager.",
        "typescript": "Typed JavaScript language / compiler (tsc).",
        "eslint": "JavaScript/TypeScript linter.",
        "prettier": "Opinionated code formatter.",
        "vite": "Frontend build tool and dev server.",
        "next": "Next.js React framework CLI.",
        "create-react-app": "Scaffolding tool for React apps (legacy).",
        "vercel": "Vercel deployment CLI.",
        "netlify-cli": "Netlify deployment and local-dev CLI.",
        "firebase-tools": "Firebase project management CLI.",
        "serverless": "Serverless Framework CLI.",
        "wrangler": "Cloudflare Workers CLI.",
        "turbo": "Turborepo — high-performance monorepo build system.",
        "nx": "Smart monorepo build system.",

        // Python tooling
        "pipx": "Install and run Python CLIs in isolated environments.",
        "poetry": "Python dependency and packaging manager.",
        "pipenv": "Python virtualenv + pip workflow tool.",
        "uv": "Extremely fast Python package installer/resolver.",
        "black": "Uncompromising Python code formatter.",
        "ruff": "Extremely fast Python linter/formatter.",
        "pytest": "Python testing framework.",
        "jupyter": "Interactive notebooks for data science.",
        "jupyterlab": "Next-generation Jupyter web UI.",
        "ansible": "IT automation / configuration management.",
        "aws-sam-cli": "AWS Serverless Application Model CLI.",

        // AI / ML CLIs
        "ollama": "Run large language models locally from the terminal.",
        "huggingface-cli": "Hugging Face Hub CLI for models and datasets.",
        "openai": "OpenAI API command-line helper (when installed as a CLI).",
        "langchain": "Framework for building LLM-powered applications.",
        "whisper": "Speech-to-text model CLI (OpenAI Whisper ecosystem).",

        // Mobile / desktop
        "cocoapods": "Dependency manager for Swift/Objective-C Cocoa projects.",
        "fastlane": "iOS/Android automation for builds, screenshots, release.",
        "flutter": "UI toolkit for building multi-platform apps from one codebase.",
        "android-platform-tools": "adb / fastboot tools for Android devices.",

        // Misc common
        "tree": "List directory contents in a tree view.",
        "htop": "Interactive process viewer.",
        "btop": "Resource monitor with a modern TUI.",
        "ripgrep": "rg — extremely fast recursive search (grep alternative).",
        "fd": "User-friendly find alternative.",
        "bat": "cat alternative with syntax highlighting.",
        "eza": "Modern ls alternative.",
        "zoxide": "Smarter cd that learns your directories.",
        "fzf": "Fuzzy finder for the command line.",
        "watchman": "File-watching service (often used by Metro/React Native).",
        "graphviz": "Graph visualization tools (dot, etc.).",
        "pandoc": "Universal document converter.",
        "tesseract": "OCR engine — extracts text from images.",
        "yt-dlp": "Download video/audio from YouTube and many sites.",
    ]
}
