#!/usr/bin/env bash
# Build Stoguard.app and pack it into a compressed DMG for GitHub Releases.
# Usage: ./scripts/build-dmg.sh [version]   (default version: 0.3.1)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.4.2}"
STAGING="$ROOT/build/dmg-staging"
DMG="$ROOT/build/Stoguard-${VERSION}.dmg"
WEB_DMG="$ROOT/website/downloads/Stoguard-${VERSION}.dmg"

"$ROOT/scripts/build-app.sh"

echo "==> packaging DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
if [ -d "$ROOT/build/Stoguard.app" ] && [ ! -L "$ROOT/build/Stoguard.app" ]; then
  cp -R "$ROOT/build/Stoguard.app" "$STAGING/"
elif [ -d "$ROOT/build/VACS.app" ]; then
  cp -R "$ROOT/build/VACS.app" "$STAGING/Stoguard.app"
else
  echo "error: build/Stoguard.app missing" >&2
  exit 1
fi
ln -sf /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Stoguard ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

mkdir -p "$ROOT/website/downloads"
cp -f "$DMG" "$WEB_DMG"
# Keep older download names pointing at latest for bookmarks.
cp -f "$DMG" "$ROOT/website/downloads/Stoguard-0.4.1.dmg" 2>/dev/null || true
cp -f "$DMG" "$ROOT/website/downloads/Stoguard-0.4.0.dmg" 2>/dev/null || true

rm -rf "$STAGING"
echo "==> done: $DMG"
echo "==> copied to website/downloads/"
