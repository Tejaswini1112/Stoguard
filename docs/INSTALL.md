# Installation Guide

Stoguard can be installed from a **GitHub Release DMG** (recommended) or built locally from source.

## Option A — Download the DMG

1. Open **[Releases](https://github.com/prajwal2308/Stoguard/releases/latest)** and download `Stoguard-x.y.z.dmg`
2. Open the DMG and drag **Stoguard.app** to **Applications**
3. If macOS blocks launch: **right-click → Open**, or `xattr -cr /Applications/Stoguard.app`
4. Continue with [Grant Full Disk Access](#grant-full-disk-access) below

Current builds are ad-hoc signed, not Apple-notarized. See the README section **Code signing & notarization**.

## Option B — Build from source

### Requirements

| Requirement | Notes |
|-------------|-------|
| macOS 14+ | Sonoma or later |
| Command Line Tools | `xcode-select --install` — full Xcode is **not** required |
| Full Disk Access | Required before any scan (see below) |
| ~50 MB disk | For build artifacts |

### Step 1 — Get the source

```bash
git clone https://github.com/prajwal2308/Stoguard.git
cd Stoguard
```

### Step 2 — Build

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

Output: `build/Stoguard.app`

The script will:

1. Generate `Assets/AppIcon.icns` if missing
2. Compile all Swift sources with `swiftc`
3. Assemble the app bundle with `rules.json`
4. Ad-hoc code-sign the app
5. Run `Stoguard --selftest` (must print `OK`)

### Build and open in one step

```bash
./scripts/build-app.sh --run
```

### Step 3 — Install to Applications (optional)

```bash
cp -R build/Stoguard.app /Applications/
```

Or drag `build/Stoguard.app` to `/Applications` in Finder.

## Grant Full Disk Access

1. Open **Stoguard** — you'll see the Full Disk Access gate if not yet granted
2. Click **Open System Settings**
3. Go to **Privacy & Security → Full Disk Access**
4. Click **+** and add **Stoguard** (from `/Applications` or `build/`)
5. Enable the toggle
6. Return to Stoguard and click **I've granted access**

Without FDA, scans will return incomplete results and macOS may show repeated permission dialogs.

## Step 5 — First scan

1. Open **Overview** → **Scan all categories**
2. Review category cards — safe items are pre-selected
3. Click **Clean Selected** or drill into a category

## Alternative: Swift Package Manager (Xcode)

If you have full Xcode installed:

```bash
open Package.swift
```

Select the **Stoguard** scheme → **Run** (⌘R).

Note: The primary supported path is `scripts/build-app.sh` (works with Command Line Tools only).

## Updating

1. `git pull` in the Stoguard directory
2. `./scripts/build-app.sh --run`
3. Replace `/Applications/Stoguard.app` if you copied it there

Settings and lifetime stats persist in UserDefaults across rebuilds.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `swiftc: command not found` | Run `xcode-select --install` |
| Self-test fails | Ensure `Sources/Stoguard/Resources/rules.json` exists |
| Scan shows 0 items | Grant Full Disk Access; quit and reopen Stoguard |
| "App is damaged" | Run `xattr -cr build/Stoguard.app` then rebuild |
| Put Back fails | Grant Stoguard → Finder in **Automation**; items trashed before v0.1.0 may lack origin metadata |

## Uninstall

```bash
rm -rf /Applications/Stoguard.app
rm -rf ~/Library/Application\ Support/Stoguard
```

Remove Stoguard from **Full Disk Access** in System Settings if desired.
