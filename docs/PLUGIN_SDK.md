# Stoguard Plugin SDK

Drop-in JSON plugins extend Stoguard’s scan rules without rebuilding the app.

## Where plugins live

| Surface | Directory |
|---------|-----------|
| Native macOS app | `~/Library/Application Support/Stoguard/Plugins/` |
| Go / web engine | `<dataDir>/Plugins/` (and bundled `stoguard/rules/plugins/`) |

Open **Rules & Plugins** in the app → **Open plugins folder**.

## Schema

```json
{
  "id": "my-team-caches",
  "name": "My team caches",
  "version": "1.0.0",
  "platforms": ["macos", "linux", "windows", "any"],
  "rules": [
    {
      "id": "team-bazel-cache",
      "name": "Bazel cache",
      "path": "~/.cache/bazel",
      "category": "Developer",
      "safety": "safe",
      "note": "Rebuildable Bazel remote/local cache. Safe to Trash when disk is tight.",
      "command": ""
    }
  ]
}
```

### Fields

| Field | Required | Notes |
|-------|----------|-------|
| `id` | yes | Stable plugin id (filename-independent) |
| `name` | yes | Shown in Rules & Plugins |
| `version` | no | Semver string |
| `platforms` | no | `macos` / `linux` / `windows` / `any` (default any) |
| `rules[]` | yes | Same shape as `rules.json` entries |

### Rule fields

| Field | Required | Notes |
|-------|----------|-------|
| `id` | yes | Unique across bundled + plugin rules |
| `name` | yes | Display name |
| `path` | yes | `~` expanded; measured if it exists |
| `category` | yes | Maps to sidebar sections (`Developer`, `Package Managers`, `Containers & K8s`, `AI Tools`, …) |
| `safety` | yes | `safe` · `check` · `command` · `never` |
| `note` | yes | Plain-English explanation (shown in UI + Ask) |
| `command` | no | When `safety` is `command`, CLI to copy (never auto-run) |

## Safety contract

- Plugins **never** delete anything. They only add measurable paths.
- Prefer `safe` for rebuildable caches; `check` for project-ish data; `command` for Docker/Minikube-style tools; `never` for profiles/credentials.
- Keep notes teachable — Learning Center and Ask surface them.

## Examples

See:

- `plugins/example-bazel.json`
- `plugins/example-ai-extra.json`
- `stoguard/rules/plugins/linux.example.json`
- `stoguard/rules/plugins/windows.example.json`

## Reload

After adding or editing a plugin JSON:

1. Native: **Rules & Plugins → Refresh** (or rescan)
2. Go web: restart `stoguard` or re-run scan (plugins merge at engine load)

## Versioning tip

Bump `version` when you change paths or safety. Teams can ship plugin packs via MDM by dropping JSON into the Plugins folder.
