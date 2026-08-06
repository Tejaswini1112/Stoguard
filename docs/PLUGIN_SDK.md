# Stoguard Plugin SDK

Drop-in JSON plugins extend Stoguard’s scan **without rebuilding the app**. Community packs live beside core `rules.json`.

## Where plugins live

| Surface | Directory |
|---------|-----------|
| Native macOS app | `~/Library/Application Support/Stoguard/Plugins/` |
| Repo examples | `plugins/{docker,flutter,unity,rust}/rules.json` |
| Go / web engine | `<dataDir>/Plugins/` (and bundled `stoguard/rules/plugins/`) |

Layout: flat (`my.json`) or packed (`docker/rules.json`). **Rules & Plugins → Open plugins folder**.

## Plugin model

Each plugin declares detection + intelligence — not just a path:

```json
{
  "id": "my-team-caches",
  "name": "My team caches",
  "version": "1.1.0",
  "platforms": ["macos", "linux", "windows", "any"],
  "description": "Internal Bazel + sccache paths for our eng laptops.",
  "documentationURL": "https://example.com/docs/caches",
  "author": "Platform team",
  "rules": [
    {
      "id": "team-bazel-cache",
      "name": "Bazel cache",
      "path": "~/.cache/bazel",
      "category": "Developer",
      "safety": "safe",
      "note": "Rebuildable Bazel remote/local cache.",
      "explanation": "Bazel stores action outputs and downloaded artifacts here so incremental builds stay fast.",
      "riskLevel": "low",
      "docsURL": "https://bazel.build/remote/caching",
      "safeActions": ["Move to Trash", "bazel clean --expunge (when safe)"],
      "whatRebuilds": "Next Bazel build refills needed artifacts.",
      "canUndo": "Put Back from Trash before Empty Trash.",
      "isCommon": "Common on monorepo developer machines.",
      "command": ""
    }
  ]
}
```

### Plugin fields

| Field | Required | Notes |
|-------|----------|-------|
| `id` | yes | Stable plugin id |
| `name` | yes | Shown in Rules & Plugins |
| `version` | no | Semver |
| `platforms` | no | `macos` / `linux` / `windows` / `any` |
| `description` | no | Pack summary |
| `documentationURL` | no | Link shown in UI |
| `author` | no | Attribution |
| `rules[]` | yes | Detection entries |

### Rule fields (detection + explainability)

| Field | Required | Notes |
|-------|----------|-------|
| `id` | yes | Unique across bundled + plugins |
| `name` | yes | Display name |
| `path` | yes | `~` expanded; measured if present (**detection**) |
| `category` | yes | Sidebar section mapping |
| `safety` | yes | `safe` · `check` · `command` · `never` |
| `note` | yes | Short explanation |
| `explanation` | no | Longer “what is this?” |
| `riskLevel` | no | `low` · `medium` · `high` |
| `docsURL` | no | Learn-more link |
| `safeActions` | no | Array of suggested actions (never auto-run) |
| `whatRebuilds` | no | What comes back after cleanup |
| `canUndo` | no | Undo guidance |
| `isCommon` | no | How common on developer machines |
| `command` | no | When `safety` is `command`, CLI to copy |

## Safety contract

- Plugins **never** delete anything. They only add measurable paths + teaching metadata.
- Prefer `safe` for rebuildable caches; `check` for project-ish data; `command` for Docker-style tools; `never` for credentials.
- Keep notes teachable — Doctor, Ask, and Learning Center surface them.

## Community contribution

1. Fork / clone Stoguard  
2. Add `plugins/<your-tech>/rules.json` using the schema above  
3. Drop a copy into Application Support **Plugins/** and hit **Refresh**  
4. Open a PR with the pack + a one-line description  

Core stays stable; the ecosystem grows via packs.

## Reload

1. Native: **Rules & Plugins → Refresh** (or rescan)  
2. Go web: restart `stoguard` or re-run scan  

## Versioning

Bump `version` when paths, safety, or explainability change. Teams can MDM-drop JSON into the Plugins folder.
