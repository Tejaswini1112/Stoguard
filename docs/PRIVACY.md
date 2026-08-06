# Privacy

Stoguard is built to run on your machine. Scan data stays local by default.

## What stays local

- All scan results (folder paths, sizes, safety labels)
- Your selection and clean history (`lifetimeTrashedBytes` in UserDefaults)
- Trash origin map for Put Back (`~/Library/Application Support/Stoguard/`)
- Adaptive profile, fingerprint cache, and scan history
- Full Disk Access status checks

## Network (optional, off by default)

| Feature | When it talks to the network |
|---------|------------------------------|
| **Optional cloud rules feed** | Only if you set `stoguard.rulesFeedURL` |
| **Cloud cohort feed / contribute** | Only if cohort opt-in **and** you set `stoguard.cohortFeedURL` / `stoguard.cohortContributeURL` (or env `STOGUARD_COHORT_*`). Payloads are anonymous category bytes — no hostname or paths. |
| **Enterprise fleet push** | Only when you push to a Team server URL you configure |
| **Ask Stoguard + Ollama** | Only if you enable Ollama chat — calls `http://127.0.0.1:11434` on your Mac |
| **Everything else** | No analytics, crash reporters, ad SDKs, or phone-home |

There is **no telemetry by default**. Fleet JSON and cohort peer averages stay in Application Support / your Team server unless you opt to push.

## Verification

```bash
# Optional remote rules (should only appear in CloudRules)
rg -n "URLSession" Sources/Stoguard

# Local Ollama only
rg -n "11434|ollama" Sources/Stoguard
```

## Permissions

| Permission | Why |
|------------|-----|
| **Full Disk Access** | Read sizes under `~/Library`, `~/.cache`, containers — without it, macOS blocks each folder individually |
| **Automation (optional)** | Only if you use Put Back via Finder for items not trashed by Stoguard |

Stoguard does not request Contacts, Photos, Microphone, or Location.

## Cross-platform note

The Go app (`stoguard/`) binds only to `127.0.0.1` for its local UI. On Windows, cleanup prefers the **Recycle Bin** via PowerShell (`SendToRecycleBin`). If that fails, items stage under `%APPDATA%\Stoguard\Recycle` (still recoverable — not a silent delete).
