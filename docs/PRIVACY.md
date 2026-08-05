# Privacy

Stoguard is built to run entirely on your Mac.

## What stays local

- All scan results (folder paths, sizes, safety labels)
- Your selection and clean history (`lifetimeTrashedBytes` in UserDefaults)
- Trash origin map for Put Back (`~/Library/Application Support/Stoguard/`)
- Full Disk Access status checks

## What never happens

- No network requests (no update checks, analytics, crash reporters, or CDN calls)
- No file contents read beyond metadata (`du`, directory listing, bundle plists)
- No accounts, sign-in, or cloud sync
- No third-party SDKs

## Verification

You can confirm zero network usage by searching the source:

```bash
grep -r "URLSession\|NWConnection\|socket" Sources/
```

Expected result: no matches in application code.

## Permissions

| Permission | Why |
|------------|-----|
| **Full Disk Access** | Read sizes under `~/Library`, `~/.cache`, containers — without it, macOS blocks each folder individually |
| **Automation (optional)** | Only if you use Put Back via Finder for items not trashed by Stoguard |

Stoguard does not request Contacts, Photos, Microphone, or Location.
