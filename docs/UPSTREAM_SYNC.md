# Upstream sync: VACS → Stoguard

Stoguard tracks useful changes from [prajwal2308/VACS](https://github.com/prajwal2308/VACS) and applies them here at [Tejaswini1112/Stoguard](https://github.com/Tejaswini1112/Stoguard).

## Automatic (GitHub Actions)

Workflow: [`.github/workflows/sync-vacs.yml`](../.github/workflows/sync-vacs.yml)

- Runs every **6 hours** and on manual **Run workflow**
- If VACS `main` has a new commit SHA, it:
  1. Runs `scripts/sync-from-vacs.sh`
  2. Opens a pull request on Stoguard for review

Merge the PR after checking branding and Stoguard-only features still work.

## Manual

```bash
./scripts/sync-from-vacs.sh --check   # see if upstream moved
./scripts/sync-from-vacs.sh           # import changes
./scripts/build-app.sh                # verify build
git add -A && git commit -m "chore: sync upstream VACS"
git push
```

Recorded upstream SHA: [`.vacs-upstream-sha`](../.vacs-upstream-sha)

## What gets synced

| Upstream | Stoguard |
|----------|----------|
| `Sources/VACS/Resources/rules.json` | `Sources/Stoguard/Resources/rules.json` (+ `stoguard/rules/macos.json`) |
| New Swift files not already in Stoguard | `Sources/Stoguard/…` (names mapped) |
| `scripts/build-*.sh` | Mapped to Stoguard branding |

Stoguard-only features (Package Finder, AI Skills & MCP, Go cross-platform app, Team fleet, website) are **not** removed by sync. Existing Swift files are not blindly overwritten — review the PR for rule/script updates and port logic by hand when VACS fixes shared code.
