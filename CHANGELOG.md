# Changelog

All notable changes to Stoguard are documented here.

## [0.4.2] — 2026-08-06

### Windows reliability
- Expanded **windows.json** scan coverage (Cursor, WSL packages, Docker Desktop, Scoop/winget, `%TEMP%`, VS Code CachedData, Unity, browsers, AI caches)
- Recycle staging uses **copy+delete** across volumes; Explorer **Reveal** quoting fixed; blocked paths are **case-insensitive**
- Package Finder finds npm / Scoop / winget / pipx on Windows; UI copy is OS-aware
- Ships **windows-arm64.exe**; Windows install docs in README / INSTALL / SUPPORT
- PowerShell helper: `stoguard/scripts/run.ps1`

## [0.4.0] — 2026-08-05

### Best-on-every-platform

- **Universal macOS app** (arm64 + x86_64 lipo)
- **Windows Recycle Bin** via PowerShell VisualBasic SendToRecycleBin (staging fallback)
- **Linux/BSD trash** via `gio trash` / `trash-put` then FreeDesktop Trash
- **macOS Go trash** uses Finder delete for Put Back metadata
- **Package Finder + Skills/MCP** in the cross-platform Go UI (same as native Optimize tools)

## [0.3.2] — 2026-08-05

### Fixed (from [VACS issues](https://github.com/prajwal2308/VACS/issues))

- **#1 Trash refresh** — Move to Trash now matches standardized paths, closes detail, invalidates scan cache, and reloads the Trash browser immediately
- **#2 Library safety** — Application Support / profile-adjacent paths no longer show as green “Safe”; red **REVIEW — PROFILE RISK** warnings when cleanup may affect settings/profiles

### Added

- **#3 Package Finder** — Homebrew Cellar, npm globals, pipx, Cargo/user bins you may have forgotten
- **#4 AI Skills & MCP** — MCP configs, skill packs, and idle VS Code extensions

## [0.3.1] — 2026-08-05

### Added (merged from upstream 0.1.1)

- Overview category chips + **Show more** sheet (safe + check first selection sync)
- **Deselect all** in category item sheet
- **Uninstall** flow for Installed Apps (app only or complete)
- Back navigation: ← Overview bar, swipe, Backspace, ⌘[
- Clearer Chrome cache note (HTTP cache only)

### Kept from 0.3.0 platform

- Workstation Doctor, Ask Stoguard, System Pulse, Env Doctor, Build Trends
- AI Models, Duplicates, Git Repos, Codebase, Rules & Plugins, Fleet Export
- Parallel/incremental scan, adaptive skips, symlink path safety

## [0.1.0] — 2026-08-05

### Added

- Native SwiftUI macOS disk cleaner for developers
- **Smart Scan** dashboard with per-category review cards and bulk clean
- Sidebar categories: Developer, Packages, Browsers, Containers, AI Tools, Apps, System, Heavy folders
- **95-path rules engine** (`rules.json`) with plain-English notes and four safety levels
- **Installed Apps** browser with related-file drill-down (caches, containers, preferences)
- **Trash browser** — list, Put Back, delete permanently, empty Trash, Finder sounds
- Docker sparse-file sizing and copy-commands for Docker / Minikube / Colima
- DerivedData per-project breakdown
- `node_modules` and project artifact scanner (18 artifact types)
- Full Disk Access gate before scanning
- Trash-only deletion — nothing permanently erased without explicit action in Trash view
- Zero network access — no telemetry, updates, or analytics

### Security

- Proprietary license — see [LICENSE](LICENSE)
