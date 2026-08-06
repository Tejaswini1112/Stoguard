# Stoguard (cross-platform)

AI developer workstation manager for **macOS, Windows, and Linux**.

One Go binary embeds the UI and rule engine:

- Parallel rule scan (OS-specific rules + plugins)
- Adaptive skip of unused technologies
- Fingerprint cache (mtime / size)
- Symlink-safe Trash / Recycle Bin (Windows: PowerShell Recycle + staging fallback)
- Workstation Doctor + storage timeline
- Duplicate detection
- Ask AI (Ollama when available, local fallback otherwise)
- Plugin JSON rules (`rules/plugins`)

## Run

### macOS / Linux

```bash
cd stoguard
go run .            # opens http://127.0.0.1:8787
go run . -scan      # CLI scan only
```

### Windows (PowerShell)

```powershell
cd stoguard
go run .
# or double-click a prebuilt stoguard-windows-*.exe from website/downloads/
```

Helper: `.\scripts\run.ps1` from this folder.

## Build all platforms

```bash
./scripts/build.sh
```

Binaries land in `stoguard/dist/` and are copied to `website/downloads/`:

| File | Platform |
|------|----------|
| `stoguard-darwin-arm64` | Apple Silicon |
| `stoguard-darwin-amd64` | Intel Mac |
| `stoguard-linux-amd64` | Linux x64 |
| `stoguard-linux-arm64` | Linux ARM |
| `stoguard-windows-amd64.exe` | Windows x64 |
| `stoguard-windows-arm64.exe` | Windows ARM64 |

## Native macOS app

The SwiftUI app in `../Sources/Stoguard` remains the polished Mac client (`Stoguard.app`).  
This Go app is the **complete cross-platform** product surface for Windows and Linux.
