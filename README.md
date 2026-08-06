<p align="center">
  <img src="Assets/icon-1024.png" width="128" alt="Stoguard icon" />
</p>

<h1 align="center">Stoguard</h1>

<p align="center">
  <strong>AI mentor for developer workstations — macOS, Windows, and Linux.</strong><br/>
  Scan, explain, forecast, and clean safely to Trash. Zero telemetry by default.
</p>

<p align="center">
  <a href="https://github.com/Tejaswini1112/Stoguard/releases/latest/download/Stoguard-0.4.2.dmg"><strong>⬇ macOS DMG</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-windows-amd64.exe"><strong>⬇ Windows</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-linux-amd64"><strong>⬇ Linux</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-darwin-arm64">Apple Silicon</a>
  ·
  <a href="https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-linux-arm64">Linux ARM</a>
  ·
  <a href="https://github.com/Tejaswini1112/Stoguard/releases/latest">Releases</a>
</p>

<p align="center">
  <a href="docs/INSTALL.md"><strong>Install</strong></a> ·
  <a href="https://stoguard.vercel.app"><strong>Website</strong></a> ·
  <a href="docs/ENTERPRISE.md">Enterprise</a> ·
  <a href="docs/ROADMAP.md">Roadmap</a> ·
  <a href="docs/COMPARISON.md">Comparison</a> ·
  <a href="docs/PLUGIN_SDK.md">Plugin SDK</a> ·
  <a href="SECURITY.md">Security</a> ·
  <a href="docs/PRIVACY.md">Privacy</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey" alt="Cross-platform" />
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/version-0.4.2-blue" alt="0.4.2" />
  <img src="https://img.shields.io/badge/license-Proprietary-red" alt="Proprietary" />
</p>

---

Stoguard finds what’s eating a developer workstation — Docker, package caches, IDE data, local AI models, large media — then acts as an **AI mentor**: grounded Ask answers, a health score, forecasts, and Trash-only cleanup (never silent deletes).

## What’s included

| Component | Path | Platforms |
|-----------|------|-----------|
| **Native macOS app (universal)** | `Sources/Stoguard` → `Stoguard.app` / DMG | macOS 14+ Apple Silicon **and** Intel |
| **Cross-platform engine + UI** | `stoguard/` (Go) → `:8787` | macOS · Windows · Linux (x64/ARM) |
| **OS Trash** | Finder / Recycle Bin / FreeDesktop | Best-effort native trash on each OS |
| **Marketing site** | `website/` | Static (Vercel or `python3 -m http.server 8765`) |

### Core capabilities
- Parallel rule-based scan with adaptive skips + fingerprint cache  
- **Ask Stoguard** — scan-grounded mentor (not ChatGPT): Problem → Cause → Explanation → Risk → Recommendation → one-click Fix → Learn More + knowledge cards  
- **Predictive intelligence** — GB/day curves for Docker, Ollama, Hugging Face, DerivedData, Downloads, Time Machine + days-to-full  
- **Health score** — Storage / Performance / Environment / Security / AI Workspace + daily·weekly·monthly history  
- **Background monitoring** — watches rapid growth, build-cache spikes, idle models (while app runs)  
- **AI Workspace Manager** — sizes, last used, RAM estimate, GPU best-effort, quants, duplicates, archive/Trash  
- **Env Doctor** — Brew doctor, Node/Python conflicts, Java, Android SDKs, Flutter dupes, Rust, asdf/mise  
- **Repository Doctor** — heavy folders, dead deps, binaries, **secrets scan**, build artifacts  
- **Plugin SDK** — detection + explanation + risk + safe actions + docs links (`docs/PLUGIN_SDK.md`)  
- **Explainability** — every Doctor rec answers Why / What happens / Undo / Rebuilds / Is this common?  
- **Preference memory** — Keep vs Clean habits reshape Doctor ranking  
- **Learning Center** — what DerivedData/Docker/etc. are, when to delete, what happens after  
- **Automation** — daily scan / Sunday safe tidy / npm&gt;5GB — stages selection for your confirm  
- **Package Finder** — Homebrew / npm / pipx / CLI installs with definition + size  
- **Duplicates (thorough)** — fingerprint-confirmed only; related installs show difference icons  
- **Media Optimizer** — large images/videos/docs; approve keep-resolution optimize or KB/MB/GB/TB target  
- **Cloud cohort knowledge** — opt-in baselines + fleet-peer averages + optional remote feed/contribute (`docs/ENTERPRISE.md`)  
- **Enterprise fleet** — schema v2 multi-OS ingest, compliance, AI/license inventory, LAN Team server (`-bind` + API key)  
- Symlink-safe Trash · Workstation Doctor · storage timeline  
- Free / Pro / Team tiers (local builds default to **Team**). Set `STOGUARD_TIER=free|pro` to simulate.  
- Roadmap: [docs/ROADMAP.md](docs/ROADMAP.md)

## Downloads

Binaries ship on **[GitHub Releases](https://github.com/Tejaswini1112/Stoguard/releases/latest)** (recommended). Repo copies under `website/downloads/` are for local builds.

| Platform | Artifact |
|----------|----------|
| **macOS** (universal app) | [`Stoguard-0.4.2.dmg`](https://github.com/Tejaswini1112/Stoguard/releases/latest/download/Stoguard-0.4.2.dmg) |
| **Windows** (x64) | [`stoguard-windows-amd64.exe`](https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-windows-amd64.exe) |
| **Windows** (ARM64) | [`stoguard-windows-arm64.exe`](https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-windows-arm64.exe) |
| **Linux** (x64) | [`stoguard-linux-amd64`](https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-linux-amd64) |
| **Linux** (ARM64) | [`stoguard-linux-arm64`](https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-linux-arm64) |
| **macOS CLI** Apple Silicon | [`stoguard-darwin-arm64`](https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-darwin-arm64) |
| **macOS CLI** Intel | [`stoguard-darwin-amd64`](https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-darwin-amd64) |

Also via the marketing site: **[stoguard.vercel.app](https://stoguard.vercel.app)** (download buttons → GitHub Releases).

## Quick start

### Windows
1. Download [`stoguard-windows-amd64.exe`](https://github.com/Tejaswini1112/Stoguard/releases/latest/download/stoguard-windows-amd64.exe) (or ARM64)
2. If SmartScreen warns → **More info → Run anyway**
3. Double-click — UI opens at `http://127.0.0.1:8787`
4. Scan → review → clean to Recycle Bin

Full steps: [docs/INSTALL.md](docs/INSTALL.md#windows-x64--arm64)

### macOS native app
```bash
./scripts/build-app.sh --run          # build + open Stoguard.app
./scripts/build-dmg.sh 0.4.2          # also refresh website/downloads/*.dmg
# or open website/downloads/Stoguard-0.4.2.dmg
```

### Cross-platform (all OSes)
```bash
cd stoguard
go run .                 # http://127.0.0.1:8787
# Windows PowerShell: .\scripts\run.ps1
# or use a prebuilt binary from website/downloads/
./scripts/build.sh       # build macOS / Windows / Linux binaries
```

### Marketing site
```bash
cd website && python3 -m http.server 8765
```

## Repository
**https://github.com/Tejaswini1112/Stoguard**



## Privacy
Runs locally. No telemetry by default. See [docs/PRIVACY.md](docs/PRIVACY.md).

## License
Proprietary — all rights reserved. See [LICENSE](LICENSE).
