# Installation Guide

Stoguard ships a **native macOS app** and a **cross-platform Go engine** (Windows / Linux / macOS CLI) with a local web UI at `http://127.0.0.1:8787`.

---

## Windows (x64 / ARM64)

### Option A — Download the `.exe`

1. Download [`stoguard-windows-amd64.exe`](../website/downloads/stoguard-windows-amd64.exe) (Intel/AMD) or [`stoguard-windows-arm64.exe`](../website/downloads/stoguard-windows-arm64.exe) (Snapdragon/ARM)
2. If SmartScreen warns: **More info → Run anyway** (builds are unsigned DIY binaries)
3. Double-click the `.exe` — it opens the UI in your browser at `http://127.0.0.1:8787`
4. Click **Scan**, review findings, clean with Recycle Bin (never silent delete)

**Data folder:** `%APPDATA%\Stoguard`  
**Recycle fallback:** `%APPDATA%\Stoguard\Recycle` (used only if PowerShell Recycle Bin fails)

### Option B — Build from source (Windows)

Requirements: [Go 1.22+](https://go.dev/dl/)

```powershell
git clone https://github.com/Tejaswini1112/Stoguard.git
cd Stoguard\stoguard
go run .
# or
go build -o stoguard.exe .
.\stoguard.exe
```

Cross-compile from macOS/Linux:

```bash
cd stoguard && ./scripts/build.sh
```

### Windows troubleshooting

| Problem | Fix |
|---------|-----|
| SmartScreen blocks | More info → Run anyway; or right-click → Properties → Unblock |
| Browser doesn’t open | Open `http://127.0.0.1:8787` manually |
| Recycle Bin fails | Items land in `%APPDATA%\Stoguard\Recycle` — move/delete from there |
| Empty scan | Run as your user (not a service); ensure tools like Docker/npm created AppData caches |
| Defender quarantine | Allow the file; report false positive if needed |

### Uninstall (Windows)

Delete the `.exe` and remove `%APPDATA%\Stoguard` if you want a clean slate.

---

## Linux

Download [`stoguard-linux-amd64`](../website/downloads/stoguard-linux-amd64) or [`stoguard-linux-arm64`](../website/downloads/stoguard-linux-arm64):

```bash
chmod +x stoguard-linux-amd64
./stoguard-linux-amd64
# UI: http://127.0.0.1:8787
```

Or: `cd stoguard && go run .`

Data dir: `~/.local/share/stoguard` (or `$XDG_DATA_HOME/stoguard`).

---

## macOS native app

### Option A — Download the DMG

1. Download [`Stoguard-0.4.2.dmg`](../website/downloads/Stoguard-0.4.2.dmg) from this repo or the [marketing site](../website/index.html)
2. Open the DMG and drag **Stoguard.app** to **Applications**
3. If macOS blocks launch: **right-click → Open**, or `xattr -cr /Applications/Stoguard.app`
4. Continue with [Grant Full Disk Access](#grant-full-disk-access) below

Current builds are ad-hoc signed, not Apple-notarized.

### Option B — Build from source (macOS)

| Requirement | Notes |
|-------------|-------|
| macOS 14+ | Sonoma or later |
| Command Line Tools | `xcode-select --install` — full Xcode is **not** required |
| Full Disk Access | Required before any scan (see below) |

```bash
git clone https://github.com/Tejaswini1112/Stoguard.git
cd Stoguard
chmod +x scripts/build-app.sh
./scripts/build-app.sh --run
```

Output: `build/Stoguard.app`

```bash
./scripts/build-dmg.sh 0.4.2   # refresh website/downloads DMG
```

### Grant Full Disk Access

1. Open **Stoguard** — you'll see the Full Disk Access gate if not yet granted
2. Click **Open System Settings**
3. Go to **Privacy & Security → Full Disk Access**
4. Click **+** and add **Stoguard** (from `/Applications` or `build/`)
5. Enable the toggle
6. Return to Stoguard and click **I've granted access**

Without FDA, scans will return incomplete results and macOS may show repeated permission dialogs.

### First scan (macOS app)

1. Open **Overview** → **Scan all categories**
2. Review category cards — safe items are pre-selected
3. Click **Clean Selected** or drill into a category

### Alternative: Swift Package Manager (Xcode)

```bash
open Package.swift
```

Select the **Stoguard** scheme → **Run** (⌘R).

### macOS troubleshooting

| Problem | Fix |
|---------|-----|
| `swiftc: command not found` | Run `xcode-select --install` |
| Self-test fails | Ensure `Sources/Stoguard/Resources/rules.json` exists |
| Scan shows 0 items | Grant Full Disk Access; quit and reopen Stoguard |
| "App is damaged" | Run `xattr -cr build/Stoguard.app` then rebuild |
| Put Back fails | Grant Stoguard → Finder in **Automation** |

### Uninstall (macOS)

```bash
rm -rf /Applications/Stoguard.app
rm -rf ~/Library/Application\ Support/Stoguard
```

Remove Stoguard from **Full Disk Access** in System Settings if desired.

---

## Feature surface by platform

| Feature | macOS app | Windows / Linux (Go UI) |
|---------|-----------|-------------------------|
| Scan + Trash / Recycle | Yes | Yes |
| Ask / Doctor / Health / Fleet | Yes | Yes |
| Package Finder | Homebrew + npm… | npm, Scoop, winget, pipx… |
| Env / Repo Doctor depth | Richest | Scan-grounded Ask; full Env/Repo UX is macOS-first |
| Media Optimizer (encode) | Yes | Detect only |

See [docs/ROADMAP.md](ROADMAP.md) and [docs/COMPARISON.md](COMPARISON.md).
