#!/usr/bin/env bash
# Pull upstream changes from prajwal2308/VACS into this Stoguard tree.
# Usage:
#   ./scripts/sync-from-vacs.sh              # sync into working tree
#   ./scripts/sync-from-vacs.sh --check      # print whether VACS has new commits
#   ./scripts/sync-from-vacs.sh --sha-only   # print latest VACS main SHA
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VACS_REPO="${VACS_REPO:-https://github.com/prajwal2308/VACS.git}"
VACS_REF="${VACS_REF:-main}"
CACHE="$ROOT/.cache/vacs-upstream"
SHA_FILE="$ROOT/.vacs-upstream-sha"
MODE="${1:-}"

mkdir -p "$ROOT/.cache"

latest_sha() {
  git ls-remote "$VACS_REPO" "refs/heads/$VACS_REF" | awk '{print $1}'
}

if [[ "$MODE" == "--sha-only" ]]; then
  latest_sha
  exit 0
fi

NEW_SHA="$(latest_sha)"
if [[ -z "$NEW_SHA" ]]; then
  echo "error: could not resolve $VACS_REPO ($VACS_REF)" >&2
  exit 1
fi

OLD_SHA=""
[[ -f "$SHA_FILE" ]] && OLD_SHA="$(tr -d '[:space:]' < "$SHA_FILE")"

if [[ "$MODE" == "--check" ]]; then
  if [[ "$NEW_SHA" == "$OLD_SHA" ]]; then
    echo "up-to-date $NEW_SHA"
    exit 0
  fi
  echo "behind old=${OLD_SHA:-none} new=$NEW_SHA"
  exit 2
fi

echo "==> fetching VACS $VACS_REF @ $NEW_SHA"
rm -rf "$CACHE"
git clone --depth 1 --branch "$VACS_REF" "$VACS_REPO" "$CACHE"

map_name() {
  # Rewrite VACS identifiers to Stoguard as we copy text sources.
  sed -E \
    -e 's/\bVACSApp\b/StoguardApp/g' \
    -e 's/\bVACSection\b/AppSection/g' \
    -e 's/\bVACS\b/Stoguard/g' \
    -e 's/\bvacs\b/stoguard/g' \
    -e 's|Sources/VACS|Sources/Stoguard|g' \
    -e 's|Application Support/VACS|Application Support/Stoguard|g' \
    -e 's|appendingPathComponent\("VACS"|appendingPathComponent("Stoguard"|g' \
    -e 's|prajwal2308/VACS|Tejaswini1112/Stoguard|g'
}

copy_mapped() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ "$src" == *.swift || "$src" == *.md || "$src" == *.sh || "$src" == *.yml || "$src" == *.yaml || "$src" == *.json ]]; then
    map_name < "$src" > "$dest"
  else
    cp -f "$src" "$dest"
  fi
}

echo "==> syncing rules + scripts + shared docs (mapped to Stoguard)"
# Rules — keep Stoguard brand; prefer VACS rule data as upstream source of truth for paths
if [[ -f "$CACHE/Sources/VACS/Resources/rules.json" ]]; then
  copy_mapped "$CACHE/Sources/VACS/Resources/rules.json" "$ROOT/Sources/Stoguard/Resources/rules.json"
  mkdir -p "$ROOT/stoguard/rules"
  cp -f "$ROOT/Sources/Stoguard/Resources/rules.json" "$ROOT/stoguard/rules/macos.json"
fi
if [[ -f "$CACHE/Sources/VACS/Resources/rules.manifest.json" ]]; then
  copy_mapped "$CACHE/Sources/VACS/Resources/rules.manifest.json" "$ROOT/Sources/Stoguard/Resources/rules.manifest.json"
fi

# Upstream scripts (build helpers) — map names
for f in build-app.sh build-dmg.sh generate-icon.swift; do
  if [[ -f "$CACHE/scripts/$f" ]]; then
    copy_mapped "$CACHE/scripts/$f" "$ROOT/scripts/$f.tmp"
    # Preserve Stoguard display name / Sources path if our script is newer — merge carefully:
    # Prefer upstream logic but force Stoguard branding after map_name.
    mv "$ROOT/scripts/$f.tmp" "$ROOT/scripts/$f"
    chmod +x "$ROOT/scripts/$f" 2>/dev/null || true
  fi
done

# Copy any NEW Swift files from VACS that Stoguard does not have yet (by basename)
echo "==> importing new Swift sources from VACS (skip existing)"
while IFS= read -r -d '' src; do
  base="$(basename "$src")"
  # Skip app entry / section enum — Stoguard owns these
  case "$base" in
    VACSApp.swift|VACSection.swift|StoguardApp.swift|AppSection.swift) continue ;;
  esac
  dest_name="$base"
  [[ "$base" == "VACSApp.swift" ]] && dest_name="StoguardApp.swift"
  [[ "$base" == "VACSection.swift" ]] && dest_name="AppSection.swift"
  dest="$ROOT/Sources/Stoguard/$dest_name"
  # Place Views/ correctly
  if [[ "$src" == */Views/* ]]; then
    dest="$ROOT/Sources/Stoguard/Views/$dest_name"
  fi
  if [[ ! -f "$dest" ]]; then
    echo "  + $dest_name"
    copy_mapped "$src" "$dest"
  fi
done < <(find "$CACHE/Sources/VACS" -name '*.swift' -print0)

echo "$NEW_SHA" > "$SHA_FILE"
echo "==> recorded upstream SHA $NEW_SHA in .vacs-upstream-sha"
echo "==> done. Review diff, run ./scripts/build-app.sh, then commit."
echo "    Upstream: https://github.com/prajwal2308/VACS"
echo "    Target:   https://github.com/Tejaswini1112/Stoguard"
