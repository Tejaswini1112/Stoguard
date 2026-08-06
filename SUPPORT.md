# Support

## Getting help

| Need | Action |
|------|--------|
| Install (macOS / Windows / Linux) | Read [docs/INSTALL.md](docs/INSTALL.md) |
| How Stoguard compares to other tools | Read [docs/COMPARISON.md](docs/COMPARISON.md) |
| Bug (UI, crash, wrong size) | [Open an issue](https://github.com/Tejaswini1112/Stoguard/issues/new) |
| Security / wrong safety label | See [SECURITY.md](SECURITY.md) — do not post sensitive paths publicly |

## License & contributions

Stoguard is **proprietary software**. See [LICENSE](LICENSE).

- This repository is published for transparency and authorized use by the copyright holder
- **Unsolicited contributions, forks for redistribution, and copying without permission are not accepted**
- Feature requests may be noted in Issues; implementation is at the maintainer's discretion

## System requirements

### macOS native app
- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel
- Xcode Command Line Tools for building from source (`xcode-select --install`)

### Windows (Go engine + web UI)
- Windows 10 or later (x64 or ARM64)
- No installer — run `stoguard-windows-amd64.exe` / `stoguard-windows-arm64.exe`
- PowerShell available for Recycle Bin (fallback: `%APPDATA%\Stoguard\Recycle`)

### Linux (Go engine + web UI)
- Modern x64 or ARM64 Linux
- Browser for the local UI at `http://127.0.0.1:8787`
