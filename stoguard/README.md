# Stoguard (cross-platform)

AI developer workstation manager for **macOS, Windows, and Linux**.

One Go binary embeds the UI and rule engine:

- Parallel rule scan
- Adaptive skip of unused technologies
- Fingerprint cache (mtime / size)
- Symlink-safe Trash / recycle staging
- Workstation Doctor + storage timeline
- Duplicate detection
- Ask AI (Ollama when available, local fallback otherwise)
- Plugin JSON rules (`rules/plugins`)

## Run

```bash
cd stoguard
go run .            # opens http://127.0.0.1:8787
go run . -scan      # CLI scan only
```

## Build all platforms

```bash
./scripts/build.sh
```

Binaries land in `stoguard/dist/`:

| File | Platform |
|------|----------|
| `stoguard-darwin-arm64` | Apple Silicon |
| `stoguard-darwin-amd64` | Intel Mac |
| `stoguard-linux-amd64` | Linux x64 |
| `stoguard-linux-arm64` | Linux ARM |
| `stoguard-windows-amd64.exe` | Windows x64 |

## Native macOS app

The SwiftUI app in `../Sources/Stoguard` remains the polished Mac client (`Stoguard.app`).  
This Go app is the **complete cross-platform** product surface.
