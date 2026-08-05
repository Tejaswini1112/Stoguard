<p align="center">
  <img src="Assets/icon-1024.png" width="128" alt="Stoguard icon" />
</p>

<h1 align="center">Stoguard</h1>

<p align="center">
  <strong>AI developer workstation manager for macOS, Windows, and Linux.</strong><br/>
  Find AI models, forgotten packages (with definitions + disk use), and caches — clean safely to Trash, zero telemetry.
</p>

<p align="center">
  <a href="docs/INSTALL.md"><strong>Install</strong></a> ·
  <a href="website/index.html"><strong>Website</strong></a> ·
  <a href="docs/COMPARISON.md">Comparison</a> ·
  <a href="SECURITY.md">Security</a> ·
  <a href="docs/PRIVACY.md">Privacy</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey" alt="Cross-platform" />
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/license-Proprietary-red" alt="Proprietary" />
</p>

---

Stoguard finds what’s eating a developer workstation — Docker, package caches, IDE data, local AI models — explains each folder **and each installed package** in plain English, groups advanced AI clutter into **AI Cleanup** for immediate safe reclaim, and moves cleanup to **Trash** (never silent deletes).

## What’s included

| Component | Path | Platforms |
|-----------|------|-----------|
| **Native macOS app (universal)** | `Sources/Stoguard` → `Stoguard.app` | macOS 14+ Apple Silicon **and** Intel |
| **Cross-platform engine + UI** | `stoguard/` (Go) | macOS · Windows · Linux (x64/ARM) |
| **OS Trash** | Finder / Recycle Bin / FreeDesktop | Best-effort native trash on each OS |
| **Marketing site** | `website/` | Static |

### Core capabilities
- Parallel rule-based scan with adaptive skips + fingerprint cache  
- **Health score** — storage / performance / security / AI workspace + SSD fill forecasts  
- **Proactive monitor** — detect → explain → recommend (background disk/memory alerts)  
- **Preference memory** — Keep vs Clean habits reshape Doctor ranking  
- **Learning Center** + richer Ask (teacher-mode explanations; Ollama optional)  
- **Automation** — scheduled scan/tidy rules + opt-in local cohort benchmarks  
- **AI Cleanup** — models, skills/MCP, and AI caches with archive/dedupe advice  
- **Package Finder** — Homebrew / npm / pipx / CLI installs with definition + size  
- **Repository intelligence** — heavy folders + large binaries in a pointed-at repo  
- **Plugin SDK** — drop-in JSON rules (`docs/PLUGIN_SDK.md`)  
- Symlink-safe Trash / recycle staging  
- Workstation Doctor, storage timeline, duplicates  
- Free / Pro / Team feature tiers (local/dev builds default to **Team** for full unlock)  
- Team fleet ingest + console (set `STOGUARD_TIER=free` or `pro` to simulate lower tiers)

## Quick start

### macOS native app
```bash
./scripts/build-app.sh --run
# or open the DMG from website/downloads/
```

### Cross-platform (all OSes)
```bash
cd stoguard
go run .                 # opens http://127.0.0.1:8787
# or use a prebuilt binary from website/downloads/
./scripts/build.sh       # build macOS / Windows / Linux binaries
```

## Repository
**https://github.com/Tejaswini1112/Stoguard**



## Privacy
Runs locally. No telemetry by default. See [docs/PRIVACY.md](docs/PRIVACY.md).

## License
Proprietary — all rights reserved. See [LICENSE](LICENSE).
