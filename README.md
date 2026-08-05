<p align="center">
  <img src="Assets/icon-1024.png" width="128" alt="Stoguard icon" />
</p>

<h1 align="center">Stoguard</h1>

<p align="center">
  <strong>AI developer workstation manager for macOS, Windows, and Linux.</strong><br/>
  Scan developer caches, reclaim disk safely, diagnose slow machines — Trash-only, zero telemetry.
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

Stoguard finds what’s eating a developer workstation — Docker, package caches, IDE data, local AI models — explains each folder in plain English, and moves cleanup to **Trash** (never silent deletes).

## What’s included

| Component | Path | Platforms |
|-----------|------|-----------|
| **Native macOS app** | `Sources/Stoguard` → `Stoguard.app` | macOS 14+ |
| **Cross-platform engine + UI** | `stoguard/` (Go) | macOS · Windows · Linux |
| **Marketing site** | `website/` | Static |

### Core capabilities
- Parallel rule-based scan with adaptive skips + fingerprint cache  
- Symlink-safe Trash / recycle staging  
- Workstation Doctor, storage timeline, duplicates, Ask AI (Ollama optional)  
- Free / Pro / Team feature tiers (local builds default to **Pro**)  
- Team fleet ingest + console (`STOGUARD_TIER=team`)

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

### Upstream sync (VACS → Stoguard)
When [prajwal2308/VACS](https://github.com/prajwal2308/VACS) changes, Stoguard auto-checks every 6 hours and opens a PR. Details: [docs/UPSTREAM_SYNC.md](docs/UPSTREAM_SYNC.md). Manual: `./scripts/sync-from-vacs.sh`.

## Privacy
Runs locally. No telemetry by default. See [docs/PRIVACY.md](docs/PRIVACY.md).

## License
Proprietary — all rights reserved. See [LICENSE](LICENSE).
