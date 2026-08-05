# Security Policy

Stoguard deletes and moves files on your Mac. Safety is the core design constraint.

## How Stoguard handles deletion

| Principle | Implementation |
|-----------|----------------|
| **Trash by default** | Scan cleanup uses `NSWorkspace.recycle` — items are recoverable until you empty Trash |
| **Explicit permanent delete** | Only available in the Trash view, with confirmation |
| **Allowlist scanning** | Known paths come from auditable `rules.json` with safety levels |
| **No silent erase** | No `rm`, no `FileManager.removeItem` on user cache paths during normal clean |
| **No elevation** | No `sudo`, no root helper, no kernel extensions |
| **Local only** | Zero network requests — verify: no `URLSession` in source |

## Safety levels

Every rule carries one of: `safe` · `check` · `command` · `never`. The UI cannot exceed the level — Docker VM disks show a copy-command, not a delete button.

## Full Disk Access

Stoguard requests **Full Disk Access** once before scanning. Without it, macOS shows a separate permission dialog per protected folder. Stoguard does not bypass TCC; it gates on FDA to avoid permission spam.

## Reporting a safety issue

If you find a path that Stoguard marks safe but should not be deletable, or a way to bypass the safety model:

1. **Do not** open a public issue with full paths to sensitive data
2. Email or DM the maintainer with: Stoguard version, macOS version, rule id (if known), and what went wrong
3. Use GitHub Issues only for **non-sensitive** bug reports (UI, crashes, wrong size display)

## Scope

Stoguard only operates under your home directory and standard user cache locations defined in `rules.json`. It does not modify `/System`, `/usr`, or other users' files.
