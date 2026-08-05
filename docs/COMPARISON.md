# Stoguard — feature comparison

How **Stoguard** stacks up against the open-source Mac cleaners developers actually use: [PureMac](https://github.com/momenbasel/PureMac), [Purge](https://github.com/jithin-sabu/purge-app), [ClearDisk](https://github.com/bysiber/cleardisk), [Cacheout](https://github.com/cacheout-app/cacheout), [SweepYourMac](https://github.com/pyramidion-solutions/sweep-your-mac), and [Mintify](https://github.com/yellowstudio-labs/mintify-app).

Last updated for **Stoguard** as of the current `main` branch (95 rules in `rules.json`, Smart Scan dashboard, Trash browser, Apps category).

---

## At a glance

| App | GitHub | Stars | License | Best for |
|-----|--------|------:|---------|----------|
| **PureMac** | [momenbasel/PureMac](https://github.com/momenbasel/PureMac) | ~5.6k | Proprietary | Full product surface — uninstaller, Smart Care dashboard, scheduled clean |
| **Purge** | [jithin-sabu/purge-app](https://github.com/jithin-sabu/purge-app) | ~451 | Proprietary | Calm UX, plain-English notes, sidebar “Clean X GB”, dev depth |
| **ClearDisk** | [bysiber/cleardisk](https://github.com/bysiber/cleardisk) | ~563 | Proprietary | Widest dev cache path list, menu bar, storage forecast |
| **Cacheout** | [cacheout-app/cacheout](https://github.com/cacheout-app/cacheout) | ~2 | Proprietary | Scanner logic — sparse files, parallel scan, MCP companion |
| **SweepYourMac** | [pyramidion-solutions/sweep-your-mac](https://github.com/pyramidion-solutions/sweep-your-mac) | ~1 | Proprietary | Actor-based scanners, safety guards |
| **Mintify** | [yellowstudio-labs/mintify-app](https://github.com/yellowstudio-labs/mintify-app) | ~10 | Proprietary | App Store / sandbox path — no FDA, treemap, duplicates |
| **Stoguard** | [prajwal2308/Stoguard](https://github.com/prajwal2308/Stoguard) | — | Proprietary | Dev-first, auditable rules, copy-commands for containers, honest sizing |

> **License note:** ClearDisk is **MIT**, not GPL-3. GPL-3 applies to a different project (DevCleaner).

---

## Master feature matrix

Legend: ✅ Full · ⚠️ Partial · ❌ Not present

| Feature | PureMac | Purge | ClearDisk | Cacheout | SweepYourMac | Mintify | **Stoguard** |
|---------|:-------:|:-----:|:---------:|:--------:|:------------:|:-------:|:--------:|
| **Navigation & dashboard** |
| Sidebar categories | ✅ | ✅ | ✅ tabs | ❌ | ✅ | ✅ | ✅ |
| Smart Scan / scan-all dashboard | ✅ | ⚠️ | ✅ hero | ❌ | ✅ | ❌ | ✅ |
| Per-category review cards + checkbox | ✅ | ❌ | ✅ groups | ❌ | ❌ | ❌ | ✅ |
| Sidebar storage bar (used / free) | ⚠️ | ✅ | ✅ | ❌ | ⚠️ | ⚠️ | ✅ |
| Sidebar “Safe to Clean” + big Clean button | ❌ | ✅ | ✅ menu bar | ❌ | ❌ | ❌ | ✅ |
| **List & selection UX** |
| Select All + master checkbox bar | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| “Clean N items” bulk action | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Safety filter pills (All / Safe / Check) | ❌ | ✅ | ✅ risk | ✅ | ✅ colors | ❌ | ✅ |
| Sort by size / name | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Per-row app / tool icons | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Plain-English per-item notes | ⚠️ | ✅ | ✅ | ⚠️ | ❌ | ❌ | ✅ |
| Folder drill-down + file list | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | ✅ treemap | ✅ |
| **Dev cache coverage** |
| Known dev cache paths (rules DB) | ⚠️ ~40 | ✅ broad | ✅ 63 | ⚠️ 15 | ⚠️ | ⚠️ | ✅ **95** |
| Open auditable rules file | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ✅ `rules.json` |
| `node_modules` / project artifact scan | ❌ | ✅ | ✅ 23 types | ✅ | ✅ | ❌ | ✅ |
| Docker real disk size (sparse/APFS) | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| DerivedData per-project breakdown | ⚠️ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Copy CLI command instead of delete | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ | ✅ Docker / Minikube / Colima |
| Unknown heavy folder discovery | ❌ | ❌ hides | ❌ | ❌ | ❌ | ❌ | ✅ opt-in |
| **Apps & uninstall** |
| Installed apps browser | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Full app uninstaller engine | ✅ 10-level | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Orphan / leftover finder | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Consumer app caches (Zoom, Discord…) | ⚠️ | ✅ | ⚠️ | ❌ | ❌ | ❌ | ✅ Apps category |
| **Files & duplicates** |
| Large Files finder (Documents/Downloads…) | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ removed¹ |
| Duplicate finder | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ MD5 | ❌ |
| Disk treemap visualizer | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Trash & deletion** |
| Trash-only delete (recoverable) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Trash browser (list / put back / empty) | ⚠️ | ⚠️ | ❌ | ❌ | ⚠️ | ❌ | ✅ |
| macOS Finder trash sounds | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Confirm before every delete | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Automation & background** |
| Scheduled auto-clean | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ⚠️ rules + prompts |
| Menu bar companion | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ |
| Storage forecast (disk fill prediction) | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ Health |
| **Permissions & trust** |
| Full Disk Access gate | ✅ | ✅ | ⚠️ | ❌ | ✅ | N/A sandbox | ✅ |
| Zero network / local-only | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Notarized / signed release | ✅ | ✅ | ⚠️ | ❌ | ❌ | ✅ App Store | ⚠️ DIY build |
| **Architecture** |
| Actor-based scanners | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Parallel category scan | ⚠️ | ✅ streaming | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ |
| MCP / AI agent integration | ❌ | ❌ | ❌ | ✅ cacheout-mcp | ❌ | ❌ | ❌ |

¹ Stoguard intentionally dropped a Documents/Downloads file browser — it was slow and blanked on tab switches. Dev caches + heavy-folder discovery remain the focus.

---

## Where each app wins

### PureMac — the complete product
- **Smart Care** post-scan command center: hero total, per-category review cards, one “Clean selected” pass.
- **App uninstaller** with multi-signal matching (bundle ID, entitlements, containers, 27 protected apps).
- **Scheduled cleaning** (hourly → monthly) and **orphan finder**.
- **Advanced Tools** submenu: AI Apps, Xcode Junk, Brew Cache, Docker Cache, etc.

### Purge — the calm dev cleaner
- **Sidebar bottom card** always visible: storage bar, “SAFE TO CLEAN” number, black **Clean X GB** pill.
- **Safety filter pills** with keyboard shortcuts (⌘1–⌘3): All / Safe to Clean / Check First.
- **Plain-English notes** on every row; unidentified folders hidden (allowlist-only).
- **Developer projects** scanner with configurable staleness threshold.
- **Menu bar** companion + scheduled clean + onboarding walkthrough.

### ClearDisk — the path encyclopedia
- **63 documented cache paths** across the full dev stack (Xcode sub-paths, Ruby, Android emulators, AI tools, nvm/pyenv/mise…).
- **Risk levels** (Safe / Caution / Risky) with “what happens if I delete” copy.
- **DerivedData breakdown** via `info.plist` per project.
- **Menu bar** disk monitor, **storage forecast** (90-day linear regression), **590 KB** binary.

### Cacheout — the scanner reference
- **Sparse file awareness** (`totalFileAllocatedSize`) — Docker reports real APFS allocation.
- **`node_modules` finder** with staleness badges and “select all stale”.
- **Parallel async** category scanning.
- **[cacheout-mcp](https://github.com/cacheout-app/cacheout-mcp)** — AI agents can trigger clean-by-target-GB.

### SweepYourMac — the safety architecture
- Each scanner is a Swift **`actor`** (thread-safe MVVM).
- **Safety guards**: protected paths, symlink escape prevention, `lsof` in-use detection, today’s files protected.
- 12 categories with green / yellow / red safety colors.

### Mintify — the App Store path
- **Sandboxed** — no FDA; permission per-folder when needed.
- **Duplicate finder** (MD5), **disk treemap**, **memory optimizer** (Mach APIs).
- ~3.4 MB binary, menu bar popover.

### Stoguard — the honest dev tool
- **95 auditable rules** in plain JSON — extend with a one-line PR.
- **Copy-command** for Docker, Minikube, Colima — never risky folder deletes on VM disks.
- **Docker sparse sizing** via `totalFileAllocatedSize` (same idea as Cacheout).
- **DerivedData per-project breakdown** (ClearDisk-style).
- **`node_modules` + 18 artifact types** via `ProjectScanner` (Cacheout/ClearDisk pattern).
- **Unknown heavy folders** over 1 GB — Purge hides these; Stoguard surfaces them for review.
- **Smart Scan dashboard** (PureMac-inspired) + **Purge-style** sidebar card, filter pills, selection bar.
- **Trash browser** with Put Back, permanent delete, Empty Trash, Finder sounds.
- **Zero network**, trash-only deletion, FDA gate before scan.

---

## UX pattern comparison (dashboard + select-all)

These are the two UX patterns worth copying — and what Stoguard implements today.

### PureMac — Smart Care dashboard
```
┌─────────────────────────────────────────┐
│  SCAN COMPLETE                          │
│  140.2 MB across 2 categories           │
│  [ Clean 140.2 MB ]  [ Scan Again ]     │
├─────────────────────────────────────────┤
│  ☑ Mail Files    9.8 MB · 15 items      │
│     [ Review ]                          │
│  ☑ System Junk   130 MB · 8 items     │
│     [ Review ]                          │
└─────────────────────────────────────────┘
```
**Stoguard:** ✅ `OverviewView` + `SmartCareHero` + `CategoryReviewCard` + category checkboxes + Clean Selected.

### PureMac — category detail + Select All
```
┌─────────────────────────────────────────┐
│  System Junk · 15 items · 9.8 MB        │
│  ☑ 15 of 15 selected · 9.8 MB           │
│              [ Clean 15 items ]         │
├─────────────────────────────────────────┤
│  ☑ row · name · path · date · size      │
└─────────────────────────────────────────┘
```
**Stoguard:** ✅ `SelectionActionBar` in every category + `CategorySplitView` drill-down.

### Purge — sidebar + filter pills
```
Sidebar (bottom)          Main panel
┌──────────────┐          ┌─────────────────────────┐
│ STORAGE      │          │ 93 items · 1.71 GB      │
│ ████░░ used  │          │ [Scan] [Clean Selected] │
│ 26 GB safe   │          │ All | Safe | Check First│
│ [Clean 26GB] │          │ ☑ Select All · Largest  │
└──────────────┘          └─────────────────────────┘
```
**Stoguard:** ✅ `SidebarStorageCard` + `SafetyFilterPills` + sort picker + app icons on rows.

---

## Dev cache path coverage (approximate)

| Stack area | PureMac | Purge | ClearDisk | Cacheout | Stoguard |
|------------|--------:|------:|----------:|---------:|-----:|
| Xcode / iOS | ⚠️ | ✅ | ✅ 9 sub-paths | ✅ | ✅ |
| JS package managers | ⚠️ | ✅ | ✅ npm/yarn/pnpm/bun | ✅ | ✅ |
| Python (pip/conda/uv…) | ⚠️ | ✅ | ✅ | ⚠️ pip | ✅ |
| Rust / Go / JVM | ❌ | ✅ | ✅ | ⚠️ | ✅ |
| Docker / K8s | ⚠️ CLI | ✅ | ✅ | ✅ sparse | ✅ CLI + sparse |
| AI tools (Ollama, HF…) | ✅ | ⚠️ | ✅ | ❌ | ✅ |
| Browser automation | ❌ | ⚠️ | ⚠️ | ⚠️ | ✅ Puppeteer/Playwright |
| Consumer apps | ⚠️ | ✅ | ⚠️ | ❌ | ✅ 22 rules |
| Project artifacts | ❌ | ✅ | ✅ 23 types | ✅ | ✅ 18 types |
| **Total known paths** | ~40 | ~50+ | **63** | 15 | **95** |

Stoguard leads on raw rule count; ClearDisk leads on per-path documentation depth and risk labeling. Purge leads on project staleness UX.

---

## Safety model comparison

| App | Default delete | Permanent delete | Unknown folders | In-use detection |
|-----|----------------|------------------|-------------------|------------------|
| PureMac | Trash | Empty Trash | Hidden in categories | ⚠️ |
| Purge | Trash | Trash | **Hidden** (allowlist) | ⚠️ |
| ClearDisk | Trash | Trash | Not scanned | Xcode-running check |
| Cacheout | Trash option | Trash | Not scanned | ❌ |
| SweepYourMac | Trash | Trash | Scanned | **`lsof`** |
| Mintify | Trash | Trash | Large Files tab | ⚠️ |
| **Stoguard** | Trash | Trash section (explicit) | **Shown** (Heavy folders) | ❌ |

Stoguard is more permissive about unknown folders than Purge — intentional for power users who want to see what's unlisted.

---

## Stoguard differentiators (what none of the others do well)

| Differentiator | Why it matters |
|----------------|----------------|
| **Open `rules.json`** | Every scanned path, safety level, and note is in one PR-reviewable file. |
| **Copy-command for VMs** | Docker Desktop, Minikube, Colima show the correct CLI — not a delete button on a 50 GB sparse file. |
| **Heavy folder discovery** | Sweeps `~/.cache`, `~/Library`, etc. for folders > 1 GB not in the rules DB. |
| **Honest Docker sizing** | Uses APFS allocated size, not virtual disk file size. |
| **Trash browser + Put Back** | Full Trash section with restore, permanent delete, Finder sounds. |
| **No network, no telemetry** | Verifiable: zero `URLSession` usage. |
| **~10 s DIY build** | `swiftc` script — no opaque download required. |

---

## Stoguard gaps (honest roadmap)

| Gap | Best repo to borrow from | Priority |
|-----|---------------------------|----------|
| Scheduled auto-clean | PureMac, Purge | Medium |
| Menu bar companion | Purge, ClearDisk, Mintify | Medium |
| Storage forecast | ClearDisk | Low |
| Full app uninstaller | PureMac | Medium |
| Orphan / leftover finder | PureMac, SweepYourMac | Low |
| Large Files tab (Documents/Downloads) | Purge, ClearDisk, Mintify | Low (removed for perf) |
| Duplicate finder | Mintify | Low |
| Actor-based scanners | SweepYourMac | Low (architecture) |
| MCP agent integration | Cacheout | Low |
| Risk color levels (🟢🟡🔴) | ClearDisk, SweepYourMac | Medium |
| In-use file detection (`lsof`) | SweepYourMac | Medium |
| Notarized release | PureMac, Purge | High for distribution |

---

## Borrow map — which repo to read for which feature

| You want to implement… | Start here |
|------------------------|------------|
| Smart Care dashboard + category review cards | [PureMac](https://github.com/momenbasel/PureMac) Views + ViewModels |
| Sidebar clean button + safety pills + onboarding | [Purge](https://github.com/jithin-sabu/purge-app) ContentView + PurgeStore |
| 63-path rules database + risk descriptions | [ClearDisk](https://github.com/bysiber/cleardisk) cache definitions |
| Docker real size + parallel scan | [Cacheout](https://github.com/cacheout-app/cacheout) Scanner/Categories.swift |
| Actor scanner + safety guards | [SweepYourMac](https://github.com/pyramidion-solutions/sweep-your-mac) Services/ |
| Sandbox / App Store / treemap / duplicates | [Mintify](https://github.com/yellowstudio-labs/mintify-app) |
| Auditable JSON rules + copy-commands | **Stoguard** `rules.json` + `AppModel` |

---

## Per-app feature inventory (condensed)

<details>
<summary><strong>PureMac</strong> — momenbasel/PureMac · Proprietary · ~5.6k ★</summary>

| Area | Features |
|------|----------|
| Smart Care | One scan all categories; live progress; post-scan dashboard with review cards |
| System cleaner | System Junk, User Cache, Mail Files, Trash Bins, Large & Old Files, AI Apps |
| Dev tools | Xcode Junk, Brew/Node/Docker Cache, Universal Binaries, Language Files |
| App uninstaller | 10-level matching; Strict/Enhanced/Deep tiers; 27 protected apps |
| Orphan finder | Leftover files from deleted apps |
| Scheduled cleaning | Hourly → monthly; auto-clean threshold |
| Safety | Trash only; hard-excluded system paths; Reveal in Finder |
| UI | Native SwiftUI sidebar; category badges; light/dark/system; signed + notarized |

</details>

<details>
<summary><strong>Purge</strong> — jithin-sabu/purge-app · Proprietary · ~451 ★</summary>

| Area | Features |
|------|----------|
| App Caches | Per-app folders + brand icons; creative app media caches; streaming results |
| Dev Tools | Xcode, Homebrew, npm/pnpm/Yarn, CocoaPods, Gradle, Flutter, Docker, VS Code, JetBrains, Cargo, Terraform… |
| Developer projects | `node_modules`, `.venv`, Rust `target`, Flutter build, Pods, `.gradle` + staleness setting |
| Large Files | Documents/Desktop/Downloads/Movies/Music/Pictures; Quick Look; Reveal in Finder |
| Safety | Safe / Check First labels; ⌘1–⌘3 filters; unidentified folders hidden |
| Dashboard | Sidebar storage bar + Safe to Clean total + big Clean button |
| Extras | Menu bar; scheduled clean; onboarding walkthrough; cleanup history |

</details>

<details>
<summary><strong>ClearDisk</strong> — bysiber/cleardisk · Proprietary · ~563 ★</summary>

| Area | Features |
|------|----------|
| Cache paths | 63 paths: full dev stack + AI tools + Android emulators + Unity/Godot |
| Project scanner | 23 project types |
| Risk levels | Safe / Caution / Risky with human descriptions |
| DerivedData | Per-project sizes via `info.plist` |
| Menu bar | Disk monitor; color at 80%/90%; cleanable amount when stressed |
| Forecast | Linear regression on 90-day history |
| Safety | Trash-only; Xcode-running check; recovery banner + cumulative saved counter |

</details>

<details>
<summary><strong>Cacheout</strong> — cacheout-app/cacheout · Proprietary · ~2 ★</summary>

| Area | Features |
|------|----------|
| Categories | 15 cache types (Xcode, Docker, npm, Homebrew, browsers, VS Code, Electron, pip…) |
| node_modules | Recursive scan with staleness badge (30d+); select all stale |
| Sparse files | `totalFileAllocatedSize` for Docker real disk usage |
| Parallel scan | Async concurrent category scanning |
| MCP | [cacheout-mcp](https://github.com/cacheout-app/cacheout-mcp) for AI-triggered clean |

</details>

<details>
<summary><strong>SweepYourMac</strong> — pyramidion-solutions/sweep-your-mac · Proprietary · ~1 ★</summary>

| Area | Features |
|------|----------|
| Categories | 12: System/Browser Caches, Logs, Trash, Dev, Languages, node_modules, Docker, Leftovers, Large Files, Mail, iOS Backups |
| Safety guards | Protected paths; symlink escape prevention; `lsof` in-use; today's files protected |
| Architecture | Swift `actor` scanners; MVVM; green/yellow/red safety colors |

</details>

<details>
<summary><strong>Mintify</strong> — yellowstudio-labs/mintify-app · Proprietary · ~10 ★</summary>

| Area | Features |
|------|----------|
| Sandbox | No FDA — permission per-folder only |
| Storage cleaner | 6 categories: browsers, logs, Xcode, npm/yarn/pip/CocoaPods/Homebrew |
| Large Files | Threshold filters (100 MB–1 GB+); sort by size/name/date |
| Duplicates | MD5 content hash; keep-original smart selection |
| Disk visualizer | Interactive treemap drill-down |
| Memory optimizer | Mach APIs — RAM pressure, CPU per core, top processes |
| Menu bar | Lightweight popover with CPU/RAM/storage · ~3.4 MB |

</details>

<details>
<summary><strong>Stoguard</strong> — prajwal2308/Stoguard · MIT</summary>

| Area | Features |
|------|----------|
| Rules engine | 95 paths in auditable `rules.json`; 4 safety levels: safe / check / command / never |
| Smart Scan | Overview dashboard; category review cards; Clean Selected across categories |
| Categories | Developer · Packages · Browsers · Containers · AI Tools · Apps · System · Heavy folders |
| Project scanner | 18 artifact types (`node_modules`, `.next`, `.venv`, `target/`, `Pods`…) in 7 search roots |
| Containers | Docker sparse sizing; Minikube/Colima copy-commands |
| Apps | 22 consumer app rules (Zoom, Discord, Slack, Perplexity, Spotify…) |
| Installed Apps | Browse apps + drill into related files (not full uninstall) |
| Trash | List Trash contents; Put Back; Delete Permanently; Empty Trash; Finder sounds |
| UI | Purge-style sidebar card + filter pills + selection bar; PureMac-style overview cards |
| Trust | Trash-only; zero network; FDA gate; ~10 s `swiftc` build |

</details>

---

## Summary positioning

| If you want… | Use |
|--------------|-----|
| Most complete free Mac cleaner (uninstaller + schedule) | **PureMac** |
| Calmest UX with best onboarding | **Purge** |
| Widest documented dev path list + forecast | **ClearDisk** |
| Best scanner implementation to study | **Cacheout** |
| Best safety architecture to study | **SweepYourMac** |
| App Store / no FDA / treemap / duplicates | **Mintify** |
| Auditable rules + copy-commands + honest dev tooling | **Stoguard** |

Stoguard sits at the intersection of **Purge's calm UX**, **PureMac's Smart Scan dashboard**, and **ClearDisk/Cacheout's dev depth** — with a deliberately open rules file and container-aware safety that the others don't offer.

---

## Contributing comparisons

If a row is wrong or a project shipped a feature, open a PR updating this file with a link to the source commit or README section.
